import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';
import 'package:moodiary_diary/src/application/diary_selection.dart';
import 'package:moodiary_diary/src/application/tag_management.dart';
import 'package:moodiary_diary/src/presentation/tag/tag_manager_page.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

class _RecordingDiaryRepository extends Fake implements DiaryRepository {
  final renamedTags = <(String, String)>[];
  final deletedTags = <String>[];
  bool renameFails = false;
  bool deleteFails = false;
  Completer<int>? pendingRename;
  Completer<int>? pendingDelete;

  @override
  Future<int> renameTag(String tag, String replacement) async {
    renamedTags.add((tag, replacement));
    if (renameFails) throw StateError('Cannot rename tag');
    return pendingRename?.future ?? Future.value(1);
  }

  @override
  Future<int> deleteTag(String tag) async {
    deletedTags.add(tag);
    if (deleteFails) throw StateError('Cannot delete tag');
    return pendingDelete?.future ?? Future.value(1);
  }
}

void main() {
  const tags = ['生活/旅行/海边', '生活/旅行记', '工作'];
  const expandedPaths = ['生活', '生活/旅行', '生活/旅行/海边', '生活/旅行记'];
  const tagOrder = ['工作', '生活', '生活/旅行记', '生活/旅行', '生活/旅行/海边'];
  late MemoryKVStorage kv;
  late _RecordingDiaryRepository repository;
  late ProviderContainer container;
  late NavigatorState navigator;

  final renameField = find.descendant(
    of: find.byType(MField),
    matching: find.byType(TextField),
  );
  final searchField = find.descendant(
    of: find.byType(SearchBar),
    matching: find.byType(TextField),
  );

  Finder row(String path) => find.byKey(ValueKey('tag-manager-row:$path'));

  setUp(() {
    kv = MemoryKVStorage();
    kv.data[MoodiaryKVs.expandedTagPaths.name] = expandedPaths;
    kv.data[MoodiaryKVs.tagOrder.name] = tagOrder;
    repository = _RecordingDiaryRepository();
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(kv);
        gi.registerSingleton<DiaryRepository>(repository);
      },
    );
  });

  tearDown(() => getIt.popScope());

  Future<void> pumpPage(
    WidgetTester tester, {
    Future<List<String>> Function()? loadTags,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: muiTestApp(
          Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              navigator = Navigator.of(context);
              return TextButton(
                key: const ValueKey('open-tag-manager'),
                onPressed: () => navigator.push<void>(
                  MaterialPageRoute(builder: (_) => const TagManagerPage()),
                ),
                child: const Text('Open'),
              );
            },
          ),
          overrides: [
            diaryTagsProvider.overrideWith(
              (ref) => loadTags?.call() ?? Future.value(tags),
            ),
            tagDiaryCountsProvider.overrideWith(
              (ref) async =>
                  (byTag: const <String, int>{}, total: 0, untagged: 0),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-tag-manager')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> openAction(
    WidgetTester tester,
    String action, {
    String path = '生活/旅行',
  }) async {
    await tester.tap(row(path));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  void selectTravelDiary() {
    container.read(tagManagementProvider).setDefaultTag('生活/旅行/海边');
    container
        .read(homeDiaryFilterProvider.notifier)
        .select(const DiaryFilter.tag('生活/旅行/海边'));
    container.read(diarySelectionProvider.notifier).enter('selected-diary');
  }

  void expectRenamedState() {
    expect(repository.renamedTags, [('生活/旅行', '生活/出游')]);
    expect(kv.data[MoodiaryKVs.tagOrder.name], [
      '工作',
      '生活',
      '生活/旅行记',
      '生活/出游',
      '生活/出游/海边',
    ]);
    expect(
      kv.data[MoodiaryKVs.expandedTagPaths.name],
      unorderedEquals(['生活', '生活/出游', '生活/出游/海边', '生活/旅行记']),
    );
    expect(
      container.read(homeDiaryFilterProvider),
      const DiaryFilter.tag('生活/出游/海边'),
    );
    expect(container.read(diarySelectionProvider), isEmpty);
    expect(kv.data[MoodiaryKVs.defaultTag.name], '生活/出游/海边');
  }

  void expectDeletedState() {
    expect(repository.deletedTags, ['生活/旅行']);
    expect(kv.data[MoodiaryKVs.tagOrder.name], ['工作', '生活', '生活/旅行记']);
    expect(
      kv.data[MoodiaryKVs.expandedTagPaths.name],
      unorderedEquals(['生活', '生活/旅行记']),
    );
    expect(container.read(homeDiaryFilterProvider), const DiaryFilter.all());
    expect(container.read(diarySelectionProvider), isEmpty);
    expect(kv.data[MoodiaryKVs.defaultTag.name], '');
  }

  test('an unused default needs no saved configuration', () async {
    final scope = ProviderContainer();
    addTearDown(scope.dispose);
    final management = scope.read(tagManagementProvider);

    expect(management.savedDefaultTag, '');
    management.setDefaultTag('');
    await management.rename('生活/旅行', '生活/出游');
    await management.delete('生活/出游');

    expect(kv.data.containsKey(MoodiaryKVs.defaultTag.name), isFalse);
  });

  test(
    'rename and delete preserve similar siblings and ancestor defaults',
    () async {
      final scope = ProviderContainer();
      addTearDown(scope.dispose);
      final management = scope.read(tagManagementProvider);

      for (final defaultTag in ['生活/旅行记', '生活', '工作']) {
        management.setDefaultTag(defaultTag);
        await management.rename('生活/旅行', '生活/出游');
        expect(management.savedDefaultTag, defaultTag);
        await management.delete('生活/旅行');
        expect(management.savedDefaultTag, defaultTag);
      }
    },
  );

  test('rename and delete update the exact default tag', () async {
    final scope = ProviderContainer();
    addTearDown(scope.dispose);
    final management = scope.read(tagManagementProvider);

    management.setDefaultTag('生活/旅行');
    await management.rename('生活/旅行', '生活/出游');
    expect(management.savedDefaultTag, '生活/出游');
    await management.delete('生活/出游');
    expect(management.savedDefaultTag, '');
  });

  test('failed delete preserves the saved default tag', () async {
    final scope = ProviderContainer();
    addTearDown(scope.dispose);
    final management = scope.read(tagManagementProvider);
    management.setDefaultTag('生活/旅行/海边');
    repository.deleteFails = true;

    await expectLater(management.delete('生活/旅行'), throwsStateError);

    expect(management.savedDefaultTag, '生活/旅行/海边');
    expect(kv.data[MoodiaryKVs.tagOrder.name], tagOrder);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
  });

  testWidgets(
    'opening tag management leaves the default unset without saving',
    (tester) async {
      await pumpPage(tester);

      expect(find.text('默认标签'), findsOneWidget);
      expect(find.text('未设置'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tag-manager-clear-default')),
        findsNothing,
      );
      expect(kv.data.containsKey(MoodiaryKVs.defaultTag.name), isFalse);
    },
  );

  testWidgets('the menu sets, switches, and cancels the default tag', (
    tester,
  ) async {
    await pumpPage(tester);

    await openAction(tester, '设为默认标签');
    expect(kv.data[MoodiaryKVs.defaultTag.name], '生活/旅行');
    expect(find.text('#生活/旅行'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tag-manager-default:生活/旅行')),
      findsOneWidget,
    );
    expect(find.byTooltip('默认标签'), findsOneWidget);

    await openAction(tester, '设为默认标签', path: '工作');
    expect(kv.data[MoodiaryKVs.defaultTag.name], '工作');
    expect(find.text('#工作'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tag-manager-default:生活/旅行')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('tag-manager-default:工作')),
      findsOneWidget,
    );

    await openAction(tester, '取消默认标签', path: '工作');
    expect(kv.data[MoodiaryKVs.defaultTag.name], '');
    expect(find.text('未设置'), findsOneWidget);
    expect(find.byTooltip('默认标签'), findsNothing);
    expect(repository.renamedTags, isEmpty);
    expect(repository.deletedTags, isEmpty);
  });

  testWidgets('the summary shows and clears an existing default tag', (
    tester,
  ) async {
    kv.data[MoodiaryKVs.defaultTag.name] = '生活/旅行/海边';
    await pumpPage(tester);

    expect(find.text('#生活/旅行/海边'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tag-manager-default:生活/旅行/海边')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tag-manager-clear-default')));
    await tester.pumpAndSettle();

    expect(kv.data[MoodiaryKVs.defaultTag.name], '');
    expect(find.text('未设置'), findsOneWidget);
    expect(find.byTooltip('默认标签'), findsNothing);
  });

  testWidgets('shows ordered hierarchy and searches with full matching paths', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('标签管理'), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(tester.widget<SearchBar>(find.byType(SearchBar)).hintText, '搜索标签');
    for (final path in tagOrder) {
      expect(row(path), findsOneWidget);
    }
    for (var i = 1; i < tagOrder.length; i++) {
      expect(
        tester.getTopLeft(row(tagOrder[i])).dy,
        greaterThan(tester.getTopLeft(row(tagOrder[i - 1])).dy),
      );
    }
    expect(
      tester.getTopLeft(find.text('海边')).dx,
      greaterThan(tester.getTopLeft(find.text('旅行')).dx),
    );

    await tester.enterText(searchField, '旅行');
    await tester.pumpAndSettle();
    expect(find.text('生活/旅行'), findsOneWidget);
    expect(find.text('生活/旅行/海边'), findsOneWidget);
    expect(find.text('生活/旅行记'), findsOneWidget);
    expect(row('工作'), findsNothing);
    expect(row('生活'), findsNothing);

    await tester.enterText(searchField, 'missing');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的标签'), findsOneWidget);
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle();
    expect(row('工作'), findsOneWidget);
  });

  testWidgets('row tap, overflow, and long press all open the bottom menu', (
    tester,
  ) async {
    await pumpPage(tester);
    for (var entry = 0; entry < 3; entry++) {
      switch (entry) {
        case 0:
          await tester.tap(row('生活/旅行'));
        case 1:
          await tester.tap(
            find.descendant(
              of: row('生活/旅行'),
              matching: find.byType(IconButton),
            ),
          );
        case 2:
          await tester.longPress(row('生活/旅行'));
      }
      await tester.pumpAndSettle();
      expect(find.byType(MSheetScaffold<String>), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('#生活/旅行'), findsOneWidget);
      expect(find.text('设为默认标签'), findsOneWidget);
      expect(find.text('重命名标签'), findsOneWidget);
      expect(find.text('删除标签'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }
    expect(repository.renamedTags, isEmpty);
    expect(repository.deletedTags, isEmpty);
    expect(kv.data.containsKey(MoodiaryKVs.defaultTag.name), isFalse);
  });

  Future<void> reorderRoots(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('tag-manager-sort')));
    await tester.pumpAndSettle();
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 1);
    await tester.pumpAndSettle();
  }

  testWidgets('sort only writes on save and refreshes the manager order', (
    tester,
  ) async {
    await pumpPage(tester);
    await reorderRoots(tester);
    expect(kv.data[MoodiaryKVs.tagOrder.name], tagOrder);
    await tester.tap(find.byKey(const ValueKey('tag-sort-save')));
    await tester.pumpAndSettle();
    expect(kv.data[MoodiaryKVs.tagOrder.name], [
      '生活',
      '生活/旅行记',
      '生活/旅行',
      '生活/旅行/海边',
      '工作',
    ]);
    expect(
      tester.getTopLeft(row('生活')).dy,
      lessThan(tester.getTopLeft(row('工作')).dy),
    );
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
  });

  testWidgets('leaving sort without saving preserves the manager order', (
    tester,
  ) async {
    await pumpPage(tester);
    await reorderRoots(tester);
    await tester.tap(find.byKey(const ValueKey('tag-sort-back')));
    await tester.pumpAndSettle();
    expect(kv.data[MoodiaryKVs.tagOrder.name], tagOrder);
    expect(
      tester.getTopLeft(row('工作')).dy,
      lessThan(tester.getTopLeft(row('生活')).dy),
    );
  });

  testWidgets('rename migrates subtree metadata and the active diary filter', (
    tester,
  ) async {
    await pumpPage(tester);
    selectTravelDiary();
    await openAction(tester, '重命名标签');
    await tester.enterText(renameField, '生活/出游');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expectRenamedState();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete requires confirmation and clears only its subtree', (
    tester,
  ) async {
    await pumpPage(tester);
    selectTravelDiary();
    await openAction(tester, '删除标签');
    expect(find.byType(MSheetScaffold<bool>), findsOneWidget);
    expect(repository.deletedTags, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(kv.data[MoodiaryKVs.tagOrder.name], tagOrder);
    expect(container.read(diarySelectionProvider), {'selected-diary'});
    expect(kv.data[MoodiaryKVs.defaultTag.name], '生活/旅行/海边');

    await openAction(tester, '删除标签');
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expectDeletedState();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed rename retains input and state until a successful retry',
    (tester) async {
      repository.renameFails = true;
      await pumpPage(tester);
      selectTravelDiary();
      await openAction(tester, '重命名标签');
      await tester.enterText(renameField, '生活/出游');
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(find.text('标签更新失败'), findsOneWidget);
      expect(tester.widget<TextField>(renameField).controller!.text, '生活/出游');
      expect(kv.data[MoodiaryKVs.tagOrder.name], tagOrder);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
      expect(container.read(diarySelectionProvider), {'selected-diary'});
      expect(kv.data[MoodiaryKVs.defaultTag.name], '生活/旅行/海边');

      repository.renameFails = false;
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(repository.renamedTags, [('生活/旅行', '生活/出游'), ('生活/旅行', '生活/出游')]);
      expect(find.byType(BottomSheet), findsNothing);
      expect(kv.data[MoodiaryKVs.defaultTag.name], '生活/出游/海边');
      expect(
        container.read(homeDiaryFilterProvider),
        const DiaryFilter.tag('生活/出游/海边'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('submitted rename completes metadata after both routes close', (
    tester,
  ) async {
    final pending = Completer<int>();
    repository.pendingRename = pending;
    await pumpPage(tester);
    selectTravelDiary();
    await openAction(tester, '重命名标签');
    await tester.enterText(renameField, '生活/出游');
    await tester.tap(find.text('确认'));
    await tester.pump();
    expect(repository.renamedTags, [('生活/旅行', '生活/出游')]);

    final sheet = tester.getRect(find.byType(MSheetScaffold<void>));
    await tester.dragFrom(
      Offset(sheet.center.dx, sheet.top - 24),
      const Offset(0, 600),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BottomSheet), findsNothing);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TagManagerPage), findsNothing);

    pending.complete(1);
    await tester.pumpAndSettle();
    expectRenamedState();
    expect(find.byKey(const ValueKey('open-tag-manager')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed delete completes metadata after the manager closes', (
    tester,
  ) async {
    final pending = Completer<int>();
    repository.pendingDelete = pending;
    await pumpPage(tester);
    selectTravelDiary();
    await openAction(tester, '删除标签');
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(repository.deletedTags, ['生活/旅行']);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(TagManagerPage), findsNothing);

    pending.complete(1);
    await tester.pumpAndSettle();
    expectDeletedState();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty tags show an empty state and disable sorting', (
    tester,
  ) async {
    await pumpPage(tester, loadTags: () async => []);
    expect(find.text('暂无标签'), findsOneWidget);
    expect(find.text('默认标签'), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    expect(kv.data.containsKey(MoodiaryKVs.defaultTag.name), isFalse);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('tag-manager-sort')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty tags still allow clearing a saved default tag', (
    tester,
  ) async {
    kv.data[MoodiaryKVs.defaultTag.name] = '生活/旅行/海边';
    await pumpPage(tester, loadTags: () async => []);

    expect(find.text('暂无标签'), findsOneWidget);
    expect(find.text('默认标签'), findsOneWidget);
    expect(find.text('#生活/旅行/海边'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-manager-clear-default')));
    await tester.pumpAndSettle();

    expect(find.text('未设置'), findsOneWidget);
    expect(kv.data[MoodiaryKVs.defaultTag.name], '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading disables sorting and renders tags when available', (
    tester,
  ) async {
    final pending = Completer<List<String>>();
    await pumpPage(tester, loadTags: () => pending.future, settle: false);
    expect(row('生活'), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('tag-manager-sort')))
          .onPressed,
      isNull,
    );
    pending.complete(tags);
    await tester.pumpAndSettle();
    expect(row('生活'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag loading errors offer a working retry', (tester) async {
    var requests = 0;
    await pumpPage(
      tester,
      loadTags: () async {
        requests++;
        if (requests == 1) throw StateError('Cannot load tags');
        return tags;
      },
    );
    expect(find.text('标签更新失败'), findsOneWidget);
    expect(row('生活'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(row('生活'), findsOneWidget);
    expect(find.text('标签更新失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
