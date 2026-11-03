import 'dart:io';

import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_controller.g.dart';

@riverpod
class MediaItems extends _$MediaItems with LoadMoreMixin<MediaItem> {
  @override
  int get pageSize => 60;

  @override
  FutureOr<List<MediaItem>> build({required MediaType type}) async {
    final sub = getIt<DiaryRepository>().diaryEvents.listen(_applyChange);
    ref.onDispose(sub.cancel);
    return init();
  }

  @override
  Future<Iterable<MediaItem>?> load({required int limit, required int offset}) {
    return getIt<DiaryRepository>().getMediaItems(
      type: type,
      offset: offset,
      limit: limit,
    );
  }

  List<String> _namesOf(Diary d) => switch (type) {
    .image => d.imageName,
    .audio => d.audioName,
    .video => d.videoName,
  };

  void _applyChange(DiaryEvent event) {
    final list = state.value;
    if (list == null) {
      markMissedEvent();
      return;
    }
    switch (event) {
      case DiaryDeleted(:final id):
        final without = list.where((m) => m.diaryId != id).toList();
        if (without.length != list.length) state = .data(without);
      case DiaryCreated(:final diary) || DiaryUpdated(:final diary):
        final without = list.where((m) => m.diaryId != diary.id).toList();
        final removed = without.length != list.length;
        final names = diary.show ? _namesOf(diary) : const <String>[];
        if (names.isEmpty) {
          if (removed) state = .data(without);
          return;
        }
        final fresh = [
          for (final name in names)
            MediaItem(fileName: name, diaryId: diary.id, time: diary.time),
        ];
        if (!noMore &&
            without.isNotEmpty &&
            MediaItem.compare(fresh.first, without.last) > 0) {
          if (removed) state = .data(without);
          return;
        }
        var at = without.length;
        for (var i = 0; i < without.length; i++) {
          if (MediaItem.compare(fresh.first, without[i]) < 0) {
            at = i;
            break;
          }
        }
        state = .data([
          ...without.sublist(0, at),
          ...fresh,
          ...without.sublist(at),
        ]);
    }
  }
}

@riverpod
class MediaCleanupController extends _$MediaCleanupController {
  @override
  void build() {}

  Future<MediaCleanupReport> scan() async {
    final used = await getIt<DiaryRepository>().collectReferencedMedia();
    final report = await AppFiles.scanOrphanMedia(
      usedImages: used.images,
      usedAudios: used.audios,
      usedVideos: used.videos,
    );
    // Derived thumbnail files have no independent reference identity. Leave
    // them to the original image's guarded cleanup rather than deleting an
    // old scan result after it may have become relevant again.
    final paths = <String>[];
    var bytes = 0;
    for (final path in report.paths) {
      if (_keyForPath(path) == null) continue;
      try {
        bytes += await File(path).length();
        paths.add(path);
      } on PathNotFoundException {
        // The filesystem changed since the scan.
      }
    }
    return MediaCleanupReport(paths: paths, bytes: bytes);
  }

  MediaKey? _keyForPath(String path) {
    for (final type in MediaType.values) {
      if (p.equals(p.dirname(path), AppFiles.getRealPath(type.value, ''))) {
        return MediaKey(type, p.basename(path));
      }
    }
    return null;
  }

  Future<MediaCleanupOutcome> clean(MediaCleanupReport report) async {
    final outcome = await getIt<DiaryRepository>().cleanMediaCandidates([
      for (final path in report.paths) ?_keyForPath(path),
    ]);
    if (outcome.deferred > 0) {
      throw StateError('Media cleanup could not safely complete');
    }
    return outcome;
  }
}
