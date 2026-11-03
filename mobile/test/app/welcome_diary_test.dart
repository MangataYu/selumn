import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/welcome/welcome_diary_seeder.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

class _DiaryRepository extends Fake implements DiaryRepository {
  final List<Diary> diaries = [];
  int insertCalls = 0;
  bool failInsert = false;
  bool failAfterInsert = false;
  Future<void> Function()? onInsert;

  @override
  Future<int> countAllDiaries() async => diaries.length;

  @override
  Future<void> insertADiary(
    Diary diary, {
    bool fromSync = false,
    IndexMode index = IndexMode.inline,
  }) async {
    insertCalls++;
    await onInsert?.call();
    if (failInsert) throw StateError('database unavailable');
    diaries.add(diary);
    if (failAfterInsert) throw StateError('notification unavailable');
  }

  @override
  Future<Diary?> getDiaryByBusinessId(String id) async {
    for (final diary in diaries) {
      if (diary.id == id) return diary;
    }
    return null;
  }
}

class _Assets extends CachingAssetBundle {
  int loads = 0;
  bool failLoad = false;

  @override
  Future<ByteData> load(String key) async {
    expect(key, WelcomeDiarySeeder.imageAsset);
    loads++;
    if (failLoad) throw StateError('asset unavailable');
    // The bundle may return a view of a larger buffer.
    return ByteData.view(Uint8List.fromList([0, 1, 2, 3, 0]).buffer, 1, 3);
  }
}

class _FailingCompletionStorage extends IKVStorage {
  final MemoryKVStorage memory = MemoryKVStorage();

  @override
  Future<void> init() async {}

  @override
  T? get<T extends Object>(String key) => memory.get<T>(key);

  @override
  void set<T extends Object>(String key, T value) {
    if (key == MoodiaryKVs.welcomeDiaryState.name && value == 'completed') {
      throw StateError('completion marker unavailable');
    }
    memory.set<T>(key, value);
    super.set(key, value);
  }

  @override
  void remove(String key) {
    memory.remove(key);
    super.remove(key);
  }

  @override
  void clear() => memory.clear();
}

Diary _existingDiary({bool show = true}) => Diary(
  id: 'existing-diary',
  title: 'Existing diary',
  content: '{"type":"doc","content":[]}',
  contentText: '',
  time: DateTime.utc(2026),
  lastModified: DateTime.utc(2026),
  show: show,
  mood: DiaryMood.neutral,
  imageName: const [],
  audioName: const [],
  videoName: const [],
  tags: const [],
  type: DiaryType.tiptap.value,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _DiaryRepository repository;
  late MemoryKVStorage storage;
  late Directory imageDirectory;
  late Directory supportDirectory;
  late MediaGuard mediaGuard;
  late _Assets assets;
  late WelcomeDiarySeeder seeder;

  setUp(() async {
    await LocaleSettings.setLocale(AppLocale.zh);
    repository = _DiaryRepository();
    storage = MemoryKVStorage();
    supportDirectory = await Directory.systemTemp.createTemp('welcome-diary-');
    imageDirectory = await Directory('${supportDirectory.path}/image').create();
    mediaGuard = MediaGuard(supportPath: supportDirectory.path);
    assets = _Assets();
    seeder = WelcomeDiarySeeder(
      repository: repository,
      storage: storage,
      imageDirectory: imageDirectory,
      assets: assets,
      mediaGuard: mediaGuard,
    );
  });

  tearDown(() async {
    await supportDirectory.delete(recursive: true);
  });

  void prepare({
    bool hadDatabase = false,
    bool hasLegacyDatabase = false,
    bool legacyMigrationPending = false,
  }) => seeder.prepare(
    hadDatabase: hadDatabase,
    hasLegacyDatabase: hasLegacyDatabase,
    legacyMigrationPending: legacyMigrationPending,
  );

  String? state() => storage.get<String>(MoodiaryKVs.welcomeDiaryState.name);

  Future<List<FileSystemEntity>> images() => imageDirectory.list().toList();

  test('首次安装创建一篇可编辑样例并复制正确的图片字节', () async {
    storage.set<bool>(MoodiaryKVs.syncPendingLocal.name, false);
    prepare();
    expect(state(), 'pending');

    await seeder.seed(migrationReady: true);

    final diary = repository.diaries.single;
    expect(diary.type, DiaryType.tiptap.value);
    expect(diary.content, isNotEmpty);
    expect(diary.tags, isNotEmpty);
    expect(diary.show, isTrue);
    final imageName = diary.imageName.single;
    expect(await File('${imageDirectory.path}/$imageName').readAsBytes(), [
      1,
      2,
      3,
    ]);
    expect(state(), 'completed');
    expect(storage.get<bool>(MoodiaryKVs.syncPendingLocal.name), isTrue);
    expect(repository.insertCalls, 1);
    expect(assets.loads, 1);
  });

  for (final locale in [AppLocale.zh, AppLocale.en]) {
    test('首次创建时使用已解析的 ${locale.languageCode} 文案', () async {
      // Eligibility is captured before the application's language is resolved.
      prepare();
      await LocaleSettings.setLocale(locale);

      await seeder.seed(migrationReady: true);

      final diary = repository.diaries.single;
      expect(diary.title, l10n.app.welcomeDiary.title);
      expect(diary.contentText, contains(l10n.app.welcomeDiary.intro));
      expect(diary.tags, [l10n.app.welcomeDiary.exampleTag]);
      expect(diary.imageName, hasLength(1));
      expect(state(), 'completed');
    });
  }

  test('切换语言后保留用户修改过的欢迎日记', () async {
    prepare();
    await seeder.seed(migrationReady: true);
    const editedTitle = 'My own title';
    const editedContent = '{"type":"doc","content":[]}';
    final edited = repository.diaries.single.copyWith(
      title: editedTitle,
      content: editedContent,
      contentText: '',
    );
    repository.diaries[0] = edited;

    await LocaleSettings.setLocale(AppLocale.en);
    prepare(hadDatabase: true);
    await seeder.seed(migrationReady: true);

    expect(repository.diaries.single.id, edited.id);
    expect(repository.diaries.single.title, editedTitle);
    expect(repository.diaries.single.content, editedContent);
    expect(repository.insertCalls, 1);
    expect(assets.loads, 1);
    expect(state(), 'completed');
  });

  test('样例图片写入和日记提交期间禁止并发媒体清理', () async {
    repository.onInsert = () async {
      expect(
        await mediaGuard.tryExclusive(
          MediaType.image,
          'candidate.jpg',
          () async {},
        ),
        isFalse,
      );
    };
    prepare();
    await seeder.seed(migrationReady: true);
    expect(
      await mediaGuard.tryExclusive(
        MediaType.image,
        'candidate.jpg',
        () async {},
      ),
      isTrue,
    );
  });

  test('重复启动不创建副本，删除样例后也不恢复', () async {
    prepare();
    await seeder.seed(migrationReady: true);

    prepare(hadDatabase: true);
    await seeder.seed(migrationReady: true);
    expect(repository.diaries, hasLength(1));

    repository.diaries.clear();
    prepare(hadDatabase: true);
    await seeder.seed(migrationReady: true);

    expect(repository.diaries, isEmpty);
    expect(repository.insertCalls, 1);
    expect(assets.loads, 1);
    expect(state(), 'completed');
  });

  test('旧版本用户即使日记为空也不创建样例', () async {
    storage.set<String>(MoodiaryKVs.appVersion.name, '2.8.1+95');
    prepare();
    await seeder.seed(migrationReady: true);

    expect(state(), 'skipped');
    expect(repository.insertCalls, 0);
    expect(assets.loads, 0);
  });

  test('已有空数据库不被误判为首次安装', () async {
    prepare(hadDatabase: true);
    await seeder.seed(migrationReady: true);

    expect(state(), 'skipped');
    expect(repository.insertCalls, 0);
  });

  test('存在旧引擎数据库时不创建样例', () async {
    prepare(hasLegacyDatabase: true);
    await seeder.seed(migrationReady: true);

    expect(state(), 'skipped');
    expect(repository.insertCalls, 0);
  });

  test('旧首次启动标记为 false 时不创建样例', () async {
    storage.set<bool>(MoodiaryKVs.firstStart.name, false);
    prepare();
    await seeder.seed(migrationReady: true);

    expect(state(), 'skipped');
    expect(repository.insertCalls, 0);
  });

  test('回收站里的日记也会阻止样例创建', () async {
    repository.diaries.add(_existingDiary(show: false));
    prepare();
    await seeder.seed(migrationReady: true);

    expect(repository.diaries.single.show, isFalse);
    expect(state(), 'skipped');
    expect(repository.insertCalls, 0);
    expect(assets.loads, 0);
  });

  test('旧配置迁移未完成时不记录首次安装资格', () async {
    prepare(legacyMigrationPending: true);
    await seeder.seed(migrationReady: false);

    expect(state(), isNull);
    expect(repository.insertCalls, 0);
    expect(assets.loads, 0);
  });

  test('迁移探测未通过时保留 pending，之后可以重试', () async {
    prepare();
    await seeder.seed(migrationReady: false);
    expect(state(), 'pending');
    expect(repository.insertCalls, 0);
    expect(assets.loads, 0);

    await seeder.seed(migrationReady: true);
    expect(repository.diaries, hasLength(1));
    expect(state(), 'completed');
  });

  test('等待重试期间已有用户日记时终止样例创建', () async {
    prepare();
    await seeder.seed(migrationReady: false);
    repository.diaries.add(_existingDiary());

    await seeder.seed(migrationReady: true);

    expect(repository.diaries.single.id, 'existing-diary');
    expect(state(), 'skipped');
    expect(repository.insertCalls, 0);
    expect(assets.loads, 0);
  });

  test('图片资源读取失败后保留 pending 且不写入日记', () async {
    prepare();
    assets.failLoad = true;
    await expectLater(
      seeder.seed(migrationReady: true),
      throwsA(isA<StateError>()),
    );

    expect(state(), 'pending');
    expect(repository.insertCalls, 0);
    expect(await images(), isEmpty);

    assets.failLoad = false;
    await seeder.seed(migrationReady: true);
    expect(repository.diaries, hasLength(1));
    expect(state(), 'completed');
  });

  test('插入失败清理图片，版本号写入后仍能在下次启动重试', () async {
    prepare();
    repository.failInsert = true;
    await expectLater(
      seeder.seed(migrationReady: true),
      throwsA(isA<StateError>()),
    );

    expect(repository.diaries, isEmpty);
    expect(await images(), isEmpty);
    expect(state(), 'pending');

    storage.set<String>(MoodiaryKVs.appVersion.name, '2.8.1+95');
    repository.failInsert = false;
    seeder = WelcomeDiarySeeder(
      repository: repository,
      storage: storage,
      imageDirectory: imageDirectory,
      assets: assets,
      mediaGuard: mediaGuard,
    );
    prepare(hadDatabase: true);
    await seeder.seed(migrationReady: true);

    expect(repository.diaries, hasLength(1));
    expect(await images(), hasLength(1));
    expect(repository.insertCalls, 2);
    expect(state(), 'completed');
  });

  test('提交完成后的通知失败不删除已被日记引用的图片', () async {
    prepare();
    repository.failAfterInsert = true;
    await expectLater(seeder.seed(migrationReady: true), throwsStateError);
    final image = File(
      '${imageDirectory.path}/${repository.diaries.single.imageName.single}',
    );
    expect(await image.exists(), isTrue);
  });

  test('插入后的完成标记失败不会删除引用图片或重复创建日记', () async {
    final failingStorage = _FailingCompletionStorage();
    seeder = WelcomeDiarySeeder(
      repository: repository,
      storage: failingStorage,
      imageDirectory: imageDirectory,
      assets: assets,
      mediaGuard: mediaGuard,
    );
    prepare();
    await expectLater(
      seeder.seed(migrationReady: true),
      throwsA(isA<StateError>()),
    );

    final diary = repository.diaries.single;
    final image = File('${imageDirectory.path}/${diary.imageName.single}');
    expect(await image.exists(), isTrue);
    expect(
      failingStorage.get<String>(MoodiaryKVs.welcomeDiaryState.name),
      'pending',
    );
    expect(failingStorage.get<bool>(MoodiaryKVs.syncPendingLocal.name), isTrue);

    seeder = WelcomeDiarySeeder(
      repository: repository,
      storage: failingStorage,
      imageDirectory: imageDirectory,
      assets: assets,
      mediaGuard: mediaGuard,
    );
    prepare(hadDatabase: true);
    await seeder.seed(migrationReady: true);

    expect(repository.diaries.single.id, diary.id);
    expect(await image.exists(), isTrue);
    expect(repository.insertCalls, 1);
    expect(assets.loads, 1);
    expect(
      failingStorage.get<String>(MoodiaryKVs.welcomeDiaryState.name),
      'skipped',
    );
  });
}
