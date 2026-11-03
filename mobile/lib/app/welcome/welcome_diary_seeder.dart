import 'dart:io';

import 'package:flutter/services.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

import 'welcome_diary_content.dart';

/// Captures first-install eligibility before version migration records a version,
/// then creates the entry once the app's language has been resolved.
class WelcomeDiarySeeder {
  WelcomeDiarySeeder({
    required this.repository,
    required this.storage,
    required this.imageDirectory,
    AssetBundle? assets,
    MediaGuard? mediaGuard,
  }) : _assets = assets ?? rootBundle,
       _mediaGuard = mediaGuard ?? MediaGuard();

  static const imageAsset = 'res/welcome/first-page.jpg';

  final DiaryRepository repository;
  final IKVStorage storage;
  final Directory imageDirectory;
  final AssetBundle _assets;
  final MediaGuard _mediaGuard;

  String? get _state => storage.get<String>(MoodiaryKVs.welcomeDiaryState.name);

  void _setState(String value) =>
      storage.set<String>(MoodiaryKVs.welcomeDiaryState.name, value);

  void prepare({
    required bool hadDatabase,
    required bool hasLegacyDatabase,
    required bool legacyMigrationPending,
  }) {
    if (legacyMigrationPending || _state != null) return;
    final existingInstallation =
        hadDatabase ||
        hasLegacyDatabase ||
        storage.get<String>(MoodiaryKVs.appVersion.name) != null ||
        storage.get<bool>(MoodiaryKVs.firstStart.name) == false;
    _setState(existingInstallation ? 'skipped' : 'pending');
  }

  Future<void> seed({required bool migrationReady}) async {
    if (!migrationReady || _state != 'pending') return;
    // Includes the recycle bin. A restored/imported entry or a previous insert
    // whose completion marker failed must never be overwritten on retry.
    if (await repository.countAllDiaries() != 0) {
      _setState('skipped');
      return;
    }

    final bytes = await _assets.load(imageAsset);
    final imageName = 'image-${uuidV7()}.jpg';
    final image = File('${imageDirectory.path}/$imageName');
    final diary = buildWelcomeDiary(imageName: imageName);
    final lease = await _mediaGuard.acquire(MediaType.image, imageName);
    try {
      try {
        await image.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true,
        );
        await repository.insertADiary(diary);
      } catch (error, stackTrace) {
        try {
          // An insert can fail after its database commit (for example while
          // notifying listeners). Never remove an already referenced image.
          if (await repository.getDiaryByBusinessId(diary.id) == null &&
              await image.exists()) {
            await image.delete();
          }
        } catch (cleanupError, cleanupStack) {
          logger.e(
            'welcome image cleanup failed',
            error: cleanupError,
            stackTrace: cleanupStack,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      await lease.release();
    }
    storage.set<bool>(MoodiaryKVs.syncPendingLocal.name, true);
    _setState('completed');
  }
}
