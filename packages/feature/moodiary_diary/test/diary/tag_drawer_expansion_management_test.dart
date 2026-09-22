import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';
import 'package:moodiary_diary/src/application/diary_selection.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_drawer.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

class _RecordingDiaryRepository extends Fake implements DiaryRepository {
  final renamedTags = <(String, String)>[];
  final deletedTags = <String>[];
  bool renameFails = false;
  Completer<int>? pendingRename;

  @override
  Future<int> renameTag(String tag, String replacement) async {
    renamedTags.add((tag, replacement));
    if (renameFails) throw StateError('Cannot rename tag');
    final pending = pendingRename;
    if (pending != null) return pending.future;
    return 1;
  }

  @override
  Future<int> deleteTag(String tag) async {
    deletedTags.add(tag);
    return 1;
  }
}

void main() {
  late MemoryKVStorage kv;
  late _RecordingDiaryRepository repository;
  const expandedPaths = ['生活', '生活/旅行', '生活/旅行/海边', '生活/旅行记'];
  const tagOrder = [
    '生活',
    '生活/旅行记',
    '生活/旅行记/夏天',
    '生活/旅行',
    '生活/旅行/海边',
    '生活/旅行/海边/日落',
  ];

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

  Future<void> openTagMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      muiTestApp(
        const TagDrawer(),
        overrides: [
          diaryTagsProvider.overrideWith(
            (ref) async => ['生活/旅行/海边/日落', '生活/旅行记/夏天'],
          ),
          tagDiaryCountsProvider.overrideWith(
            (ref) async =>
                (byTag: const <String, int>{}, total: 0, untagged: 0),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
    await tester.ensureVisible(find.text('旅行'));
    await tester.longPress(find.text('旅行'));
    await tester.pumpAndSettle();
  }

  Future<void> openTagAction(WidgetTester tester, String action) async {
    await openTagMenu(tester);
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  void expectUnchanged() {
    expect(repository.renamedTags, isEmpty);
    expect(repository.deletedTags, isEmpty);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
    expect(kv.data[MoodiaryKVs.tagOrder.name], tagOrder);
    expect(kv.data.containsKey(MoodiaryKVs.defaultTag.name), isFalse);
  }

  testWidgets(
    'long-press actions open in a bottom sheet and cancel does not write',
    (tester) async {
      await openTagMenu(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(MSheetScaffold<String>), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('#生活/旅行'), findsOneWidget);
      expect(find.byType(MSheetOptionTile<String>), findsNWidgets(2));
      expect(find.text('设为默认标签'), findsOneWidget);
      expect(find.text('重命名标签'), findsOneWidget);
      expect(find.byType(MDangerRow), findsOneWidget);
      expect(tester.getRect(find.byType(MSheetScaffold<String>)).bottom, 844);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expectUnchanged();
    },
  );

  testWidgets(
    'rename opens a field in a bottom sheet and cancel discards edits',
    (tester) async {
      await openTagAction(tester, '重命名标签');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(MSheetScaffold<void>), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(MField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '生活/旅行',
      );

      await tester.enterText(find.byType(TextField), '生活/出游');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expectUnchanged();
    },
  );

  testWidgets(
    'delete confirmation is a destructive bottom sheet and can cancel',
    (tester) async {
      await openTagAction(tester, '删除标签');
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(MSheetScaffold<bool>), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('移除所有日记中的「生活/旅行」及其子标签，正文保留标签名称。'), findsOneWidget);
      final actions = tester
          .widget<MSheetScaffold<bool>>(find.byType(MSheetScaffold<bool>))
          .actions;
      expect(
        actions.singleWhere((action) => action.label == '删除').isDestructive,
        isTrue,
      );
      expectUnchanged();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expectUnchanged();
    },
  );

  testWidgets('invalid rename remains open without writing', (tester) async {
    await openTagAction(tester, '重命名标签');
    for (final value in ['', '生活/旅行 计划']) {
      await tester.enterText(find.byType(TextField), value);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(find.text('标签路径无效'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expectUnchanged();
    }
  });

  testWidgets('failed rename preserves the draft and can be retried', (
    tester,
  ) async {
    repository.renameFails = true;
    await openTagAction(tester, '重命名标签');
    await tester.enterText(find.byType(TextField), '生活/出游');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.text('标签更新失败'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '生活/出游',
    );
    expect(repository.renamedTags, [('生活/旅行', '生活/出游')]);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
    expect(kv.data[MoodiaryKVs.tagOrder.name], tagOrder);

    repository.renameFails = false;
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(repository.renamedTags, [('生活/旅行', '生活/出游'), ('生活/旅行', '生活/出游')]);
    expect(find.byType(BottomSheet), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], contains('生活/出游'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename stays above the keyboard without overflow', (
    tester,
  ) async {
    await openTagAction(tester, '重命名标签');
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(MSheetScaffold<void>)).bottom, 484);
    expect(tester.getRect(find.text('确认')).bottom, lessThanOrEqualTo(484));
    expect(
      tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(484),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending rename submits once and applies state after sheet dismissal',
    (tester) async {
      final pending = Completer<int>();
      repository.pendingRename = pending;
      await openTagAction(tester, '重命名标签');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagDrawer)),
      );
      container
          .read(homeDiaryFilterProvider.notifier)
          .select(const DiaryFilter.tag('生活/旅行/海边'));
      container.read(diarySelectionProvider.notifier).enter('selected-diary');
      await tester.enterText(find.byType(TextField), '生活/出游');
      final confirm = find.byType(MActionButton<void>).last;
      await tester.tap(confirm);
      await tester.pump();
      expect(tester.widget<MActionButton<void>>(confirm).enabled, isFalse);
      await tester.tap(confirm);
      await tester.pump();
      expect(repository.renamedTags, [('生活/旅行', '生活/出游')]);

      final sheet = tester.getRect(find.byType(MSheetScaffold<void>));
      await tester.dragFrom(
        Offset(sheet.center.dx, sheet.top - 24),
        const Offset(0, 600),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(BottomSheet), findsNothing);
      pending.complete(1);
      await tester.pumpAndSettle();

      expect(
        kv.data[MoodiaryKVs.expandedTagPaths.name],
        unorderedEquals(['生活', '生活/出游', '生活/出游/海边', '生活/旅行记']),
      );
      expect(kv.data[MoodiaryKVs.tagOrder.name], [
        '生活',
        '生活/旅行记',
        '生活/旅行记/夏天',
        '生活/出游',
        '生活/出游/海边',
        '生活/出游/海边/日落',
      ]);
      expect(
        container.read(homeDiaryFilterProvider),
        const DiaryFilter.tag('生活/出游/海边'),
      );
      expect(container.read(diarySelectionProvider), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renaming migrates expansion for the whole matching subtree', (
    tester,
  ) async {
    await openTagAction(tester, '重命名标签');
    await tester.enterText(find.byType(TextField), '生活/出游');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(repository.renamedTags, [('生活/旅行', '生活/出游')]);
    expect(repository.deletedTags, isEmpty);
    expect(
      kv.data[MoodiaryKVs.expandedTagPaths.name],
      unorderedEquals(['生活', '生活/出游', '生活/出游/海边', '生活/旅行记']),
    );
    expect(kv.data[MoodiaryKVs.tagOrder.name], [
      '生活',
      '生活/旅行记',
      '生活/旅行记/夏天',
      '生活/出游',
      '生活/出游/海边',
      '生活/出游/海边/日落',
    ]);
  });

  testWidgets('deleting removes only expansion under the matching prefix', (
    tester,
  ) async {
    await openTagAction(tester, '删除标签');
    expect(repository.deletedTags, isEmpty);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repository.deletedTags, ['生活/旅行']);
    expect(repository.renamedTags, isEmpty);
    expect(
      kv.data[MoodiaryKVs.expandedTagPaths.name],
      unorderedEquals(['生活', '生活/旅行记']),
    );
    expect(kv.data[MoodiaryKVs.tagOrder.name], ['生活', '生活/旅行记', '生活/旅行记/夏天']);
  });
}
