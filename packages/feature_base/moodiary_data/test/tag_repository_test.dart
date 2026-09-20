import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

Diary diary(
  String id, {
  List<String> tags = const [],
  String? category,
  bool show = true,
}) => Diary.empty(type: .tiptap).copyWith(
  id: id,
  title: '苹果',
  content: jsonEncode({
    'type': 'doc',
    'content': [
      {
        'type': 'paragraph',
        'content': [
          {'type': 'text', 'text': '苹果'},
        ],
      },
    ],
  }),
  contentText: '苹果',
  tags: tags,
  categoryId: category,
  show: show,
  time: DateTime.utc(2026, 1, 1),
  lastModified: DateTime.utc(2026, 1, 2),
);

void main() {
  late MoodiaryDatabase db;
  late DiaryRepository repository;
  late CategoryRepository categories;

  setUp(() {
    db = MoodiaryDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    repository = DiaryRepository(db);
    categories = CategoryRepository(db);
  });
  tearDown(() => db.close());

  Future<void> category(String id, String name, {String? parent}) =>
      categories.insertACategory(
        Category(
          id: id,
          categoryName: name,
          parentId: parent,
          lastModified: DateTime.utc(2026),
        ),
      );

  test('parent queries and counts include descendants once, excluding hidden diaries', () async {
    await repository.insertDiaries([
      diary('one', tags: [' 工作 / 项目 ', '工作', '工作/项目']),
      diary('two', tags: ['工作/会议']),
      diary('three'),
      diary('hidden', tags: ['工作/会议'], show: false),
      diary('different', tags: ['工作室']),
    ]);
    expect(
      (await repository.getDiaryByTag(tag: '工作')).map((d) => d.id).toSet(),
      {'one', 'two'},
    );
    expect((await repository.getDiaryByTag(untagged: true)).single.id, 'three');
    final counts = await repository.diaryCountByTag();
    expect(counts.total, 4);
    expect(counts.untagged, 1);
    expect(counts.byTag['工作'], 2);
    expect(counts.byTag['工作/项目'], 1);
    expect(await repository.getAllTags(), ['工作', '工作/会议', '工作/项目', '工作室']);
    expect(await repository.countSearchDiaries(query: '苹果', tag: '工作'), 2);
    expect(
      (await repository.searchDiaries(
        query: '苹果',
        tag: '工作/项目',
      )).single.diary.id,
      'one',
    );
    expect((await repository.diaryCountByMonth(tag: '工作')).values.single, 2);
    expect(
      (await repository.getDiaryByTag(tag: '工作', limit: 1, offset: 1)).length,
      1,
    );
  });

  test(
    'SQL path matching treats wildcards literally and supports emoji',
    () async {
      await repository.insertDiaries([
        diary('literal', tags: ['a%_/child']),
        diary('other', tags: ['abc/child']),
        diary('emoji', tags: ['😀/运动']),
      ]);
      expect((await repository.getDiaryByTag(tag: 'a%_')).single.id, 'literal');
      expect((await repository.getDiaryByTag(tag: '😀')).single.id, 'emoji');
    },
  );

  test('legacy categories migrate complete paths with stable timestamps and no resurrection', () async {
    await category('parent', '生活');
    await category('child', '运动', parent: 'parent');
    await repository.insertDiaries([
      diary('one', tags: ['随笔', '生活/运动'], category: 'child'),
      diary('hidden', category: 'child', show: false),
    ]);
    final events = <DiaryEvent>[];
    final subscription = repository.diaryEvents.listen(events.add);
    expect(await repository.migrateLegacyCategoriesToTags(), 2);
    await Future<void>.delayed(Duration.zero);
    expect(
      events.whereType<DiaryUpdated>().every((event) => event.fromSync),
      isTrue,
    );
    final migrated = (await repository.getDiaryByBusinessId('one'))!;
    expect(migrated.categoryId, isNull);
    expect(migrated.tags, ['随笔', '生活/运动']);
    expect(migrated.lastModified, DateTime.utc(2026, 1, 2));
    expect((await repository.getDiaryByBusinessId('hidden'))!.tags, ['生活/运动']);
    expect(await repository.migrateLegacyCategoriesToTags(), 0);
    await repository.deleteTag('生活');
    expect(await repository.migrateLegacyCategoriesToTags(), 0);
    expect((await repository.getDiaryByBusinessId('one'))!.tags, ['随笔']);
    expect((await categories.getAllCategories()).length, 2);
    await subscription.cancel();
  });

  test('migration waits for missing parents, preserves cycles, and respects open diaries', () async {
    await category('child', '项目', parent: 'parent');
    await category('cycle-a', 'A', parent: 'cycle-b');
    await category('cycle-b', 'B', parent: 'cycle-a');
    await repository.insertDiaries([
      diary('late', category: 'child'),
      diary('cycle', category: 'cycle-a'),
      diary('orphan', category: 'missing'),
    ]);
    expect(await repository.migrateLegacyCategoriesToTags(), 0);
    await category('parent', '工作');
    expect(
      await repository.migrateLegacyCategoriesToTags(excludeIds: {'late'}),
      0,
    );
    final concurrent = await Future.wait([
      repository.migrateLegacyCategoriesToTags(),
      repository.migrateLegacyCategoriesToTags(),
    ]);
    expect(concurrent.fold(0, (sum, count) => sum + count), 1);
    expect((await repository.getDiaryByBusinessId('late'))!.tags, ['工作/项目']);
    expect(
      (await repository.getDiaryByBusinessId('cycle'))!.categoryId,
      'cycle-a',
    );
    expect(
      (await repository.getDiaryByBusinessId('orphan'))!.categoryId,
      'missing',
    );
  });

  test('rename and delete update inline marks, descendants, deduplication and timestamps', () async {
    final content = jsonEncode({
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {
              'type': 'text',
              'text': '#工作/项目',
              'marks': [
                {
                  'type': 'tag',
                  'attrs': {'tag': '工作/项目'},
                },
              ],
            },
          ],
        },
      ],
    });
    await repository.insertADiary(
      diary(
        'one',
        tags: ['工作/项目', '生活/项目', '工作室'],
      ).copyWith(content: content, contentText: '#工作/项目'),
    );
    await repository.insertADiary(
      diary('hidden', tags: ['工作/会议'], show: false),
    );
    expect(await repository.renameTag('工作', '生活'), 2);
    final renamed = (await repository.getDiaryByBusinessId('one'))!;
    expect(renamed.tags, ['生活/项目', '工作室']);
    expect(TiptapContent.tags(renamed.content), ['生活/项目']);
    expect(renamed.contentText, '#生活/项目');
    expect(renamed.lastModified.isAfter(DateTime.utc(2026, 1, 2)), isTrue);
    expect(await repository.deleteTag('生活'), 2);
    final removed = (await repository.getDiaryByBusinessId('one'))!;
    expect(removed.tags, ['工作室']);
    expect(TiptapContent.tags(removed.content), isEmpty);
    expect(removed.contentText, '生活/项目');
    expect(await repository.getAllTags(), ['工作室']);
  });

  test('import and sync writes include tags from inline marks', () async {
    final content = jsonEncode({
      'type': 'doc',
      'content': [
        {
          'type': 'paragraph',
          'content': [
            {
              'type': 'text',
              'text': '#工作/项目',
              'marks': [
                {
                  'type': 'tag',
                  'attrs': {'tag': '工作/项目'},
                },
              ],
            },
          ],
        },
      ],
    });
    await repository.insertADiary(
      diary('incoming', tags: ['随笔']).copyWith(content: content),
      fromSync: true,
    );
    expect((await repository.getDiaryByBusinessId('incoming'))!.tags, [
      '随笔',
      '工作/项目',
    ]);
    await expectLater(repository.renameTag('工作', '含 空格'), throwsArgumentError);
  });

  test('legacy names survive and existing tag paths are normalized without user edits', () async {
    await category('language', 'C#');
    await repository.insertADiary(diary('category', category: 'language'));
    await repository.insertADiary(diary('tags'));
    final legacy = [' 工作 / 项目 ', '工作/项目', 'C#', 'a//b'];
    await db.batch((batch) {
      batch.insertAll(db.diaryTags, [
        for (var index = 0; index < legacy.length; index++)
          DiaryTagsCompanion.insert(
            diaryId: 'tags',
            seq: index,
            tag: legacy[index],
          ),
      ]);
    });
    expect(await repository.migrateLegacyCategoriesToTags(), 2);
    expect((await repository.getDiaryByBusinessId('category'))!.tags, ['C#']);
    final normalized = (await repository.getDiaryByBusinessId('tags'))!;
    expect(normalized.tags, ['工作/项目', 'C#', 'a//b']);
    expect(normalized.lastModified, DateTime.utc(2026, 1, 2));
    expect((await repository.getDiaryByTag(tag: '工作')).single.id, 'tags');
    expect((await repository.getDiaryByTag(tag: 'a//b')).single.id, 'tags');
    expect(await repository.migrateLegacyCategoriesToTags(), 0);
  });

  test(
    'deleted parent tags do not return when a legacy ancestor arrives later',
    () async {
      await category('child', '项目', parent: 'parent');
      await repository.insertDiaries([
        diary('visible', category: 'child', tags: ['工作/项目']),
        diary('hidden', category: 'child', tags: ['工作/项目'], show: false),
      ]);
      expect(await repository.migrateLegacyCategoriesToTags(), 0);
      expect(await repository.deleteTag('工作'), 2);
      final removed = (await repository.getDiaryByBusinessId('visible'))!;
      expect(removed.legacyCategoryExcludedTags, ['工作']);
      expect(removed.categoryId, 'child');
      await category('parent', '工作');
      expect(await repository.migrateLegacyCategoriesToTags(), 2);
      for (final id in ['visible', 'hidden']) {
        final migrated = (await repository.getDiaryByBusinessId(id))!;
        expect(migrated.tags, isEmpty);
        expect(migrated.categoryId, isNull);
        expect(migrated.legacyCategoryExcludedTags, isEmpty);
      }
      expect(
        (await repository.getDiaryByBusinessId('visible'))!.lastModified,
        removed.lastModified,
      );
      expect((await repository.getDiaryByBusinessId('hidden'))!.show, isFalse);
      expect(await repository.migrateLegacyCategoriesToTags(), 0);
    },
  );

  test('renaming a pending legacy tag suppresses its old path only', () async {
    await category('child', '项目', parent: 'parent');
    await repository.insertDiaries([
      diary('renamed', category: 'child', tags: ['工作/项目']),
      diary('unrelated', category: 'child', tags: ['随笔']),
    ]);
    expect(await repository.renameTag('工作', '事业'), 1);
    expect(await repository.deleteTag('随笔'), 1);
    await category('parent', '工作');
    expect(await repository.migrateLegacyCategoriesToTags(), 2);
    expect((await repository.getDiaryByBusinessId('renamed'))!.tags, ['事业/项目']);
    expect((await repository.getDiaryByBusinessId('unrelated'))!.tags, [
      '工作/项目',
    ]);
  });

  test('local repository tag edits record exclusions and explicit undo clears exact paths', () async {
    await category('child', '项目', parent: 'parent');
    final original = diary('local-edit', category: 'child', tags: ['工作/项目']);
    await repository.insertADiary(original);
    await repository.updateADiary(
      newDiary: original.copyWith(tags: []),
      index: .skip,
    );
    final removed = (await repository.getDiaryByBusinessId(original.id))!;
    expect(removed.legacyCategoryExcludedTags, ['工作/项目']);
    await repository.updateADiary(
      newDiary: removed.copyWith(tags: ['工作/项目']),
      index: .skip,
    );
    final undone = (await repository.getDiaryByBusinessId(original.id))!;
    expect(undone.legacyCategoryExcludedTags, isEmpty);
    await category('parent', '工作');
    expect(await repository.migrateLegacyCategoriesToTags(), 1);
    expect((await repository.getDiaryByBusinessId(original.id))!.tags, [
      '工作/项目',
    ]);
  });

  test(
    'adding a new child keeps a broader exclusion for the unknown legacy child',
    () async {
      await category('child', '旧项目', parent: 'parent');
      await repository.insertADiary(
        diary(
          'new-child',
          category: 'child',
        ).copyWith(legacyCategoryExcludedTags: ['工作']),
      );
      final before = (await repository.getDiaryByBusinessId('new-child'))!;
      await repository.updateADiary(
        newDiary: before.copyWith(tags: ['工作/新项目']),
        index: .skip,
      );
      expect(
        (await repository.getDiaryByBusinessId('new-child'))!
            .legacyCategoryExcludedTags,
        ['工作'],
      );
      await category('parent', '工作');
      expect(await repository.migrateLegacyCategoriesToTags(), 1);
      expect((await repository.getDiaryByBusinessId('new-child'))!.tags, [
        '工作/新项目',
      ]);
    },
  );

  test('pending exclusions survive payload transfer into another database and migration', () async {
    await category('child', '项目', parent: 'parent');
    await repository.insertADiary(
      diary('backup', category: 'child', tags: ['工作/项目'], show: false),
    );
    await repository.deleteTag('工作');
    final exported = (await repository.getDiaryByBusinessId('backup'))!;
    final payload =
        jsonDecode(jsonEncode(exported.toJson())) as Map<String, dynamic>;
    final receiver = MoodiaryDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    try {
      final receiverDiaries = DiaryRepository(receiver);
      final receiverCategories = CategoryRepository(receiver);
      await receiverDiaries.insertADiary(
        Diary.fromJson(payload),
        fromSync: true,
      );
      final imported = (await receiverDiaries.getDiaryByBusinessId('backup'))!;
      expect(imported.legacyCategoryExcludedTags, ['工作']);
      expect(imported.lastModified, exported.lastModified);
      await receiverCategories.insertACategory(
        Category.create(
          categoryName: '项目',
          parentId: 'parent',
        ).copyWith(id: 'child'),
      );
      expect(await receiverDiaries.migrateLegacyCategoriesToTags(), 0);
      await receiverCategories.insertACategory(
        Category.create(categoryName: '工作').copyWith(id: 'parent'),
      );
      expect(await receiverDiaries.migrateLegacyCategoriesToTags(), 1);
      final migrated = (await receiverDiaries.getDiaryByBusinessId('backup'))!;
      expect(migrated.tags, isEmpty);
      expect(migrated.categoryId, isNull);
      expect(migrated.legacyCategoryExcludedTags, isEmpty);
      expect(migrated.show, isFalse);
      expect(migrated.lastModified, exported.lastModified);
    } finally {
      await receiver.close();
    }
  });
}
