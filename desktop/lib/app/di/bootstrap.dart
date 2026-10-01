import 'dart:async';

import 'package:fast_image/fast_image.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_sync/moodiary_sync.dart';

Future<void> bootstrapPlatform() async {
  await PlatformService.get().init();
  await AppFiles.initCreateDir();
  FastImageRuntime.configure(
    imageDir: AppFiles.imageDir,
    thumbDir: AppFiles.imageThumbDir,
    log: logger.d,
  );
  AppLogger.configure(logFilePath: AppFiles.getErrorLogPath());
}

void initializeUsageStartTime() {
  if (MmkvKVStorage.legacyMigrationPending) return;
  final storage = getIt<IKVStorage>();
  final startTime = storage.get<int>(MoodiaryKVs.startTime.name);
  if (startTime != null && startTime > 0) return;
  storage.set<int>(
    MoodiaryKVs.startTime.name,
    DateTime.now().millisecondsSinceEpoch,
  );
}

void runStartupMaintenance() {
  unawaited(purgeExpiredTombstones());
  unawaited(purgeSyncMediaTemp());
  unawaited(getIt<EmbedIndexService>().drain());
  getIt<EmbedQueueWatcher>().start();
}
