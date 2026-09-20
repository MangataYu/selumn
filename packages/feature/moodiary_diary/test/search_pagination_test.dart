import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/application/search_controller.dart';
import 'package:moodiary_models/moodiary_models.dart';

void main() {
  late MoodiaryDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = MoodiaryDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    final repository = DiaryRepository(db);
    await repository.insertDiaries([
      for (var i = 0; i < 40; i++)
        Diary.create(
          title: '第 $i 篇',
          content: '',
          contentText: '今天吃了一个苹果',
          mood: .neutral,
          imageName: const [],
          audioName: const [],
          videoName: const [],
          tags: [i < 35 ? '生活/旅行' : '阅读'],
          type: .tiptap,
        ),
    ]);
    getIt.registerSingleton<DiaryRepository>(repository);
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await getIt.reset();
    await db.close();
  });

  test('换查询会作废在途的 loadMore，不会把分页卡死', () async {
    final controller = container.read(diarySearchControllerProvider.notifier);
    await controller.search('苹果');
    expect(container.read(diarySearchControllerProvider).totalCount, 40);
    expect(container.read(diarySearchControllerProvider).hasMore, isTrue);

    final pending = controller.loadMore();
    await controller.search('苹果');
    await pending;

    final state = container.read(diarySearchControllerProvider);
    expect(state.isLoadingMore, isFalse, reason: '过期的 loadMore 不清标志');
    expect(state.results, hasLength(30));

    await controller.loadMore();
    expect(
      container.read(diarySearchControllerProvider).results,
      hasLength(40),
    );
  });

  test('父标签过滤保持搜索计数与分页一致', () async {
    final controller = container.read(diarySearchControllerProvider.notifier);
    await controller.search('苹果');
    await controller.setTag('生活');
    var state = container.read(diarySearchControllerProvider);
    expect(state.totalCount, 35);
    expect(state.results, hasLength(30));
    expect(
      state.results.every((hit) => hit.diary.tags.contains('生活/旅行')),
      isTrue,
    );

    await controller.loadMore();
    state = container.read(diarySearchControllerProvider);
    expect(state.results, hasLength(35));
    expect(state.hasMore, isFalse);

    await controller.setTag(null);
    expect(container.read(diarySearchControllerProvider).totalCount, 40);
  });

  test('标签重命名事件自动刷新当前搜索结果和计数', () async {
    final refreshed = Completer<void>();
    final subscription = container.listen(diarySearchControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.isSearching == true &&
          !next.isSearching &&
          next.totalCount == 0 &&
          !refreshed.isCompleted) {
        refreshed.complete();
      }
    });
    addTearDown(subscription.close);
    final controller = container.read(diarySearchControllerProvider.notifier);
    await controller.search('苹果');
    await controller.setTag('生活');
    expect(container.read(diarySearchControllerProvider).totalCount, 35);

    await getIt<DiaryRepository>().renameTag('生活', '日常');
    await refreshed.future.timeout(const Duration(seconds: 5));

    final state = container.read(diarySearchControllerProvider);
    expect(state.tag, '生活');
    expect(state.results, isEmpty);
    expect(state.totalCount, 0);
    expect(state.hasMore, isFalse);
  });
}
