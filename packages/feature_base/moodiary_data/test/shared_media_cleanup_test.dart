import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fast_image/fast_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

class _HeifDecoder implements IHeifDecoder {
  @override
  Future<String?> convert(String srcPath, {required String outputPath}) async {
    await File(outputPath).writeAsString('converted');
    return outputPath;
  }
}

class _BlockingHeifDecoder implements IHeifDecoder {
  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<String?> convert(String srcPath, {required String outputPath}) async {
    started.complete();
    await finish.future;
    await File(outputPath).writeAsString('converted');
    return outputPath;
  }
}

class _PausingRepairRepository extends DiaryRepository {
  _PausingRepairRepository(super.database);

  final snapshotTaken = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<List<Diary>> getAllDiaries() async {
    final snapshot = await super.getAllDiaries();
    if (!snapshotTaken.isCompleted) {
      snapshotTaken.complete();
      await resume.future;
    }
    return snapshot;
  }
}

Diary _diary(
  String id, {
  List<String> images = const [],
  List<String> videos = const [],
  List<String> audios = const [],
  bool show = true,
}) {
  final content = jsonEncode({
    'type': 'doc',
    'content': [
      {
        'type': 'paragraph',
        'content': [
          {'type': 'text', 'text': 'Test diary'},
          for (final name in images)
            {
              'type': 'image',
              'attrs': {'src': name},
            },
          for (final name in videos)
            {
              'type': 'video',
              'attrs': {'filename': name},
            },
          for (final name in audios)
            {
              'type': 'audio',
              'attrs': {'filename': name},
            },
        ],
      },
    ],
  });
  final time = DateTime.utc(2026, 1, 1);
  return Diary(
    id: id,
    title: id,
    content: content,
    contentText: 'Test diary',
    time: time,
    lastModified: time,
    show: show,
    mood: .neutral,
    imageName: images,
    videoName: videos,
    audioName: audios,
    tags: const [],
    type: 'tiptap',
  );
}

void main() {
  late Directory root;
  late MoodiaryDatabase db;
  late DiaryRepository repo;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('shared_media_cleanup_');
    PlatformService.get().applicationSupportPath = root.path;
    PlatformService.get().applicationCachePath = root.path;
    await AppFiles.initCreateDir();
    FastImageRuntime.configure(
      imageDir: AppFiles.imageDir,
      thumbDir: AppFiles.imageThumbDir,
    );
    getIt.registerSingleton<IKVStorage>(MemoryKVStorage());
  });

  setUp(() {
    db = MoodiaryDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    repo = DiaryRepository(db);
  });

  tearDown(() async => db.close());

  tearDownAll(() async {
    await getIt.reset();
    await root.delete(recursive: true);
  });

  Future<File> media(String kind, String name) async {
    final file = File(AppFiles.getRealPath(kind, name));
    await file.writeAsString('file content for $name');
    return file;
  }

  test('permanent deletion preserves media used by another diary', () async {
    const image = 'image-shared.jpg';
    const video = 'video-shared.mp4';
    const audio = 'audio-shared.m4a';
    final imageFile = await media('image', image);
    final videoFile = await media('video', video);
    final audioFile = await media('audio', audio);
    final thumbnail = await media('video', 'thumbnail-shared.jpeg');
    await repo.insertDiaries([
      _diary('a', images: [image], videos: [video], audios: [audio]),
      _diary('b', images: [image], videos: [video], audios: [audio]),
    ]);

    expect(await repo.deleteADiary('a'), isTrue);

    expect(await repo.getDiaryByBusinessId('a'), isNull);
    final survivor = await repo.getDiaryByBusinessId('b');
    expect(survivor!.imageName, [image]);
    expect(survivor.videoName, [video]);
    expect(survivor.audioName, [audio]);
    for (final file in [imageFile, videoFile, audioFile, thumbnail]) {
      expect(await file.exists(), isTrue, reason: file.path);
    }
    expect(
      await TombstoneRepository(db).getByKey(SyncTombstone.diaryKey('a')),
      isNotNull,
    );
  });

  test('a recycled diary still protects its shared image', () async {
    const image = 'image-recycled.jpg';
    final file = await media('image', image);
    await repo.insertDiaries([
      _diary('delete', images: [image]),
      _diary('recycled', images: [image], show: false),
    ]);

    expect(await repo.deleteADiary('delete'), isTrue);

    expect((await repo.getDiaryByBusinessId('recycled'))!.show, isFalse);
    expect(await file.exists(), isTrue);
  });

  test(
    'a body reference missing from the media index still protects a file',
    () async {
      const image = 'image-missing-index.jpg';
      final file = await media('image', image);
      await repo.insertDiaries([
        _diary('delete', images: [image]),
        _diary('inconsistent', images: [image]).copyWith(imageName: const []),
      ]);

      expect(await repo.deleteADiary('delete'), isTrue);

      expect(
        (await repo.getDiaryByBusinessId('inconsistent'))!.imageName,
        isEmpty,
      );
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'an active media lease defers removal and the queue retries it',
    () async {
      const image = 'image-active.jpg';
      final file = await media('image', image);
      await repo.insertADiary(_diary('active', images: [image]));
      final lease = await MediaGuard().acquire(MediaType.image, image);
      try {
        expect(await repo.deleteADiary('active'), isTrue);
        expect(await file.exists(), isTrue);
        expect(await MediaCleanupQueue().pending(), isNotEmpty);
      } finally {
        await lease.release();
      }

      await repo.drainMediaCleanupQueue();
      expect(await file.exists(), isFalse);
    },
  );

  test('unparseable diary data defers cleanup until it is repaired', () async {
    const image = 'image-unknown-body.jpg';
    final file = await media('image', image);
    await repo.insertDiaries([
      _diary('delete', images: [image]),
      _diary('damaged').copyWith(content: '{invalid'),
    ]);

    expect(await repo.deleteADiary('delete'), isTrue);
    expect(await file.exists(), isTrue);
    expect(await MediaCleanupQueue().pending(), isNotEmpty);

    await repo.updateADiary(newDiary: _diary('damaged'));
    await repo.drainMediaCleanupQueue();
    expect(await file.exists(), isFalse);
  });

  test('legacy Isar data defers cleanup until migration finishes', () async {
    const image = 'image-legacy-blocked.jpg';
    final file = await media('image', image);
    final legacy = File(AppFiles.getRealPath('database', 'default.isar'));
    await legacy.writeAsString('legacy database fixture');
    await repo.insertADiary(_diary('delete-legacy', images: [image]));

    expect(await repo.deleteADiary('delete-legacy'), isTrue);
    expect(await file.exists(), isTrue);
    expect(await MediaCleanupQueue().pending(), isNotEmpty);

    await legacy.delete();
    await repo.drainMediaCleanupQueue();
    expect(await file.exists(), isFalse);
  });

  test('a saved assistant message protects its shared image', () async {
    const image = 'image-chat-shared.jpg';
    final file = await media('image', image);
    await repo.insertADiary(_diary('delete', images: [image]));
    await db
        .into(db.chatSessions)
        .insert(
          ChatSessionsCompanion.insert(
            id: 'session',
            providerId: 'provider',
            model: 'model',
            createdAt: 0,
            updatedAt: 0,
          ),
        );
    await db
        .into(db.chatMessages)
        .insert(
          ChatMessagesCompanion.insert(
            id: 'message',
            sessionId: 'session',
            role: 'user',
            content: 'image',
            createdAt: 0,
            imageName: const Value(image),
          ),
        );

    expect(await repo.deleteADiary('delete'), isTrue);

    expect((await db.select(db.chatMessages).get()).single.imageName, image);
    expect(await file.exists(), isTrue);
  });

  test('hard deletion of a draft preserves other diary references', () async {
    const image = 'image-draft-shared.jpg';
    final file = await media('image', image);
    await repo.insertDiaries([
      _diary('draft', images: [image]),
      _diary('saved', images: [image]),
    ]);

    expect(await repo.hardDeleteDiary('draft'), isTrue);

    expect(await repo.getDiaryByBusinessId('draft'), isNull);
    expect((await repo.getDiaryByBusinessId('saved'))!.imageName, [image]);
    expect(await file.exists(), isTrue);
  });

  test(
    'visibility change does not revive a permanently deleted diary',
    () async {
      const image = 'image-stale-visibility.jpg';
      final file = await media('image', image);
      final stale = _diary('stale-visibility', images: [image]);
      await repo.insertADiary(stale);
      expect(await repo.deleteADiary(stale.id), isTrue);
      expect(await file.exists(), isFalse);

      await repo.setVisibility(stale, show: true);

      expect(await repo.getDiaryByBusinessId(stale.id), isNull);
      expect(
        await TombstoneRepository(db)
            .getByKey(SyncTombstone.diaryKey(stale.id)),
        isNotNull,
      );
    },
  );

  test(
    'visibility change retains newer content instead of the stale snapshot',
    () async {
      final stale = _diary('stale-content');
      await repo.insertADiary(stale);
      await repo.updateADiary(newDiary: stale.copyWith(title: 'New title'));

      await repo.setVisibility(stale, show: false);

      final current = (await repo.getDiaryByBusinessId(stale.id))!;
      expect(current.title, 'New title');
      expect(current.show, isFalse);
    },
  );

  test('removing the last reference by editing queues and cleans it', () async {
    const image = 'image-edit-removed.jpg';
    final file = await media('image', image);
    await repo.insertADiary(_diary('editing', images: [image]));

    await repo.updateADiary(newDiary: _diary('editing'));

    expect((await repo.getDiaryByBusinessId('editing'))!.imageName, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test('optimizing a shared HEIC updates all diaries and preserves derivatives', () async {
    const heic = 'image-optimized.heic';
    const jpeg = 'image-optimized.jpg';
    final original = await media('image', heic);
    final thumb = File(
      '${AppFiles.imageThumbDir}${Platform.pathSeparator}image-optimized_512.jpg',
    );
    await thumb.writeAsString('existing derivative');
    await repo.insertDiaries([
      _diary('optimize-a', images: [heic]),
      _diary('optimize-b', images: [heic]),
    ]);
    getIt.registerSingleton<DiaryRepository>(repo);
    getIt.registerSingleton<IHeifDecoder>(_HeifDecoder());
    try {
      final result = await ImageOptimizer.run();

      expect(result.heicConverted, 2);
      expect((await repo.getDiaryByBusinessId('optimize-a'))!.imageName, [
        jpeg,
      ]);
      expect((await repo.getDiaryByBusinessId('optimize-b'))!.imageName, [
        jpeg,
      ]);
      expect(await original.exists(), isFalse);
      expect(await File(AppFiles.getRealPath('image', jpeg)).exists(), isTrue);
      expect(await thumb.readAsString(), 'existing derivative');
    } finally {
      await getIt.unregister<IHeifDecoder>();
      await getIt.unregister<DiaryRepository>();
    }
  });

  test(
    'optimization does not overwrite an edit made during conversion',
    () async {
      const heic = 'image-optimize-race.heic';
      const jpeg = 'image-optimize-race.jpg';
      final original = await media('image', heic);
      final diary = _diary('optimize-race', images: [heic]);
      await repo.insertADiary(diary);
      final decoder = _BlockingHeifDecoder();
      getIt.registerSingleton<DiaryRepository>(repo);
      getIt.registerSingleton<IHeifDecoder>(decoder);
      try {
        final optimization = ImageOptimizer.run();
        await decoder.started.future;
        await repo.updateADiary(newDiary: diary.copyWith(title: 'Newer edit'));
        decoder.finish.complete();
        final result = await optimization;

        final current = (await repo.getDiaryByBusinessId(diary.id))!;
        expect(current.title, 'Newer edit');
        expect(current.imageName, [heic]);
        expect(result.heicConverted, 0);
        expect(result.heicFailed, 1);
        expect(await original.exists(), isTrue);
        expect(
          await File(AppFiles.getRealPath('image', jpeg)).exists(),
          isFalse,
        );
      } finally {
        if (!decoder.finish.isCompleted) decoder.finish.complete();
        await getIt.unregister<IHeifDecoder>();
        await getIt.unregister<DiaryRepository>();
      }
    },
  );

  test('repair does not revive a diary deleted after its snapshot', () async {
    const image = 'image-repair-deleted.jpg';
    final file = await media('image', image);
    final diary = _diary(
      'repair-deleted',
      images: [image],
    ).copyWith(contentText: 'stale index');
    await repo.insertADiary(diary);
    final repair = _PausingRepairRepository(db);
    final events = <DiaryEvent>[];
    final sub = repair.diaryEvents.listen(events.add);
    try {
      final pending = repair.repairData();
      await repair.snapshotTaken.future;
      expect(await repo.deleteADiary(diary.id), isTrue);
      expect(await file.exists(), isTrue, reason: 'repair still uses media');
      repair.resume.complete();

      final result = await pending;
      expect(result.scanned, 1);
      expect(result.changed, 0);
      expect(await repo.getDiaryByBusinessId(diary.id), isNull);
      expect(await file.exists(), isFalse);
      expect(events.whereType<DiaryUpdated>(), isEmpty);
    } finally {
      if (!repair.resume.isCompleted) repair.resume.complete();
      await sub.cancel();
    }
  });

  test('repair does not overwrite an edit made after its snapshot', () async {
    final diary = _diary('repair-updated').copyWith(contentText: 'stale index');
    await repo.insertADiary(diary);
    final repair = _PausingRepairRepository(db);
    try {
      final pending = repair.repairData();
      await repair.snapshotTaken.future;
      await repo.updateADiary(newDiary: diary.copyWith(title: 'Newer title'));
      repair.resume.complete();

      final result = await pending;
      expect(result.changed, 0);
      expect((await repo.getDiaryByBusinessId(diary.id))!.title, 'Newer title');
    } finally {
      if (!repair.resume.isCompleted) repair.resume.complete();
    }
  });

  test('the last unshared diary reference can be deleted', () async {
    const video = 'video-last.mp4';
    final videoFile = await media('video', video);
    final thumbnail = await media('video', 'thumbnail-last.jpeg');
    await repo.insertADiary(_diary('last', videos: [video]));

    expect(await repo.deleteADiary('last'), isTrue);

    expect(await repo.getDiaryByBusinessId('last'), isNull);
    expect(await videoFile.exists(), isFalse);
    expect(await thumbnail.exists(), isFalse);
  });

  test(
    'cleanup counts only files actually removed, including thumbnails',
    () async {
      final thumbnail = await media('video', 'thumbnail-count.jpeg');
      final result = await repo.cleanMediaCandidates([
        const MediaKey(MediaType.image, 'image-missing.jpg'),
        const MediaKey(MediaType.video, 'video-count.mp4'),
      ]);

      expect(result.deleted, 1);
      expect(result.retained, 0);
      expect(result.deferred, 0);
      expect(await thumbnail.exists(), isFalse);
    },
  );

  test('repository disposal stops cleanup retries and closes events', () async {
    Timer? timer;
    var streamClosed = false;
    final sub = repo.diaryEvents.listen(
      (_) {},
      onDone: () => streamClosed = true,
    );
    await runZoned(
      () async {
        repo.startMediaCleanup();
        await repo.dispose();
        await repo.dispose();
      },
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          timer = parent.createPeriodicTimer(zone, duration, callback);
          return timer!;
        },
      ),
    );

    expect(timer, isNotNull);
    expect(timer!.isActive, isFalse);
    expect(streamClosed, isTrue);
    expect(repo.startMediaCleanup, throwsStateError);
    await sub.cancel();
  });
}
