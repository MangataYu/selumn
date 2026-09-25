import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/application/diary_citation.dart';
import 'package:moodiary_assistant/src/application/session_title_display.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';

void main() {
  test('中文取第一句而非后续内容', () {
    expect(localSessionTitle('这周搬家好累。帮我看看日记。'), '这周搬家好累');
  });

  test('跳过空行，保留首个非空句行', () {
    expect(localSessionTitle('\n\n。\n  搬家后的疲惫  \n后面的细节'), '搬家后的疲惫');
    expect(localSessionTitle('   \n\t'), isEmpty);
  });

  test('英文句号和问号可结束第一句', () {
    expect(
      localSessionTitle('How did I sleep? Please check my diary.'),
      'How did I sleep',
    );
    expect(
      localSessionTitle('Review my sleep. Then suggest a plan.'),
      'Review my sleep',
    );
    expect(localSessionTitle('I slept 7.5 hours'), 'I slept 7.5 hours');
  });

  test('清理控制字符并折叠行内空白', () {
    expect(localSessionTitle('\u200B搬家\u202E后的\u0008   疲惫\t感'), '搬家后的 疲惫 感');
  });

  test('日记引用只展示用户文本', () {
    expect(localSessionTitle(citeDiary('帮我分析今天的心情', 'diary-id')), '帮我分析今天的心情');
    expect(localSessionTitle(citeDiary('', 'diary-id')), isEmpty);
  });

  test('继续标记不作为标题', () {
    expect(localSessionTitle(' $continueTurnMarker '), isEmpty);
    expect(
      localSessionTitle(citeDiary(continueTurnMarker, 'diary-id')),
      isEmpty,
    );
  });

  test('长标题限制为 24 个字符', () {
    expect(localSessionTitle('搬' * 30), '搬' * 24);
    expect(localSessionTitle('a' * 30), 'a' * 24);
  });

  test('组合 emoji 和音调字符不会被切断', () {
    const family = '👨‍👩‍👧‍👦';
    const accent = 'e\u0301';
    expect(localSessionTitle('${'搬' * 23}$family 更多'), '${'搬' * 23}$family');
    expect(localSessionTitle('${'搬' * 23}$accent 更多'), '${'搬' * 23}$accent');
  });

  test('普通用户的 think 标签内容不会被当作模型推理删除', () {
    expect(localSessionTitle('<think>你好</think>'), '<think>你好</think>');
  });
}
