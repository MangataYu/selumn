import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_plus/isar_plus.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_migration/moodiary_migration.dart';
import 'package:moodiary_migration/src/legacy/legacy_models.dart';
import 'package:moodiary_models/moodiary_models.dart'
    hide Category, Diary, Font;
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

class _FailingKVStorage extends IKVStorage {
  final MemoryKVStorage memory = MemoryKVStorage();
  String? failingKey;

  @override
  Future<void> init() async {}

  @override
  T? get<T extends Object>(String key) => memory.get<T>(key);

  @override
  void set<T extends Object>(String key, T value) {
    if (key == failingKey) throw StateError('KV write unavailable');
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

Diary _legacyDiary(
  String id, {
  required String type,
  required String content,
}) => Diary(
  id: id,
  title: '',
  content: content,
  contentText: '',
  time: DateTime.utc(2024, 6, 1),
  lastModified: DateTime.utc(2024, 6, 2),
  show: true,
  mood: 0.5,
  weather: const [],
  imageName: const [],
  audioName: const [],
  videoName: const [],
  tags: const [],
  position: const [],
  type: type,
);

void main() {
  group('run 将旧迁移水位与 Selume 版本分开', () {
    late _FailingKVStorage kv;

    setUp(() {
      kv = _FailingKVStorage();
      getIt.registerSingleton<IKVStorage>(kv);
      MmkvKVStorage.legacyMigrationPending = false;
      PackageInfo.setMockInitialValues(
        appName: 'Selume',
        packageName: 'com.aerieyarrowy.selume',
        version: '1.0.0',
        buildNumber: '96',
        buildSignature: '',
      );
    });

    tearDown(() async {
      MmkvKVStorage.legacyMigrationPending = false;
      await getIt.reset();
    });

    test('首次安装记录迁移水位，之后启动不重跑旧迁移', () async {
      await VersionMigrator.run();

      expect(MoodiaryKVs.appVersion.get(), '1.0.0+96');
      expect(MoodiaryKVs.legacyMigrationVersion.get(), '2.8.2');
      expect(MoodiaryKVs.searchIndexBackfilled.get(), isTrue);
      MoodiaryKVs.customFont.set('my-font.ttf');
      MoodiaryKVs.autoSync.set(true);
      MoodiaryKVs.assistantReasoningEffort.set('');

      await VersionMigrator.run();

      expect(MoodiaryKVs.customFont.get(), 'my-font.ttf');
      expect(MoodiaryKVs.autoSync.get(), isTrue);
      expect(MoodiaryKVs.assistantReasoningEffort.get(), '');
    });

    test('旧版本升级先完成待执行迁移，重启保留用户设置', () async {
      MoodiaryKVs.appVersion.set('2.8.1+95');
      MoodiaryKVs.assistantReasoningEffort.set('');
      MoodiaryKVs.customFont.set('my-font.ttf');
      MoodiaryKVs.autoSync.set(true);

      await VersionMigrator.run();

      expect(MoodiaryKVs.assistantReasoningEffort.get(), 'none');
      expect(MoodiaryKVs.appVersion.get(), '1.0.0+96');
      expect(MoodiaryKVs.legacyMigrationVersion.get(), '2.8.2');
      expect(MoodiaryKVs.searchIndexBackfilled.get(), isFalse);
      MoodiaryKVs.assistantReasoningEffort.set('');

      await VersionMigrator.run();

      expect(MoodiaryKVs.customFont.get(), 'my-font.ttf');
      expect(MoodiaryKVs.autoSync.get(), isTrue);
      expect(MoodiaryKVs.assistantReasoningEffort.get(), '');
    });

    test('已有更高迁移水位不会被降低', () async {
      MoodiaryKVs.appVersion.set('1.0.0+96');
      MoodiaryKVs.legacyMigrationVersion.set('2.9.0');
      MoodiaryKVs.assistantReasoningEffort.set('');

      await VersionMigrator.run();

      expect(MoodiaryKVs.legacyMigrationVersion.get(), '2.9.0');
      expect(MoodiaryKVs.assistantReasoningEffort.get(), '');
    });

    test('没有独立水位时保留高于已知迁移的旧应用版本', () async {
      MoodiaryKVs.appVersion.set('2.9.0+120');

      await VersionMigrator.run();

      expect(MoodiaryKVs.legacyMigrationVersion.get(), '2.9.0+120');
      expect(MoodiaryKVs.appVersion.get(), '1.0.0+96');
    });

    test('迁移水位写入失败保留旧版本，下次仍能完成待执行迁移', () async {
      MoodiaryKVs.appVersion.set('2.8.1+95');
      MoodiaryKVs.assistantReasoningEffort.set('');
      kv.failingKey = MoodiaryKVs.legacyMigrationVersion.name;

      await expectLater(VersionMigrator.run(), throwsStateError);

      expect(MoodiaryKVs.appVersion.get(), '2.8.1+95');
      expect(MoodiaryKVs.legacyMigrationVersion.get(), isNull);
      MoodiaryKVs.assistantReasoningEffort.set('');
      kv.failingKey = null;

      await VersionMigrator.run();

      expect(MoodiaryKVs.assistantReasoningEffort.get(), 'none');
      expect(MoodiaryKVs.legacyMigrationVersion.get(), '2.8.2');
      expect(MoodiaryKVs.appVersion.get(), '1.0.0+96');
    });

    test('首次安装水位写入失败不会先记录新的应用版本', () async {
      kv.failingKey = MoodiaryKVs.legacyMigrationVersion.name;

      await expectLater(VersionMigrator.run(), throwsStateError);

      expect(MoodiaryKVs.appVersion.get(), isNull);
      expect(MoodiaryKVs.legacyMigrationVersion.get(), isNull);
      kv.failingKey = null;

      await VersionMigrator.run();

      expect(MoodiaryKVs.legacyMigrationVersion.get(), '2.8.2');
      expect(MoodiaryKVs.appVersion.get(), '1.0.0+96');
      expect(MoodiaryKVs.searchIndexBackfilled.get(), isTrue);
    });

    test('应用版本写入失败后沿用已完成水位，不重复迁移', () async {
      MoodiaryKVs.appVersion.set('2.8.1+95');
      MoodiaryKVs.assistantReasoningEffort.set('');
      kv.failingKey = MoodiaryKVs.appVersion.name;

      await expectLater(VersionMigrator.run(), throwsStateError);

      expect(MoodiaryKVs.legacyMigrationVersion.get(), '2.8.2');
      expect(MoodiaryKVs.appVersion.get(), '2.8.1+95');
      MoodiaryKVs.assistantReasoningEffort.set('');
      kv.failingKey = null;

      await VersionMigrator.run();

      expect(MoodiaryKVs.assistantReasoningEffort.get(), '');
      expect(MoodiaryKVs.appVersion.get(), '1.0.0+96');
    });

    test('迁移失败不推进水位或覆盖旧版本', () async {
      MoodiaryKVs.appVersion.set('invalid-version');

      await expectLater(VersionMigrator.run(), throwsFormatException);

      expect(MoodiaryKVs.appVersion.get(), 'invalid-version');
      expect(MoodiaryKVs.legacyMigrationVersion.get(), isNull);
    });

    test('旧配置尚未完成搬迁时不记录水位或应用版本', () async {
      MmkvKVStorage.legacyMigrationPending = true;

      await VersionMigrator.run();

      expect(MoodiaryKVs.legacyMigrationVersion.get(), isNull);
      expect(MoodiaryKVs.appVersion.get(), isNull);
      expect(MoodiaryKVs.searchIndexBackfilled.get(), isFalse);
    });
  });

  group('versionBelow 闸门语义', () {
    test('低版本在闸门之下', () {
      expect(VersionMigrator.versionBelow('2.7.3+73', '2.8.0'), isTrue);
      expect(VersionMigrator.versionBelow('2.4.7+50', '2.4.8'), isTrue);
    });

    test('同版本与更高版本不触发（含 build 元数据）', () {
      expect(VersionMigrator.versionBelow('2.8.0+94', '2.8.0'), isFalse);
      expect(VersionMigrator.versionBelow('2.8.1+1', '2.8.0'), isFalse);
      expect(VersionMigrator.versionBelow('2.8.0+999', '2.8.0'), isFalse);
    });

    test('pre-release 被剥掉：beta 渠道不得每次冷启动重跑迁移', () {
      expect(VersionMigrator.versionBelow('2.8.0-beta+94', '2.8.0'), isFalse);
      expect(VersionMigrator.versionBelow('2.7.3-beta+73', '2.8.0'), isTrue);
    });

    test('semver 比较而非字典序', () {
      expect(VersionMigrator.versionBelow('2.10.0+1', '2.9.0'), isFalse);
      expect(VersionMigrator.versionBelow('2.9.0+1', '2.10.0'), isTrue);
    });
  });

  group('merge 在 2.8.2 及以上是纯 no-op', () {
    test('正式版与 beta 版都直接返回', () async {
      await VersionMigrator.merge(lastAppVersion: '2.8.2+96');
      await VersionMigrator.merge(lastAppVersion: '2.8.2-beta+96');
      await VersionMigrator.merge(lastAppVersion: '2.9.1+120');
    });
  });

  group('2.8.2：思考档位从空串变成显式关闭', () {
    late MemoryKVStorage kv;

    setUp(() {
      kv = MemoryKVStorage();
      getIt.registerSingleton<IKVStorage>(kv);
    });

    tearDown(getIt.reset);

    test('旧版写进去的空串变成 none', () async {
      kv.set<String>(MoodiaryKVs.assistantReasoningEffort.name, '');
      await VersionMigrator.merge(lastAppVersion: '2.8.1+95');
      expect(MoodiaryKVs.assistantReasoningEffort.get(), 'none');
    });

    test('显式档位与显式关闭原样保留', () async {
      kv.set<String>(MoodiaryKVs.assistantReasoningEffort.name, 'high');
      await VersionMigrator.merge(lastAppVersion: '2.8.1+95');
      expect(MoodiaryKVs.assistantReasoningEffort.get(), 'high');

      kv.set<String>(MoodiaryKVs.assistantReasoningEffort.name, 'none');
      await VersionMigrator.merge(lastAppVersion: '2.8.1+95');
      expect(MoodiaryKVs.assistantReasoningEffort.get(), 'none');
    });

    test('2.8.2 之后不再碰这个键', () async {
      kv.set<String>(MoodiaryKVs.assistantReasoningEffort.name, '');
      await VersionMigrator.merge(lastAppVersion: '2.8.2+96');
      expect(MoodiaryKVs.assistantReasoningEffort.get(), '');
    });
  });

  final dylib = Platform.environment['ISAR_TEST_DYLIB'];
  if (dylib == null || dylib.isEmpty) {
    test(
      '2.8.0 迁移步骤（skipped）',
      () {},
      skip: '需要 ISAR_TEST_DYLIB 指向 libisar_plus 动态库，见文件头注释',
    );
    return;
  }

  setUpAll(() async {
    await Isar.initialize(dylib);
  });

  group('2.8.0 迁移步骤（真库）', () {
    late Directory dir;
    late Isar isar;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('moodiary_migration_test');
      isar = .open(
        schemas: legacyMigrationSchemas,
        directory: dir.path,
        inspector: false,
      );
    });

    tearDown(() {
      if (isar.isOpen) isar.close();
      dir.deleteSync(recursive: true);
    });

    void seed(List<Diary> diaries) {
      isar.write((isar) => isar.diarys.putAll(diaries));
    }

    void runMerge() {
      VersionMigrator.debugMergeToV280(dir.path);
      isar = .open(
        schemas: legacyMigrationSchemas,
        directory: dir.path,
        inspector: false,
      );
    }

    Diary byId(String id) => isar.diarys.where().idEqualTo(id).findFirst()!;

    test('text 裸文本被包装成 Delta 并翻成 richText，时间戳原样保留', () {
      seed([_legacyDiary('t1', type: 'text', content: '第一篇\n随手记')]);
      runMerge();

      final d = byId('t1');
      expect(d.type, DiaryType.richText.value);
      expect(QuillDelta.isDelta(d.content), isTrue);
      expect(QuillDelta.plainText(d.content), '第一篇\n随手记\n');
      // isar_plus 反序列化会 toLocal，按绝对时刻比较
      expect(d.lastModified.toUtc(), DateTime.utc(2024, 6, 2));
      expect(d.time.toUtc(), DateTime.utc(2024, 6, 1));
    });

    test('恰好是 JSON 数组的裸文本同样被包装——不得漏成"合法 Delta"静默清空', () {
      const raw = '["买菜","做饭"]';
      seed([_legacyDiary('t2', type: 'text', content: raw)]);
      runMerge();

      final d = byId('t2');
      expect(d.type, DiaryType.richText.value);
      final ops = jsonDecode(d.content) as List;
      expect(ops, hasLength(1));
      expect((ops.single as Map)['insert'], '$raw\n');
    });

    test('text 里已是合法 Delta 的只翻 type，内容逐字节不动', () {
      const delta = '[{"insert":"正文\\n"}]';
      seed([_legacyDiary('t3', type: 'text', content: delta)]);
      runMerge();

      final d = byId('t3');
      expect(d.type, DiaryType.richText.value);
      expect(d.content, delta);
    });

    test('richText 与 markdown 行原样不动', () {
      const delta = '[{"insert":"已是富文本\\n"}]';
      const md = '# 标题\n正文';
      seed([
        _legacyDiary('r1', type: 'richText', content: delta),
        _legacyDiary('m1', type: 'markdown', content: md),
      ]);
      runMerge();

      expect(byId('r1').content, delta);
      expect(byId('r1').type, 'richText');
      expect(byId('m1').content, md);
      expect(byId('m1').type, 'markdown');
    });

    test('幂等：重复执行结果不变', () {
      seed([_legacyDiary('t4', type: 'text', content: '重复跑')]);
      runMerge();
      final first = byId('t4').content;
      runMerge();
      expect(byId('t4').content, first);
      expect(byId('t4').type, DiaryType.richText.value);
    });
  });

  group('2.6.0 / 2.6.3 / 2.7.3 旧步骤（真库）', () {
    late Directory dir;
    late Isar isar;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('moodiary_legacy_mig_test');
      isar = .open(
        schemas: legacyMigrationSchemas,
        directory: dir.path,
        inspector: false,
      );
    });

    tearDown(() {
      if (isar.isOpen) isar.close();
      dir.deleteSync(recursive: true);
    });

    void reopen() {
      isar = .open(
        schemas: legacyMigrationSchemas,
        directory: dir.path,
        inspector: false,
      );
    }

    Diary byId(String id) => isar.diarys.where().idEqualTo(id).findFirst()!;

    test('2.6.0：裸文本包成 Delta、翻 richText、lastModified 对齐 time；重跑幂等', () {
      const delta = '[{"insert":"已是 Delta\\n"}]';
      isar.write(
        (i) => i.diarys.putAll([
          _legacyDiary('plain', type: 'text', content: '第一篇\n随手记'),
          _legacyDiary('delta', type: 'text', content: delta),
        ]),
      );
      VersionMigrator.debugMergeToV260(dir.path);
      reopen();

      final plain = byId('plain');
      expect(QuillDelta.isDelta(plain.content), isTrue, reason: '裸文本被包装');
      expect(QuillDelta.plainText(plain.content), '第一篇\n随手记\n');
      expect(plain.type, DiaryType.richText.value);
      expect(plain.lastModified.toUtc(), plain.time.toUtc());
      expect(byId('delta').content, delta, reason: '合法 Delta 逐字节不动');

      final first = (plain: plain.content, delta: byId('delta').content);
      VersionMigrator.debugMergeToV260(dir.path);
      reopen();
      expect(byId('plain').content, first.plain, reason: '重跑幂等');
      expect(byId('delta').content, first.delta);
    });

    test('2.6.3：悬挂 categoryId 补占位分类；已存在的不重复建', () {
      isar.write((i) {
        i.categorys.put(
          Category(id: 'ok', categoryName: '在册', lastModified: DateTime(2024)),
        );
        i.diarys.putAll([
          _legacyDiary(
            'a',
            type: 'richText',
            content: '[{"insert":"x\\n"}]',
          ).copyWith(categoryId: 'dangling'),
          _legacyDiary(
            'b',
            type: 'richText',
            content: '[{"insert":"y\\n"}]',
          ).copyWith(categoryId: 'ok'),
        ]);
      });
      VersionMigrator.debugFixV263(dir.path);
      reopen();

      expect(
        isar.categorys.where().idEqualTo('dangling').findFirst(),
        isNotNull,
      );
      expect(isar.categorys.where().count(), 2, reason: '在册的不重复建');
    });

    test('2.7.3：字体表清空重灌；重跑幂等', () async {
      isar.write(
        (i) => i.fonts.put(
          const Font(fontFileName: 'stale.ttf', fontWghtAxisMap: {}),
        ),
      );
      const scanned = [
        Font(fontFileName: 'a.ttf', fontWghtAxisMap: {'wght': 400}),
        Font(fontFileName: 'b.otf', fontWghtAxisMap: {}),
      ];
      await VersionMigrator.debugMergeToV273(dir.path, scanned);
      reopen();

      expect(isar.fonts.where().count(), 2, reason: '旧行被清空、重灌磁盘扫描结果');
      expect(isar.fonts.where().findAll().map((f) => f.fontFileName).toSet(), {
        'a.ttf',
        'b.otf',
      });

      await VersionMigrator.debugMergeToV273(dir.path, scanned);
      reopen();
      expect(isar.fonts.where().count(), 2, reason: '重跑幂等');
    });
  });
}
