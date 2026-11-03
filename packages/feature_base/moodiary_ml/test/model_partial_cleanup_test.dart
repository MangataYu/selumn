import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_lint/testing.dart';
import 'package:moodiary_ml/moodiary_ml.dart';
import 'package:moodiary_ml/src/embedding_models.dart'
    show cleanModelPartEntries;
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

class _BlockingHttp extends Fake implements IHttpClient {
  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<void> downloadFile(
    String url,
    String destPath, {
    Map<String, dynamic>? headers,
    void Function(int received, int total)? onProgress,
    Duration? timeout,
    bool silent = false,
    CancelToken? cancel,
  }) async {
    await File(destPath).writeAsString('partial');
    started.complete();
    await finish.future;
    throw StateError('download interrupted');
  }
}

class _DeniedFile extends Fake implements File {
  _DeniedFile(this.path);

  @override
  final String path;

  @override
  Future<int> length() async => throw const FileSystemException('denied');
}

void main() {
  late Directory root;
  late EmbeddingModelManager manager;
  late _BlockingHttp http;
  final spec = embeddingModelCatalog.first;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('model_cleanup_test');
    PlatformService.get().applicationSupportPath = root.path;
    PlatformService.get().applicationCachePath = root.path;
  });

  setUp(() async {
    getIt.registerSingleton<IKVStorage>(MemoryKVStorage());
    http = _BlockingHttp();
    manager = EmbeddingModelManager(http);
    await Directory(EmbeddingModelManager.modelsDirPath).create();
  });

  tearDown(() async {
    final dir = Directory(EmbeddingModelManager.modelsDirPath);
    if (await dir.exists()) await dir.delete(recursive: true);
    await getIt.reset();
  });

  tearDownAll(() async => root.delete(recursive: true));

  test(
    'cleans known partials but preserves completed models and unknown files',
    () async {
      final part = File('${manager.modelPathOf(spec)}.part');
      final tokenizerPart = File('${manager.tokenizerPathOf(spec)}.part');
      final completed = File(manager.modelPathOf(spec));
      final unknown = File(
        '${EmbeddingModelManager.modelsDirPath}/unknown.part',
      );
      await part.writeAsString('abc');
      await tokenizerPart.writeAsString('12345');
      await completed.writeAsString('completed');
      await unknown.writeAsString('unknown');

      final result = await manager.cleanIncompleteDownloads();

      expect(result, (deletedFiles: 2, deletedBytes: 8, failedFiles: 0));
      expect(await part.exists(), isFalse);
      expect(await tokenizerPart.exists(), isFalse);
      expect(await completed.readAsString(), 'completed');
      expect(await unknown.readAsString(), 'unknown');
    },
  );

  test('reports unsafe file types while cleaning other partials', () async {
    final part = File('${manager.modelPathOf(spec)}.part');
    await part.writeAsString('abc');
    final unsafe = Directory('${manager.tokenizerPathOf(spec)}.part');
    await unsafe.create();
    await File('${unsafe.path}/keep').writeAsString('keep');

    final result = await manager.cleanIncompleteDownloads();

    expect(result, (deletedFiles: 1, deletedBytes: 3, failedFiles: 1));
    expect(await File('${unsafe.path}/keep').readAsString(), 'keep');
  });

  test('waits for the entire download before checking partials', () async {
    final download = manager.download(spec);
    final failure = expectLater(download, throwsStateError);
    await http.started.future;
    var completed = false;
    final cleanup = manager.cleanIncompleteDownloads().then((result) {
      completed = true;
      return result;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(
      await File('${manager.tokenizerPathOf(spec)}.part').exists(),
      isTrue,
    );

    http.finish.complete();
    await failure;
    expect(await cleanup, (deletedFiles: 1, deletedBytes: 7, failedFiles: 0));
    expect(
      await File('${manager.tokenizerPathOf(spec)}.part').exists(),
      isFalse,
    );
  });

  test('waits for a model lock held by another process', () async {
    final part = File('${manager.modelPathOf(spec)}.part');
    await part.writeAsString('abc');
    final executable = Platform.isWindows ? 'dart.exe' : 'dart';
    // Flutter tests run under flutter_tester, alongside the engine artifacts
    // in bin/cache/artifacts/engine/<platform>. Use the same SDK's Dart where
    // available, and otherwise allow standard PATH-based SDK installations.
    final cache = File(Platform.resolvedExecutable).parent.parent.parent.parent;
    final sdkDart = File('${cache.path}/dart-sdk/bin/$executable');
    final dart = await sdkDart.exists() ? sdkDart.path : executable;
    final holder = await Process.start(dart, [
      '$repoRoot/packages/feature_base/moodiary_ml/test/fixtures/model_lock_holder.dart',
      '${Directory(EmbeddingModelManager.modelsDirPath).parent.path}/.embedding-download.lock',
    ]);
    addTearDown(() async {
      holder.kill();
      await holder.exitCode;
    });
    final ready = await holder.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    expect(ready, 'locked');

    var completed = false;
    final cleanup = manager.cleanIncompleteDownloads().then((result) {
      completed = true;
      return result;
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(completed, isFalse);
    expect(await part.exists(), isTrue);

    holder.stdin.writeln('release');
    await holder.stdin.flush();
    expect(await holder.exitCode, 0);
    expect(await cleanup, (deletedFiles: 1, deletedBytes: 3, failedFiles: 0));
  });

  test('reports per-file permission failures', () async {
    final file = _DeniedFile('${manager.modelPathOf(spec)}.part');
    final result = await cleanModelPartEntries(Stream.value(file));
    expect(result, (deletedFiles: 0, deletedBytes: 0, failedFiles: 1));
  });

  test('reports failure to list the model directory', () async {
    final result = await cleanModelPartEntries(
      Stream.error(const FileSystemException('denied')),
    );
    expect(result, (deletedFiles: 0, deletedBytes: 0, failedFiles: 1));
  });

  test('keeps deleted counts when directory listing fails midway', () async {
    final file = File('${manager.modelPathOf(spec)}.part');
    await file.writeAsString('abc');
    final entries = Stream<FileSystemEntity>.multi((controller) {
      controller.add(file);
      controller.addError(const FileSystemException('denied'));
      controller.close();
    });
    final result = await cleanModelPartEntries(entries);
    expect(result, (deletedFiles: 1, deletedBytes: 3, failedFiles: 1));
    expect(await file.exists(), isFalse);
  });

  test('reset waits for a download and preserves the shared lock', () async {
    final download = manager.download(spec);
    final failure = expectLater(download, throwsStateError);
    await http.started.future;
    var completed = false;
    final reset = EmbeddingModelManager.clearModelFiles().then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    http.finish.complete();
    await failure;
    await reset;
    expect(
      await Directory(EmbeddingModelManager.modelsDirPath).exists(),
      isFalse,
    );
    expect(
      await File('${root.path}/.embedding-download.lock').exists(),
      isTrue,
    );
  });

  test('deleting a model waits for its download', () async {
    final download = manager.download(spec);
    final failure = expectLater(download, throwsStateError);
    await http.started.future;
    await File(manager.modelPathOf(spec)).writeAsString('model');
    var completed = false;
    final deletion = manager.delete(spec).then((_) {
      completed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    http.finish.complete();
    await failure;
    await deletion;
    expect(await File(manager.modelPathOf(spec)).exists(), isFalse);
  });
}
