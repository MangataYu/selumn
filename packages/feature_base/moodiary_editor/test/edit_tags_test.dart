import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_editor/moodiary_editor.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

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
  test('在标签筛选下新建记录会预填该标签', () async {
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
