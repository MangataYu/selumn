import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

Map<String, Object> marked(String text, String tag, {bool bold = false}) => {
  'type': 'text',
  'text': text,
  'marks': [
    {
      'type': 'tag',
      'attrs': {'tag': tag},
    },
    if (bold) {'type': 'bold'},
  ],
};

String doc(List<Object> content) => jsonEncode({
  'type': 'doc',
  'content': [
    {'type': 'paragraph', 'content': content},
  ],
});

void main() {
  test('paths normalize, deduplicate and respect segment boundaries', () {
    expect(TagPath.normalize(' #工作 / 项目 '), '工作/项目');
    expect(TagPath.normalize('工作//项目'), isNull);
    expect(TagPath.normalizeAll(['工作', '#工作', '旧#名称']), ['工作', '旧#名称']);
    expect(TagPath.ancestors('工作/项目/会议'), ['工作', '工作/项目', '工作/项目/会议']);
    expect(TagPath.matches('工作/项目', '工作'), isTrue);
    expect(TagPath.matches('工作室', '工作'), isFalse);
    expect(TagPath.isInline('工作/项目-1'), isTrue);
    expect(TagPath.isInline('工作/项目 1'), isFalse);
  });

  test('only explicit marks are tags and duplicates collapse', () {
    final content = doc([
      {'type': 'text', 'text': 'https://example.com/#原样 #普通文字 '},
      marked('#工作/项目', '工作/项目'),
      marked('#工作/项目', '工作/项目'),
    ]);
    expect(TiptapContent.tags(content), ['工作/项目']);
    expect(TiptapContent.tags('# 普通 Markdown'), isEmpty);
    expect(TiptapContent.parse(content).plainText, contains('#工作/项目'));
  });

  test('rename updates a formatted token once and keeps descendants', () {
    final content = doc([
      marked('#工', '工作/项目', bold: true),
      marked('作/项目', '工作/项目'),
      {'type': 'text', 'text': ' '},
      marked('#工作室', '工作室'),
    ]);
    final renamed = TiptapContent.renameTag(content, '工作', '事业');
    expect(TiptapContent.tags(renamed), ['事业/项目', '工作室']);
    expect(TiptapContent.parse(renamed).plainText, '#事业/项目 #工作室');
    expect(renamed, contains('bold'));
  });

  test('remove retains tag name as text and exact mode retains subtags', () {
    final content = doc([
      marked('#', '工作'),
      marked('工作', '工作'),
      {'type': 'text', 'text': ' '},
      marked('#工作/项目', '工作/项目'),
    ]);
    final exact = TiptapContent.removeTag(content, '工作', descendants: false);
    expect(TiptapContent.tags(exact), ['工作/项目']);
    expect(TiptapContent.parse(exact).plainText, '工作 #工作/项目');
    final all = TiptapContent.removeTag(content, '工作');
    expect(TiptapContent.tags(all), isEmpty);
    expect(TiptapContent.parse(all).plainText, '工作 工作/项目');
  });

  test(
    'removing a formatted legacy tag preserves internal hash characters',
    () {
      final content = doc([marked('#C', 'C#'), marked('#', 'C#', bold: true)]);
      final removed = TiptapContent.removeTag(content, 'C#');
      expect(TiptapContent.tags(removed), isEmpty);
      expect(TiptapContent.parse(removed).plainText, 'C#');
      expect(removed, contains('bold'));
    },
  );
}
