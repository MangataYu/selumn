import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/assistant_tools.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_models/moodiary_models.dart';

Future<String> _run(AssistantTool tool, Map<String, dynamic> input) =>
    AssistantToolRegistry.byId(tool.id)!.run(input);

void main() {
  late MoodiaryDatabase db;
  late DiaryRepository repository;

  setUp(() {
    db = MoodiaryDatabase.forTesting(NativeDatabase.memory());
    repository = DiaryRepository(db);
    getIt.registerSingleton<DiaryRepository>(repository);
  });

  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  test('新建日记接受全部可选情绪，未提供时默认为平静', () async {
    for (final mood in DiaryMood.selectableValues) {
      final output = await _run(.createDiary, {
        'title': mood.name,
        'content': '今天的记录',
        'mood': mood.name,
      });
      expect(output, startsWith('Created '), reason: mood.name);
    }
    expect(
      await _run(.createDiary, {'title': 'default', 'content': '今天的记录'}),
      startsWith('Created '),
    );

    final saved = {
      for (final diary in await repository.getAllDiaries())
        diary.title: diary.mood,
    };
    expect(saved, {
      for (final mood in DiaryMood.selectableValues) mood.name: mood,
      'default': DiaryMood.neutral,
    });
  });

  test('新建日记显式拒绝历史行为状态及非法值，不产生记录', () async {
    for (final mood in <Object>[
      for (final mood in DiaryMood.values)
        if (!mood.isSelectable) mood.name,
      'unknown-mood',
      42,
    ]) {
      final output = await _run(.createDiary, {
        'content': '不应保存',
        'mood': mood,
      });
      expect(output, startsWith('Failed:'), reason: '$mood');
      expect(output, contains('selectable emotions'), reason: '$mood');
    }
    expect(await repository.getAllDiaries(), isEmpty);
  });

  test('编辑日记可以将历史行为状态改成任一可选情绪', () async {
    final original = Diary.empty(type: .tiptap)
        .copyWith(id: 'legacy', mood: .work);
    await repository.insertADiary(original);

    for (final mood in DiaryMood.selectableValues) {
      final output = await _run(.updateDiary, {
        'id': original.id,
        'mood': mood.name,
      });
      expect(output, startsWith('Updated '), reason: mood.name);
      final saved = (await repository.getDiaryByBusinessId(original.id))!;
      expect(saved.mood, mood);
    }
  });

  test('编辑日记拒绝历史行为状态及非法值，整条编辑不落库', () async {
    final original = Diary.empty(type: .tiptap)
        .copyWith(id: 'legacy', title: '原始标题', mood: .coffee);
    await repository.insertADiary(original);
    final before = (await repository.getDiaryByBusinessId(original.id))!;

    for (final mood in <Object>[
      for (final mood in DiaryMood.values)
        if (!mood.isSelectable) mood.name,
      'unknown-mood',
      42,
    ]) {
      final output = await _run(.updateDiary, {
        'id': original.id,
        'title': '不应保存的新标题',
        'mood': mood,
      });
      expect(output, startsWith('Failed:'), reason: '$mood');
      expect(output, contains('selectable emotions'), reason: '$mood');
      expect(await repository.getDiaryByBusinessId(original.id), before);
    }
  });

  test('未指定心情的编辑保留历史值，查询与统计仍展示历史值', () async {
    for (final mood in DiaryMood.values.where((mood) => !mood.isSelectable)) {
      await repository.insertADiary(
        Diary.empty(type: .tiptap).copyWith(id: mood.name, mood: mood),
      );
      final output = await _run(.updateDiary, {
        'id': mood.name,
        'title': '只更新标题',
      });
      expect(output, startsWith('Updated '), reason: mood.name);
      final saved = (await repository.getDiaryByBusinessId(mood.name))!;
      expect(saved.mood, mood);
      expect(saved.title, '只更新标题');

      final full = await _run(.getDiary, {
        'ids': [mood.name],
      });
      expect(full, contains('mood=${mood.name}'), reason: mood.name);
    }

    final overview = await _run(.diaryOverview, {});
    for (final mood in DiaryMood.values.where((mood) => !mood.isSelectable)) {
      expect(overview, contains('${mood.name}=1'), reason: mood.name);
    }
  });
}
