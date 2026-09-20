import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/application/tool_approval.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/assistant_tools.dart';
import 'package:moodiary_assistant/src/presentation/tool_approval_preview.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

String _body(List<Map<String, Object>> nodes) => jsonEncode({
  'type': 'doc',
  'content': [
    {'type': 'paragraph', 'content': nodes},
  ],
});

Map<String, Object> _markedTag(String tag) => {
  'type': 'text',
  'text': '#$tag',
  'marks': [
    {
      'type': 'tag',
      'attrs': {'tag': tag},
    },
  ],
};

Diary _diary(
  String id, {
  List<String> tags = const [],
  String text = '苹果',
  String? body,
  bool show = true,
}) {
  final content =
      body ??
      _body([
        {'type': 'text', 'text': text},
      ]);
  return Diary.empty(type: .tiptap).copyWith(
    id: id,
    title: '记录 $id',
    content: content,
    contentText: TiptapContent.parse(content).plainText,
    tags: tags,
    show: show,
    mood: .fulfilled,
    time: DateTime.utc(2026, 1, 1),
    lastModified: DateTime.utc(2026, 1, 2),
  );
}

Future<String> _run(AssistantTool tool, Map<String, dynamic> input) =>
    AssistantToolRegistry.byId(tool.id)!.run(input);

Set<String> _rowIds(String output) => RegExp(
  r'^id=(\S+)',
  multiLine: true,
).allMatches(output).map((match) => match.group(1)!).toSet();

void main() {
  late MoodiaryDatabase db;
  late DiaryRepository repository;

  setUp(() {
    db = MoodiaryDatabase.forTesting(NativeDatabase.memory());
    repository = DiaryRepository(db);
    // Tag operations must not depend on the retired category repository or a
    // semantic index being registered.
    getIt.registerSingleton<DiaryRepository>(repository);
  });

  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  test('create normalizes and deduplicates explicit tag paths', () async {
    final output = await _run(.createDiary, {
      'title': '散步',
      'content': '今天在公园散步。',
      'tags': [' #生活/运动 ', '生活/运动', '工作'],
    });

    expect(output, startsWith('Created '));
    final saved = (await repository.getAllDiaries()).single;
    expect(saved.tags, ['生活/运动', '工作']);
    expect(saved.categoryId, isNull);
    expect(saved.contentText, contains('今天在公园散步。'));
  });

  test(
    'invalid paths and non-array tags fail without creating diaries',
    () async {
      for (final tags in <Object>[
        ['生活//运动'],
        ['生活/'],
        ['生活', 42],
        '生活',
      ]) {
        final output = await _run(.createDiary, {
          'title': '不应保存',
          'content': '正文',
          'tags': tags,
        });
        expect(output, startsWith('Failed:'), reason: '$tags');
      }
      expect(await repository.getAllDiaries(), isEmpty);
    },
  );

  test(
    'tag replacement removes only omitted marks and preserves other fields',
    () async {
      final original = _diary(
        'edit',
        tags: ['生活', '生活/运动', '手动'],
        body: _body([
          {
            'type': 'text',
            'text': '保留加粗 ',
            'marks': [
              {'type': 'bold'},
            ],
          },
          _markedTag('生活'),
          {'type': 'text', 'text': ' 与 '},
          _markedTag('生活/运动'),
          {'type': 'text', 'text': ' 后文'},
        ]),
      );
      await repository.insertADiary(original);

      final output = await _run(.updateDiary, {
        'id': original.id,
        'tags': ['生活/运动', '#新标签', '新标签'],
      });
      expect(output, startsWith('Updated '));
      final saved = (await repository.getDiaryByBusinessId(original.id))!;
      expect(saved.tags, ['生活/运动', '新标签']);
      expect(TiptapContent.tags(saved.content), ['生活/运动']);
      expect(saved.contentText, contains('保留加粗 生活 与 #生活/运动 后文'));
      expect(saved.content, contains('"type":"bold"'));
      expect(saved.title, original.title);
      expect(saved.time, original.time);
      expect(saved.mood, original.mood);
      expect(saved.show, original.show);
      expect(saved.lastModified.isAfter(original.lastModified), isTrue);

      await _run(.updateDiary, {'id': original.id, 'title': '只改标题'});
      final titleOnly = (await repository.getDiaryByBusinessId(original.id))!;
      expect(titleOnly.tags, saved.tags);
      expect(titleOnly.content, saved.content);
    },
  );

  test(
    'empty tags clear manual and inline tags without losing body text',
    () async {
      await repository.insertADiary(
        _diary(
          'clear',
          tags: ['手动'],
          body: _body([
            {'type': 'text', 'text': '开始 '},
            _markedTag('生活/运动'),
            {'type': 'text', 'text': ' 结束'},
          ]),
        ),
      );

      expect(
        await _run(.updateDiary, {'id': 'clear', 'tags': []}),
        startsWith('Updated '),
      );
      final saved = (await repository.getDiaryByBusinessId('clear'))!;
      expect(saved.tags, isEmpty);
      expect(TiptapContent.tags(saved.content), isEmpty);
      expect(saved.contentText, '开始 生活/运动 结束');
      // A later ordinary save must not restore the removed inline tag.
      await repository.updateADiary(newDiary: saved);
      expect((await repository.getDiaryByBusinessId('clear'))!.tags, isEmpty);
    },
  );

  test('invalid replacement does not partially change title or tags', () async {
    final original = _diary('unchanged', tags: ['生活/运动']);
    await repository.insertADiary(original);
    final output = await _run(.updateDiary, {
      'id': original.id,
      'title': '不应修改',
      'tags': ['生活//错误'],
    });
    expect(output, startsWith('Failed:'));
    expect(await repository.getDiaryByBusinessId(original.id), original);
  });

  Future<void> seedSearch() => repository.insertDiaries([
    _diary('sport', tags: ['生活/运动', '生活']),
    _diary('reading', tags: ['生活/阅读'], text: '香蕉'),
    _diary('similar', tags: ['生活方式']),
    _diary('hidden', tags: ['生活/运动'], show: false),
    _diary('untagged'),
  ]);

  test(
    'parent tag lists descendants once with exact total before limiting',
    () async {
      await seedSearch();
      final all = await _run(.searchDiaries, {'tag': '生活'});
      expect(all, startsWith('2 matches:'));
      expect(_rowIds(all), {'sport', 'reading'});
      expect(all, contains('tags=["生活/运动","生活"]'));

      final limited = await _run(.searchDiaries, {'tag': '生活', 'limit': 1});
      expect(limited, startsWith('2 matches; the first 1 follow.'));
      expect(_rowIds(limited), hasLength(1));

      final unfiltered = await _run(.searchDiaries, {'limit': 1});
      expect(unfiltered, startsWith('4 matches; the first 1 follow.'));
    },
  );

  test(
    'query plus parent tag applies FTS and meaning mode explicitly falls back',
    () async {
      await seedSearch();
      for (final mode in ['keyword', 'meaning']) {
        final output = await _run(.searchDiaries, {
          'query': '苹果',
          'tag': '生活',
          'mode': mode,
        });
        expect(output, startsWith('1 matches:'), reason: mode);
        expect(_rowIds(output), {'sport'});
        expect(output, contains('via=keyword'));
        expect(
          output,
          contains(
            'Tag filters use keyword search; semantic search was not run.',
          ),
        );
      }
    },
  );

  test(
    'overview counts each parent once and derives untagged independently',
    () async {
      await repository.insertDiaries([
        _diary('many', tags: ['生活', '生活/运动', '工作']),
        _diary('reading', tags: ['生活/阅读']),
        _diary('untagged'),
        _diary('hidden', tags: ['生活/运动'], show: false),
      ]);
      final output = await _run(.diaryOverview, {});
      expect(output, startsWith('Total entries=3'));
      expect(
        output,
        contains('by tag (parents include descendants; counts overlap):'),
      );
      for (final row in [
        '- 生活: 2',
        '- 生活/运动: 1',
        '- 生活/阅读: 1',
        '- 工作: 1',
        '- untagged: 1',
      ]) {
        expect(output.split('\n'), contains(row));
      }
    },
  );

  test('full diary output includes current tags', () async {
    await repository.insertADiary(_diary('read', tags: ['生活/运动', '工作']));
    final output = await _run(.getDiary, {
      'ids': ['read'],
    });
    expect(output, contains('id=read'));
    expect(output, contains('tags=生活/运动, 工作'));
    expect(output, contains('苹果'));
  });

  test(
    'approval preview shows replacing tags and explicitly clearing them',
    () async {
      await repository.insertADiary(_diary('preview', tags: ['生活/运动']));
      for (final tags in <List<String>>[
        ['工作'],
        [],
      ]) {
        final preview = await buildToolApprovalPreview(
          ToolApprovalRequest(
            callId: 'tags-preview',
            tool: .updateDiary,
            args: {'id': 'preview', 'tags': tags},
            tier: .write,
          ),
          l10n,
        );
        final line = preview.lines.singleWhere(
          (line) => line.label == l10n.common.tag,
        );
        expect(line.value, contains('生活/运动'));
        expect(line.value, contains(tags.isEmpty ? l10n.diary.tagNoTag : '工作'));
        expect(preview.warning, isNull);
      }
      expect((await repository.getDiaryByBusinessId('preview'))!.tags, [
        '生活/运动',
      ]);
    },
  );
}
