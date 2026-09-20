import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:sqlite3_simple/sqlite3_simple.dart';

import 'drift/moodiary/generated/schema.dart';
import 'drift/moodiary/generated/schema_v1.dart' as v1;
import 'drift/moodiary/generated/schema_v2.dart' as v2;
import 'drift/moodiary/generated/schema_v4.dart' as v4;
import 'fixtures/personal_v3/generated/schema.dart' as personal_v3;

String marked(String word) => '$searchHitStart$word$searchHitEnd';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    loadSimpleExtension();
    installJiebaDict();
    verifier = SchemaVerifier(GeneratedHelper());
  });

  Future<int> userVersion(GeneratedDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.data.values.first as int;
  }

  Future<List<String>> columns(GeneratedDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return [for (final r in rows) r.read<String>('name')];
  }

  v1.DiariesCompanion v1Diary(
    String id, {
    double? lat,
    double? lon,
    String? placeName,
    int time = 0,
  }) => v1.DiariesCompanion.insert(
    id: id,
    title: '',
    content: '',
    contentText: '',
    time: time,
    lastModified: 0,
    show: 1,
    mood: 'neutral',
    type: 'tiptap',
    latitude: Value(lat),
    longitude: Value(lon),
    placeName: Value(placeName),
  );

  test('新库直接建到 v5，且与 v5 快照一致', () async {
    final db = MoodiaryDatabase.forTesting(NativeDatabase.memory());
    await verifier.migrateAndValidate(db, 5);
    expect(await userVersion(db), 5);
    await db.close();
  });

  test('v2 老库升级：旧行留空，预设被丢弃', () async {
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    await old
        .into(old.chatSessions)
        .insert(
          v2.ChatSessionsCompanion.insert(
            id: 's1',
            providerId: 'p1',
            model: 'm1',
            createdAt: 0,
            updatedAt: 0,
            agentPresetId: const Value('ap'),
            personaSnapshot: const Value('y'),
          ),
        );
    await old
        .into(old.chatMessages)
        .insert(
          v2.ChatMessagesCompanion.insert(
            id: 'm1',
            sessionId: 's1',
            role: 'user',
            content: 'hi',
            createdAt: 0,
          ),
        );
    await old
        .into(old.memories)
        .insert(
          v2.MemoriesCompanion.insert(
            id: 'f1',
            category: 'preference',
            content: 'call me 小竹',
            createdAt: 0,
            updatedAt: 0,
          ),
        );
    await old
        .into(old.agentPresets)
        .insert(
          v2.AgentPresetsCompanion.insert(
            id: 'ap',
            name: 'x',
            persona: 'y',
            createdAt: 0,
            updatedAt: 0,
          ),
        );
    await old.close();

    final db = MoodiaryDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);
    final message = await db
        .customSelect("SELECT provider_id FROM chat_messages WHERE id = 'm1'")
        .getSingle();
    expect(message.readNullable<String>('provider_id'), isNull);
    final fact = await db
        .customSelect("SELECT source FROM memories WHERE id = 'f1'")
        .getSingle();
    expect(fact.readNullable<String>('source'), isNull);
    final session = await db
        .customSelect("SELECT model FROM chat_sessions WHERE id = 's1'")
        .getSingle();
    expect(session.read<String>('model'), 'm1');
    await db.close();
  });

  test('v1 老库升级：位置快照归并成常用地点，日记改引用，一篇不丢', () async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    await old
        .into(old.categories)
        .insert(
          v1.CategoriesCompanion.insert(id: 'c1', name: '生活', lastModified: 0),
        );
    await old.batch((b) {
      b.insertAll(old.diaries, [
        v1Diary('d1', lat: 30.28, lon: 120.15, placeName: '杭州市 西湖区', time: 1),
        v1Diary('d2', lat: 30.29, lon: 120.16, placeName: '杭州市 西湖区', time: 2),
        v1Diary('d3', lat: 24.48, lon: 118.08, placeName: '', time: 3),
        v1Diary('d4', time: 4),
      ]);
    });
    await old.close();

    final db = MoodiaryDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);
    final places = await PlaceRepository(db).getAllPlaces();
    expect(places, hasLength(2));
    final xihu = places.singleWhere((p) => p.name == '杭州市 西湖区');
    expect(xihu.id, Place.idForName('杭州市 西湖区'), reason: 'id 由地名派生，跨设备一致');
    expect(xihu.latitude, 30.29, reason: '坐标取最近一篇');
    final byCoords = places.singleWhere((p) => p.name != '杭州市 西湖区');
    expect(byCoords.name, '24.4800, 118.0800');
    final repo = DiaryRepository(db);
    expect((await repo.getDiaryByBusinessId('d1'))!.placeId, xihu.id);
    expect((await repo.getDiaryByBusinessId('d2'))!.placeId, xihu.id);
    expect((await repo.getDiaryByBusinessId('d3'))!.placeId, byCoords.id);
    expect((await repo.getDiaryByBusinessId('d4'))!.placeId, isNull);
    expect(
      (await CategoryRepository(db).getCategoryById('c1'))?.categoryName,
      '生活',
    );
    await db.close();
  });

  test('v2 老库升级：索引换成 simple external content，老数据重建后可搜', () async {
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    await old
        .into(old.diaries)
        .insert(
          v2.DiariesCompanion.insert(
            id: 'd1',
            title: '关于苹果的日记',
            content: '',
            contentText: '早上吃了一个苹果，味道不错',
            time: 1,
            lastModified: 0,
            show: 1,
            mood: 'neutral',
            type: 'tiptap',
          ),
        );
    await old.close();

    final db = MoodiaryDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);
    final hit = (await DiaryRepository(db).searchDiaries(query: '苹果')).single;
    expect(hit.diary.id, 'd1', reason: "'rebuild' 从 diaries 重灌了整个索引");
    expect(hit.titleHighlight, '关于${marked('苹果')}的日记');
    await db.close();
  });

  for (final personal in [true, false]) {
    test('${personal ? 'personal 旧' : '上游新版'} v3 升级：保留日记、对话、记忆和全文索引', () async {
      final sourceVerifier = personal
          ? SchemaVerifier(personal_v3.GeneratedHelper())
          : verifier;
      final schema = await sourceVerifier.schemaAt(3);
      final raw = schema.rawDatabase;
      // drift 的测试数据库生成器没有包含触发器，从相应历史快照恢复真实旧库行为。
      final snapshot = jsonDecode(
        await File(
          personal
              ? 'test/fixtures/personal_v3/drift_schema_v3.json'
              : 'drift_schemas/moodiary/drift_schema_v3.json',
        ).readAsString(),
      ) as Map<String, dynamic>;
      final existingTriggers = raw
          .select("SELECT name FROM sqlite_master WHERE type = 'trigger'")
          .map((row) => row['name'])
          .toSet();
      for (final entity in (snapshot['entities'] as List).cast<Map>()) {
        if (entity['type'] != 'trigger') continue;
        final trigger = entity['data'] as Map;
        if (!existingTriggers.contains(trigger['name'])) {
          raw.execute(trigger['sql'] as String);
        }
      }
      raw.execute('''
        INSERT INTO diaries
          (id, title, content, content_text, time, last_modified, show, mood, type)
        VALUES ('d1', '关于苹果的日记', '正文', '早上吃了一个苹果', 123, 456, 1, 'neutral', 'tiptap')
      ''');
      raw.execute('''
        INSERT INTO chat_sessions
          (id, provider_id, model, title, created_at, updated_at, compacted_summary)
        VALUES ('s1', 'p1', 'model1', '旧会话', 123, 456, '已有摘要')
      ''');
      raw.execute('''
        INSERT INTO chat_messages (id, session_id, role, content, created_at)
        VALUES ('m1', 's1', 'user', '旧消息', 123)
      ''');
      raw.execute('''
        INSERT INTO memories (id, category, content, created_at, updated_at)
        VALUES ('f1', 'preference', '喜欢苹果', 123, 456)
      ''');
      if (personal) {
        raw.execute('''
          INSERT INTO agent_presets (id, name, persona, created_at, updated_at)
          VALUES ('ap', '旧预设', '旧人设', 123, 456)
        ''');
        raw.execute('''
          UPDATE chat_sessions
          SET agent_preset_id = 'ap', persona_snapshot = '旧人设', tools_snapshot_json = '[]'
          WHERE id = 's1'
        ''');
      } else {
        raw.execute("UPDATE chat_messages SET provider_id = 'p1'");
        raw.execute("UPDATE memories SET source = 'user'");
      }
      expect(
        raw.select(
          'SELECT rowid FROM diary_fts WHERE diary_fts MATCH jieba_query(?)',
          ['苹果'],
        ),
        hasLength(1),
        reason: '迁移前旧库的真实触发器已经维护好全文索引',
      );

      var db = MoodiaryDatabase.forTesting(schema.newConnection());
      await verifier.migrateAndValidate(db, 5);
      expect(await userVersion(db), 5);
      expect(db.upgradedFrom, 3);
      final diary = await DiaryRepository(db).getDiaryByBusinessId('d1');
      expect(diary!.title, '关于苹果的日记');
      expect(diary.content, '正文');
      expect(
        (await db
                .customSelect(
                  "SELECT last_modified FROM diaries WHERE id = 'd1'",
                )
                .getSingle())
            .read<int>('last_modified'),
        456,
      );
      final hit = (await DiaryRepository(db).searchDiaries(query: '苹果')).single;
      expect(hit.diary.id, 'd1');
      expect(hit.titleHighlight, '关于${marked('苹果')}的日记');
      final session = (await db.select(db.chatSessions).get()).single;
      expect(session.id, 's1');
      expect(session.providerId, 'p1');
      expect(session.model, 'model1');
      expect(session.title, '旧会话');
      expect(session.compactedSummary, '已有摘要');
      expect(session.updatedAt, 456);
      final message = (await db.select(db.chatMessages).get()).single;
      expect(message.id, 'm1');
      expect(message.sessionId, 's1');
      expect(message.content, '旧消息');
      expect(message.createdAt, 123);
      expect(message.providerId, personal ? isNull : 'p1');
      final memory = (await db.select(db.memories).get()).single;
      expect(memory.id, 'f1');
      expect(memory.content, '喜欢苹果');
      expect(memory.updatedAt, 456);
      expect(memory.source, personal ? isNull : 'user');
      expect(
        await columns(db, 'chat_sessions'),
        isNot(
          anyElement(
            isIn([
              'agent_preset_id',
              'persona_snapshot',
              'tools_snapshot_json',
            ]),
          ),
        ),
      );
      expect(
        await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name = 'agent_presets'",
            )
            .get(),
        isEmpty,
      );
      await db.close();

      db = MoodiaryDatabase.forTesting(schema.newConnection());
      expect(await userVersion(db), 5);
      expect(db.upgradedFrom, isNull);
      expect((await db.select(db.chatMessages).get()).single.content, '旧消息');
      await db.close();
    });
  }

  test('已是 v5 的库重开不重复建表', () async {
    final schema = await verifier.schemaAt(5);
    var db = MoodiaryDatabase.forTesting(schema.newConnection());
    await PlaceRepository(
      db,
    ).insertAPlace(Place.create(name: '家', latitude: 30.1, longitude: 120.1));
    await db.close();

    db = MoodiaryDatabase.forTesting(schema.newConnection());
    expect(await userVersion(db), 5);
    expect(await PlaceRepository(db).getAllPlaces(), hasLength(1));
    expect(await columns(db, 'diaries'), isNot(contains('latitude')));
    await db.close();
  });

  test('v4 升级保留旧日记并为空的标签迁移排除列表赋默认值', () async {
    final schema = await verifier.schemaAt(4);
    final old = v4.DatabaseAtV4(schema.newConnection());
    await old
        .into(old.diaries)
        .insert(
          v4.DiariesCompanion.insert(
            id: 'legacy',
            categoryId: const Value('late-category'),
            title: '旧日记',
            content: '',
            contentText: '',
            time: 123,
            lastModified: 456,
            show: 0,
            mood: 'neutral',
            type: 'tiptap',
          ),
        );
    await old
        .into(old.diaryTags)
        .insert(
          v4.DiaryTagsCompanion.insert(diaryId: 'legacy', seq: 0, tag: '工作/项目'),
        );
    await old.close();

    final db = MoodiaryDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);
    final diary = (await DiaryRepository(db).getDiaryByBusinessId('legacy'))!;
    expect(diary.legacyCategoryExcludedTags, isEmpty);
    expect(diary.categoryId, 'late-category');
    expect(diary.tags, ['工作/项目']);
    expect(diary.lastModified.microsecondsSinceEpoch, 456);
    expect(diary.show, isFalse);
    expect(
      (await db.select(db.diaries).getSingle()).legacyCategoryExcludedTagsJson,
      '[]',
    );
    expect(await userVersion(db), 5);
    await db.close();
  });
}
