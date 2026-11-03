import 'dart:io';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, visibleForTesting;
import 'package:injectable/injectable.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:synchronized/synchronized.dart';

import 'hf_hub.dart';
import 'onnx_embedding_backend.dart';

class EmbeddingModelSpec {
  final String id;

  final String displayName;

  final int dim;

  final String modelHfPath;

  final String tokenizerHfPath;

  final int sizeBytes;

  final String queryPrefix;

  final String passagePrefix;

  final int contextSize;

  final String padToken;

  const EmbeddingModelSpec({
    required this.id,
    required this.displayName,
    required this.dim,
    required this.modelHfPath,
    required this.tokenizerHfPath,
    required this.sizeBytes,
    required this.queryPrefix,
    this.passagePrefix = '',
    this.contextSize = 512,
    this.padToken = '<|endoftext|>',
  });

  String get modelFileName => '$id.onnx';

  String get tokenizerFileName => '$id.tokenizer.json';
}

const embeddingModelCatalog = <EmbeddingModelSpec>[
  EmbeddingModelSpec(
    id: 'qwen3-embedding-0.6b-int8',
    displayName: 'Qwen3-Embedding 0.6B',
    dim: 1024,
    modelHfPath: 'onnx-community/Qwen3-Embedding-0.6B-ONNX/resolve/main/onnx/model_int8.onnx',
    tokenizerHfPath:
        'onnx-community/Qwen3-Embedding-0.6B-ONNX/resolve/main/tokenizer.json',
    sizeBytes: 624951296, // 596 MB
    // query 侧带 Instruct 前缀，"Query:" 后不加空格；passage 侧裸文本。
    queryPrefix: 'Instruct: Given a diary search query, retrieve relevant diary passages\nQuery:',
  ),
];

typedef ModelPartialCleanup = ({
  int deletedFiles,
  int deletedBytes,
  int failedFiles,
});

enum EmbeddingModelOperationKind { activate, disable, delete }

class EmbeddingModelOperation {
  const EmbeddingModelOperation({
    required this.kind,
    required this.modelId,
    this.progress = 0,
  });

  final EmbeddingModelOperationKind kind;
  final String modelId;

  /// Download fraction; a negative value means the model is being verified.
  final double progress;
}

// Dart's process-level file locks do not serialize isolates within a process
// on every platform, so retain the in-isolate lock as well.
final _modelDownloadLock = Lock();

Future<T> _withModelDownloadLock<T>(Future<T> Function() operation) =>
    _modelDownloadLock.synchronized(() async {
      final dir = Directory(EmbeddingModelManager.modelsDirPath);
      await dir.parent.create(recursive: true);
      final lock = await File('${dir.parent.path}/.embedding-download.lock')
          .open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.blockingExclusive);
        final type = await FileSystemEntity.type(dir.path, followLinks: false);
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
          throw FileSystemException(
            'Model directory is not a directory',
            dir.path,
          );
        }
        await dir.create(recursive: true);
        return await operation();
      } finally {
        await lock.close();
      }
    });

@visibleForTesting
Future<ModelPartialCleanup> cleanModelPartEntries(
  Stream<FileSystemEntity> entries,
) async {
  final names = <String>{
    for (final spec in embeddingModelCatalog) ...[
      '${spec.modelFileName}.part',
      '${spec.tokenizerFileName}.part',
    ],
  };
  var deletedFiles = 0;
  var deletedBytes = 0;
  var failedFiles = 0;
  try {
    await for (final entry in entries) {
      var name = Uri.file(entry.path).pathSegments.last;
      if (Platform.isWindows) name = name.toLowerCase();
      if (!names.contains(name)) continue;
      if (entry is! File) {
        failedFiles++;
        continue;
      }
      try {
        final bytes = await entry.length();
        await entry.delete();
        deletedFiles++;
        deletedBytes += bytes;
      } on PathNotFoundException {
        // A concurrent external cleanup already removed this file.
      } on FileSystemException catch (e, s) {
        failedFiles++;
        logger.e('incomplete model cleanup failed', error: e, stackTrace: s);
      }
    }
  } on FileSystemException catch (e, s) {
    failedFiles++;
    logger.e('incomplete model listing failed', error: e, stackTrace: s);
  }
  return (
    deletedFiles: deletedFiles,
    deletedBytes: deletedBytes,
    failedFiles: failedFiles,
  );
}

@LazySingleton()
class EmbeddingModelManager {
  final IHttpClient _http;

  EmbeddingModelManager(this._http);

  final _operation = ValueNotifier<EmbeddingModelOperation?>(null);
  Object? _operationToken;

  /// Shared state for model-management screens that may be opened or closed
  /// while a download or another operation is still running.
  ValueListenable<EmbeddingModelOperation?> get operation => _operation;

  /// Starts one management operation atomically. Returns false when another
  /// operation is already active; the operation always clears on completion.
  Future<bool> runOperation({
    required EmbeddingModelOperationKind kind,
    required String modelId,
    required Future<void> Function(void Function(double) progress) action,
  }) async {
    if (_operationToken != null) return false;
    final token = Object();
    _operationToken = token;
    _operation.value = EmbeddingModelOperation(kind: kind, modelId: modelId);
    try {
      await action((progress) {
        if (!identical(_operationToken, token)) return;
        _operation.value = EmbeddingModelOperation(
          kind: kind,
          modelId: modelId,
          progress: progress,
        );
      });
      return true;
    } finally {
      if (identical(_operationToken, token)) {
        _operationToken = null;
        _operation.value = null;
      }
    }
  }

  static EmbeddingModelSpec? byId(String id) {
    for (final spec in embeddingModelCatalog) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  EmbeddingModelSpec? get active =>
      byId(MoodiaryKVs.embeddingModelId.get() ?? '');

  String modelPathOf(EmbeddingModelSpec spec) =>
      AppFiles.getRealPath('model', spec.modelFileName);

  String tokenizerPathOf(EmbeddingModelSpec spec) =>
      AppFiles.getRealPath('model', spec.tokenizerFileName);

  static String get modelsDirPath =>
      File(AppFiles.getRealPath('model', 'x')).parent.path;

  bool isDownloaded(EmbeddingModelSpec spec) =>
      File(modelPathOf(spec)).existsSync() &&
      File(tokenizerPathOf(spec)).existsSync();

  Future<void> download(
    EmbeddingModelSpec spec, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) => _withModelDownloadLock(() async {
    if (isDownloaded(spec)) return;
    final modelPath = modelPathOf(spec);
    final tokenizerPath = tokenizerPathOf(spec);
    await Directory(modelPath).parent.create(recursive: true);

    if (!File(tokenizerPath).existsSync()) {
      final tokenizerPart = '$tokenizerPath.part';
      await _http.downloadFile(
        HfHub.resolve(spec.tokenizerHfPath),
        tokenizerPart,
        cancel: cancel,
      );
      await File(tokenizerPart).rename(tokenizerPath);
    }

    final modelPart = '$modelPath.part';
    await _http.downloadFile(
      HfHub.resolve(spec.modelHfPath),
      modelPart,
      onProgress: onProgress,
      cancel: cancel,
    );
    try {
      await _probe(spec, modelPart, tokenizerPath);
    } catch (e, s) {
      logger.e('embedding model probe failed', error: e, stackTrace: s);
      await AppFiles.deleteFile(modelPart);
      rethrow;
    }
    await File(modelPart).rename(modelPath);
  });

  /// Deletes only known incomplete model downloads after active downloads end.
  /// Completed models and unknown files are never candidates.
  Future<ModelPartialCleanup> cleanIncompleteDownloads() =>
      _withModelDownloadLock(() async {
        return cleanModelPartEntries(
          Directory(modelsDirPath).list(followLinks: false),
        );
      });

  /// Clears model files during the startup recovery reset while holding the
  /// same cross-process lock used by downloads and cleanup.
  static Future<void> clearModelFiles() =>
      _withModelDownloadLock(() => AppFiles.deleteDir(modelsDirPath));

  Future<void> activate(EmbeddingModelSpec spec) async {
    if (!isDownloaded(spec)) {
      throw StateError('model ${spec.id} not downloaded');
    }
    if (MoodiaryKVs.embeddingModelId.get() == spec.id) return;
    MoodiaryKVs.embeddingModelId.set(spec.id);
    MoodiaryKVs.embeddingDim.set(spec.dim);
    MoodiaryKVs.embeddingIndexStale.set(true);
  }

  void deactivate() {
    MoodiaryKVs.embeddingModelId.set('');
    MoodiaryKVs.embeddingDim.set(0);
    MoodiaryKVs.embeddingIndexStale.set(false);
  }

  Future<void> delete(EmbeddingModelSpec spec) =>
      _withModelDownloadLock(() async {
        if (active?.id == spec.id) deactivate();
        await AppFiles.deleteFile(modelPathOf(spec));
        await AppFiles.deleteFile(tokenizerPathOf(spec));
      });

  Future<void> _probe(
    EmbeddingModelSpec spec,
    String modelPath,
    String tokenizerPath,
  ) async {
    final backend = OnnxEmbeddingBackend();
    try {
      await backend.load(
        modelPath,
        tokenizerPath: tokenizerPath,
        padToken: spec.padToken,
        contextSize: spec.contextSize,
      );
      final vectors = await backend.embed(const ['探测']);
      if (vectors.single.length != spec.dim) {
        throw StateError(
          'dim mismatch: expect ${spec.dim}, got ${vectors.single.length}',
        );
      }
    } finally {
      await backend.unload();
    }
  }
}
