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

const _tags = ['生活/旅行/海边', '生活/摄影', '工作/项目', '阅读/小说'];

Widget _wrap(Widget child, {List<String> tags = _tags}) => muiTestApp(
  child,
  overrides: [
    diaryTagsProvider.overrideWith((ref) async => tags),
    tagDiaryCountsProvider.overrideWith(
      (ref) async => (byTag: const <String, int>{}, total: 6, untagged: 1),
    ),
  ],
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder get _menuLabel => find.descendant(
  of: find.byKey(const ValueKey('tags-row')),
  matching: find.text('标签'),
);

Finder get _menuArrow => find.byKey(const ValueKey('tags-expand'));

void main() {
  late MemoryKVStorage kv;

  setUp(() {
    kv = MemoryKVStorage();
    getIt.pushNewScope(init: (gi) => gi.registerSingleton<IKVStorage>(kv));
  });

  tearDown(() => getIt.popScope());

  Future<void> pumpDrawer(WidgetTester tester, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(child);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tag menu label and arrow toggle the whole section without selecting',
    (tester) async {
      kv.data[MoodiaryKVs.expandedTagPaths.name] = ['生活', '生活/旅行'];
      kv.data[MoodiaryKVs.tagOrder.name] = ['阅读', '生活', '工作'];
      kv.data[MoodiaryKVs.diaryFiltersExpanded.name] = false;
      final scaffoldKey = GlobalKey<ScaffoldState>();
      var filterPicks = 0;
      await pumpDrawer(
        tester,
        _wrap(
          Scaffold(
            key: scaffoldKey,
            drawer: TagDrawer(onFilterSelected: () => filterPicks++),
          ),
        ),
      );
      scaffoldKey.currentState!.openDrawer();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagDrawer)),
      );
      container
          .read(homeDiaryFilterProvider.notifier)
          .select(const DiaryFilter.tag('生活/旅行'));
      container.read(diarySelectionProvider.notifier).enter('selected-diary');
      await tester.pumpAndSettle();
      expect(_menuLabel, findsOneWidget);
      expect(find.text('全部标签'), findsNothing);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('海边'), findsOneWidget);
      expect(find.text('项目'), findsNothing);

      await _tap(tester, _menuLabel);
      expect(kv.data[MoodiaryKVs.tagTreeExpanded.name], isFalse);
      for (final path in ['生活', '生活/旅行', '生活/旅行/海边', '工作', '阅读']) {
        expect(find.byKey(ValueKey('tag-row:$path')), findsNothing);
      }
      expect(find.byKey(const ValueKey('tag-sort-button')), findsNothing);
      expect(find.byKey(const ValueKey('tag-search-toggle')), findsNothing);
      expect(find.byKey(const ValueKey('all-diaries-row')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-untagged')), findsNothing);
      expect(
        find.descendant(
          of: _menuArrow,
          matching: find.byIcon(LucideIcons.chevronRight),
        ),
        findsOneWidget,
      );

      await _tap(tester, _menuArrow);
      expect(kv.data[MoodiaryKVs.tagTreeExpanded.name], isTrue);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('海边'), findsOneWidget);
      expect(find.text('项目'), findsNothing);
      expect(find.text('小说'), findsNothing);
      expect(find.byKey(const ValueKey('tag-sort-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-search-toggle')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('tag-row:阅读'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('tag-row:生活'))).dy,
        ),
      );
      expect(
        find.descendant(
          of: _menuArrow,
          matching: find.byIcon(LucideIcons.chevronDown),
        ),
        findsOneWidget,
      );
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活', '生活/旅行']);
      expect(kv.data[MoodiaryKVs.tagOrder.name], ['阅读', '生活', '工作']);
      expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isFalse);
      expect(
        container.read(homeDiaryFilterProvider),
        const DiaryFilter.tag('生活/旅行'),
      );
      expect(container.read(diarySelectionProvider), {'selected-diary'});
      expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);
      expect(filterPicks, 0);
    },
  );

  testWidgets('tag menu expansion survives closing and recreating the drawer', (
    tester,
  ) async {
    kv.data[MoodiaryKVs.expandedTagPaths.name] = ['生活', '生活/旅行'];
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await pumpDrawer(
      tester,
      _wrap(Scaffold(key: scaffoldKey, drawer: const TagDrawer())),
    );
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await _tap(tester, _menuArrow);

    scaffoldKey.currentState!.closeDrawer();
    await tester.pumpAndSettle();
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(_menuLabel, findsOneWidget);
    expect(find.text('生活'), findsNothing);
    expect(find.byKey(const ValueKey('tag-sort-button')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(kv.data[MoodiaryKVs.tagTreeExpanded.name], isFalse);
    expect(find.text('生活'), findsNothing);
    await _tap(tester, _menuLabel);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(kv.data[MoodiaryKVs.tagTreeExpanded.name], isTrue);
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('海边'), findsOneWidget);
    expect(find.text('项目'), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活', '生活/旅行']);
  });

  testWidgets(
    'collapsing during search clears the query and restores the tree',
    (tester) async {
      kv.data[MoodiaryKVs.expandedTagPaths.name] = ['生活', '生活/旅行'];
      await pumpDrawer(tester, _wrap(const TagDrawer()));
      await _tap(tester, find.byKey(const ValueKey('tag-search-toggle')));
      await tester.enterText(find.byType(SearchBar), '工作/项');
      await tester.pumpAndSettle();
      expect(find.text('工作/项目'), findsOneWidget);
      expect(find.text('旅行'), findsNothing);

      await _tap(tester, _menuLabel);
      expect(find.byType(SearchBar), findsNothing);
      expect(find.text('工作/项目'), findsNothing);
      expect(find.byKey(const ValueKey('tag-search-toggle')), findsNothing);
      await _tap(tester, _menuArrow);
      expect(find.byType(SearchBar), findsNothing);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('海边'), findsOneWidget);
      expect(find.text('工作'), findsOneWidget);
      expect(find.text('项目'), findsNothing);
      expect(find.text('工作/项目'), findsNothing);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活', '生活/旅行']);

      await _tap(tester, find.byKey(const ValueKey('tag-search-toggle')));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      expect(find.text('海边'), findsOneWidget);
      expect(find.text('项目'), findsNothing);
    },
  );

  testWidgets('empty tag menu remains available and independent of filters', (
    tester,
  ) async {
    await pumpDrawer(tester, _wrap(const TagDrawer(), tags: []));
    expect(_menuLabel, findsOneWidget);
    expect(_menuArrow, findsOneWidget);
    final sortButton = find.byKey(const ValueKey('tag-sort-button'));
    expect(tester.widget<IconButton>(sortButton).onPressed, isNull);

    await _tap(tester, _menuLabel);
    expect(_menuLabel, findsOneWidget);
    expect(kv.data[MoodiaryKVs.tagTreeExpanded.name], isFalse);
    expect(sortButton, findsNothing);
    for (final filter in ['untagged', 'images', 'links', 'audio']) {
      expect(find.byKey(ValueKey('filter-$filter')), findsOneWidget);
    }

    await _tap(tester, _menuArrow);
    expect(kv.data[MoodiaryKVs.tagTreeExpanded.name], isTrue);
    expect(tester.widget<IconButton>(sortButton).onPressed, isNull);
    expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isNull);
  });
}
