import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_export/moodiary_export.dart';
import 'package:moodiary_models/moodiary_models.dart';

class _Diaries extends Fake implements DiaryRepository {
  final List<Diary> diaries;
  _Diaries(this.diaries);

  @override
  Future<List<Diary>> getAllDiaries() async => diaries;
}

void main() {
  tearDown(getIt.reset);

  test('tag export includes descendants once, excludes recycle and prefix siblings', () async {
    final base = Diary.empty(type: .tiptap);
    getIt.registerSingleton<DiaryRepository>(
      _Diaries([
        base.copyWith(id: 'parent', tags: ['工作']),
        base.copyWith(id: 'child', tags: ['工作/项目', '工作/会议']),
        base.copyWith(id: 'sibling', tags: ['工作室']),
        base.copyWith(id: 'hidden', tags: ['工作'], show: false),
        base.copyWith(id: 'untagged', tags: []),
      ]),
    );
    final entries = await const TagScope({'工作', '工作/项目'}, '工作').resolve();
    expect(entries.map((d) => d.id), unorderedEquals(['parent', 'child']));
    final untagged = await const TagScope({null}, '无标签').resolve();
    expect(untagged.single.id, 'untagged');
  });

  test('tag marks preserve ordinary text in export', () {
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
    final result = TiptapToIr.convert(
      id: 'entry',
      title: 'Title',
      time: DateTime.utc(2026),
      content: content,
      tags: ['工作/项目'],
      resolvePath: (_, name) => name,
    );
    expect(result.unsupportedNodes, isEmpty);
    expect(result.tags, ['工作/项目']);
    // The export IR retains tag text without requiring a special node type.
    expect(result.blocks.single, isA<IrBlock_Paragraph>());
    expect(
      (result.blocks.single as IrBlock_Paragraph).spans.single.text,
      '#工作/项目',
    );
  });
}
