import 'dart:io';

import 'package:fast_image/fast_image.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

import 'diary_derive.dart';
import 'diary_repository.dart';

class ImageOptimizer {
  ImageOptimizer._();

  static const _heifSuffixes = ['.heic', '.heif'];

  static Future<ImageOptimizeReport> run({
    void Function(int done, int total)? onProgress,
  }) async {
    final repo = getIt<DiaryRepository>();
    final lease = await MediaGuard().acquire(MediaType.image, '');
    try {
      return await _run(repo, onProgress);
    } finally {
      await lease.release();
      await repo.drainMediaCleanupQueue();
    }
  }

  static Future<ImageOptimizeReport> _run(
    DiaryRepository repo,
    void Function(int done, int total)? onProgress,
  ) async {
    final heicDiaries = await repo.getDiariesReferencingMedia(
      kind: .image,
      suffixes: _heifSuffixes,
    );
    final heicTotal = heicDiaries.fold(
      0,
      (n, d) => n + d.imageName.where(_isHeif).length,
    );
    final total =
        heicTotal + (await repo.collectReferencedMedia()).images.length;
    var done = 0;
    onProgress?.call(done, total);

    var converted = 0;
    var failed = 0;
    for (final diary in heicDiaries) {
      final renamed = <String, String>{};
      for (final old in diary.imageName.where(_isHeif)) {
        final next = '${old.substring(0, old.lastIndexOf('.'))}.jpg';
        // Record files created by this attempt before writing them. If the
        // diary changes during conversion, a later safe retry can recover the
        // new file; an already existing file is never claimed by this attempt.
        if (!await File(AppFiles.getRealPath('image', next)).exists()) {
          await MediaCleanupQueue().enqueue([MediaKey(MediaType.image, next)]);
        }
        if (await _convert(old, next)) {
          renamed[old] = next;
        } else {
          failed++;
        }
        onProgress?.call(++done, total);
      }
      if (renamed.isEmpty) continue;
      var content = diary.content;
      renamed.forEach((old, next) => content = content.replaceAll(old, next));
      final updated = await repo.updateADiaryIfUnchanged(
        expected: diary,
        newDiary: withDerivedMedia(touched(diary.copyWith(content: content))),
      );
      if (updated) {
        converted += renamed.length;
      } else {
        failed += renamed.length;
      }
    }

    final images = (await repo.collectReferencedMedia()).images;
    for (final name in images) {
      final path = AppFiles.getRealPath('image', name);
      if (await File(path).exists()) await FastImageDerivatives.warm(path);
      onProgress?.call(++done, total);
    }

    return ImageOptimizeReport(
      images: images.length,
      heicConverted: converted,
      heicFailed: failed,
    );
  }

  static Future<bool> _convert(String oldName, String newName) async {
    final src = AppFiles.getRealPath('image', oldName);
    final dst = AppFiles.getRealPath('image', newName);
    if (await File(dst).exists()) return true;
    if (!await File(src).exists()) return false;
    final part = AppFiles.getRealPath('image', 'heif-${uuidV7()}.jpg');
    try {
      final out = await getIt<IHeifDecoder>().convert(src, outputPath: part);
      if (out == null) return false;
      await File(part).rename(dst);
      return true;
    } catch (e) {
      logger.d('HEIC -> JPG failed: $oldName ($e)');
      return false;
    } finally {
      try {
        await File(part).delete();
      } catch (_) {}
    }
  }

  static bool _isHeif(String name) {
    final lower = name.toLowerCase();
    return _heifSuffixes.any(lower.endsWith);
  }
}

class ImageOptimizeReport {
  final int images;

  final int heicConverted;

  final int heicFailed;

  const ImageOptimizeReport({
    required this.images,
    required this.heicConverted,
    required this.heicFailed,
  });
}
