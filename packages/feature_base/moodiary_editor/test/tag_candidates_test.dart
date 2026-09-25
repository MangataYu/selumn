import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_editor/src/application/tag_candidates.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

class _DiaryRepository extends Fake implements DiaryRepository {
  _DiaryRepository(this.tags, {this.error});

  final List<String> tags;
  final Object? error;

  @override
  Future<List<String>> getAllTags() async {
    final failure = error;
    if (failure != null) throw failure;
    return tags;
  }
}

void main() {
  setUp(() {
    getIt.registerSingleton<IKVStorage>(MemoryKVStorage());
  });
  tearDown(() => getIt.reset());

  void registerTags(List<String> tags) {
    getIt.registerSingleton<DiaryRepository>(_DiaryRepository(tags));
  }

  test('未保存排序时使用默认层级顺序', () async {
    registerTags(['B/x', 'A/z', 'A/a', 'A-2']);

    expect(await loadTagCandidates(''), ['A', 'A/a', 'A/z', 'A-2', 'B', 'B/x']);
  });

  test('空查询按保存的兄弟顺序排列并保持父子相邻', () async {
    registerTags(['A/a', 'A/b', 'B/child', 'C']);
    MoodiaryKVs.tagOrder.set(['B', 'B/child', 'A', 'A/b', 'A/a', 'C']);

    expect(await loadTagCandidates(''), [
      'B',
      'B/child',
      'A',
      'A/b',
      'A/a',
      'C',
    ]);
  });

  test('新兄弟按名称追加并忽略已删除和重复的排序项', () async {
    registerTags(['A/new-z', 'A/old', 'A/new-a', 'B', 'C']);
    MoodiaryKVs.tagOrder.set(['B', 'deleted', 'A', 'A/old', 'B']);

    expect(await loadTagCandidates(''), [
      'B',
      'A',
      'A/old',
      'A/new-a',
      'A/new-z',
      'C',
    ]);
  });

  test('大小写无关的子串查询保留标签排序', () async {
    registerTags(['Work/Alpha', 'Work/BETA', 'Workout', 'Personal']);
    MoodiaryKVs.tagOrder.set([
      'Work',
      'Work/BETA',
      'Work/Alpha',
      'Workout',
      'Personal',
    ]);

    expect(await loadTagCandidates('woRK/'), ['Work/BETA', 'Work/Alpha']);
  });

  test('先排序并筛选再限制为二十条候选', () async {
    final unrelated = [for (var i = 0; i < 25; i++) 'A$i'];
    final matches = [for (var i = 0; i < 25; i++) 'Match$i'];
    registerTags([...unrelated, ...matches]);
    MoodiaryKVs.tagOrder.set([...unrelated, ...matches.reversed]);

    expect(await loadTagCandidates('MATCH'), [
      for (var i = 24; i >= 5; i--) 'Match$i',
    ]);
  });

  test('每次查询读取最新保存顺序', () async {
    registerTags(['A', 'B', 'C']);
    MoodiaryKVs.tagOrder.set(['C', 'A', 'B']);
    expect(await loadTagCandidates(''), ['C', 'A', 'B']);

    MoodiaryKVs.tagOrder.set(['B', 'C', 'A']);
    expect(await loadTagCandidates(''), ['B', 'C', 'A']);
  });

  test('读取标签失败时向调用方传递错误', () async {
    final error = StateError('Tag storage unavailable');
    getIt.registerSingleton<DiaryRepository>(
      _DiaryRepository([], error: error),
    );

    await expectLater(loadTagCandidates(''), throwsA(same(error)));
  });
}
