import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_editor/moodiary_editor.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

class _DiaryRepository extends Fake implements DiaryRepository {
  _DiaryRepository(this.diary);

  final Diary diary;

  @override
  Future<Diary?> getDiaryByBusinessId(String id) async =>
      diary.id == id ? diary : null;

  @override
  Stream<DiaryEvent> get diaryEvents => const Stream.empty();
}

String body(List<String> tags) => jsonEncode({
  'type': 'doc',
  'content': [
    {
      'type': 'paragraph',
      'content': [
        for (final tag in tags) ...[
          {
            'type': 'text',
            'text': '#$tag',
            'marks': [
              {
                'type': 'tag',
                'attrs': {'tag': tag},
              },
            ],
          },
          {'type': 'text', 'text': ' '},
        ],
      ],
    },
  ],
});

void main() {
  setUp(() {
    getIt.registerSingleton<IKVStorage>(MemoryKVStorage());
  });
  tearDown(() => getIt.reset());

  test('未配置默认标签时新建记录没有标签', () async {
    final container = ProviderContainer.test();
    final provider = editControllerProvider(null, defaultType: .tiptap);
    container.listen(provider, (_, _) {});
    final diary = await container.read(provider.future);
    expect(diary.tags, isEmpty);
  });

  test('新建记录预填默认标签且允许删除', () async {
    MoodiaryKVs.defaultTag.set(' #生活 / 随记 ');
    final container = ProviderContainer.test();
    final provider = editControllerProvider(null, defaultType: .tiptap);
    container.listen(provider, (_, _) {});
    final diary = await container.read(provider.future);
    expect(diary.tags, ['生活/随记']);
    expect(diary.categoryId, isNull);

    container.read(provider.notifier).changeTags([]);
    expect(container.read(provider).value!.tags, isEmpty);
  });

  test('取消默认标签后新建记录没有标签', () async {
    MoodiaryKVs.defaultTag.set('生活');
    MoodiaryKVs.defaultTag.set('');
    final container = ProviderContainer.test();
    final provider = editControllerProvider('', defaultType: .tiptap);
    container.listen(provider, (_, _) {});
    final diary = await container.read(provider.future);
    expect(diary.tags, isEmpty);
  });

  test('在标签筛选下新建记录会预填该标签', () async {
    MoodiaryKVs.defaultTag.set('生活');
    final container = ProviderContainer.test();
    final provider = editControllerProvider(
      null,
      defaultType: .tiptap,
      defaultTag: '工作/项目',
    );
    container.listen(provider, (_, _) {});
    final diary = await container.read(provider.future);
    expect(diary.tags, ['工作/项目']);
    expect(diary.categoryId, isNull);
    expect(diary.legacyCategoryExcludedTags, isEmpty);
  });

  test('显式空标签不回退到默认标签', () async {
    MoodiaryKVs.defaultTag.set('生活');
    final container = ProviderContainer.test();
    final provider = editControllerProvider(
      null,
      defaultType: .tiptap,
      defaultTag: '',
    );
    container.listen(provider, (_, _) {});
    final diary = await container.read(provider.future);
    expect(diary.tags, isEmpty);
  });

  test('更改默认标签不覆盖已经打开的新建草稿', () async {
    MoodiaryKVs.defaultTag.set('生活');
    final container = ProviderContainer.test();
    final provider = editControllerProvider(null, defaultType: .tiptap);
    container.listen(provider, (_, _) {});
    final original = await container.read(provider.future);
    container.read(provider.notifier).changeTitle('正在编辑');

    MoodiaryKVs.defaultTag.set('工作');
    await container.pump();
    final current = container.read(provider).value!;
    expect(current.id, original.id);
    expect(current.title, '正在编辑');
    expect(current.tags, ['生活']);
  });

  for (final tags in <List<String>>[
    [],
    ['已有标签'],
  ]) {
    test('打开已有记录保留原标签 $tags', () async {
      MoodiaryKVs.defaultTag.set('生活');
      final existing = Diary.empty(type: .tiptap)
          .copyWith(id: 'existing', tags: tags);
      getIt.registerSingleton<DiaryRepository>(_DiaryRepository(existing));
      final container = ProviderContainer.test();
      final provider = editControllerProvider(
        'existing',
        defaultType: .tiptap,
        defaultTag: '工作',
      );
      container.listen(provider, (_, _) {});
      final diary = await container.read(provider.future);
      expect(diary, existing);
    });
  }

  test('只有默认标签的空白草稿不会保存为日记', () async {
    MoodiaryKVs.defaultTag.set('生活');
    final container = ProviderContainer.test();
    final provider = editControllerProvider(null, defaultType: .tiptap);
    container.listen(provider, (_, _) {});
    await container.read(provider.future);
    expect(
      await container.read(provider.notifier).autoSave(),
      DraftSaveResult.saved,
    );
  });

  Future<ProviderContainer> setup(
    List<String> inline,
    List<String> manual, {
    String? legacyCategoryId,
    List<String> excluded = const [],
  }) async {
    final content = body(inline);
    final diary = Diary.empty(type: .tiptap).copyWith(
      id: 'diary',
      content: content,
      contentText: TiptapContent.parse(content).plainText,
      tags: [...manual, ...inline],
      categoryId: legacyCategoryId,
      legacyCategoryExcludedTags: excluded,
    );
    final container = ProviderContainer.test(
      overrides: [
        getDiaryProvider(id: 'diary')
            .overrideWith((ref) => Stream.value(diary)),
      ],
    );
    container.listen(editControllerProvider('diary'), (_, _) {});
    await container.read(editControllerProvider('diary').future);
    return container;
  }

  test('正文标签编辑和撤销保持手工标签并去重', () async {
    final container = await setup(['工作'], ['手工']);
    final controller = container.read(editControllerProvider('diary').notifier);
    final changed = body(['生活/运动', '生活/运动']);
    controller.changeContent(changed);
    expect(container.read(editControllerProvider('diary')).value!.tags, [
      '手工',
      '生活/运动',
    ]);
    controller.changeContent(body(['工作']));
    expect(container.read(editControllerProvider('diary')).value!.tags, [
      '手工',
      '工作',
    ]);
  });

  test('顶部删除只解除该标签，保留名称和子标签', () async {
    final container = await setup(['工作', '工作/项目'], ['手工']);
    final controller = container.read(editControllerProvider('diary').notifier);
    controller.changeTags(['手工', '工作/项目']);
    final diary = container.read(editControllerProvider('diary')).value!;
    expect(diary.tags, ['手工', '工作/项目']);
    expect(TiptapContent.tags(diary.content), ['工作/项目']);
    expect(diary.contentText, '工作 #工作/项目');
  });

  test('规范化层级和重复值时保留旧的非规范标签', () async {
    final container = await setup([], []);
    container.read(editControllerProvider('diary').notifier).changeTags([
      '#工作 / 项目',
      '工作/项目',
      '无效//层级',
    ]);
    expect(container.read(editControllerProvider('diary')).value!.tags, [
      '工作/项目',
      '无效//层级',
    ]);
  });

  test('待迁移记录删除正文标签后记住意图，撤销可恢复', () async {
    final container = await setup(
      ['工作/项目'],
      ['手工'],
      legacyCategoryId: 'pending',
    );
    final controller = container.read(editControllerProvider('diary').notifier);
    controller.changeContent(body([]));
    expect(
      container
          .read(editControllerProvider('diary'))
          .value!
          .legacyCategoryExcludedTags,
      ['工作/项目'],
    );
    controller.changeContent(body(['工作/项目']));
    final restored = container.read(editControllerProvider('diary')).value!;
    expect(restored.legacyCategoryExcludedTags, isEmpty);
    expect(restored.tags, ['手工', '工作/项目']);
  });

  test('新增一个子标签不撤回对整个父标签的旧排除意图', () async {
    final container = await setup(
      [],
      [],
      legacyCategoryId: 'pending',
      excluded: ['工作'],
    );
    final controller = container.read(editControllerProvider('diary').notifier);
    controller.changeTags(['工作/新项目']);
    final current = container.read(editControllerProvider('diary')).value!;
    expect(current.tags, ['工作/新项目']);
    expect(current.legacyCategoryExcludedTags, ['工作']);
  });
}
