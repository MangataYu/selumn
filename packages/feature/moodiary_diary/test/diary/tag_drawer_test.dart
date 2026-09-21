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

Future<void> _pumpWidget(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
}

Widget wrap(Widget child, {List<String> tags = const ['生活/旅行', '阅读']}) =>
    muiTestApp(
      child,
      overrides: [
        diaryTagsProvider.overrideWith((ref) async => tags),
        tagDiaryCountsProvider.overrideWith(
          (ref) async => (
            byTag: const {'生活': 4, '生活/旅行': 3, '阅读': 4},
            total: 6,
            untagged: 1,
          ),
        ),
      ],
    );

void main() {
  late MemoryKVStorage kv;

  setUp(() {
    kv = MemoryKVStorage();
    getIt.pushNewScope(init: (gi) => gi.registerSingleton<IKVStorage>(kv));
  });

  tearDown(() => getIt.popScope());

  Future<void> toggleTag(WidgetTester tester, String path) async {
    final button = find.byKey(ValueKey('tag-expand:$path'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> toggleAllDiaries(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('all-diaries-expand'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('shows only root tags until a parent is expanded', (
    tester,
  ) async {
    await _pumpWidget(tester, wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('旅行'), findsNothing);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    expect(find.byKey(const ValueKey('tag-expand:阅读')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tag-expand:生活')),
        matching: find.byIcon(LucideIcons.chevronRight),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('all-diaries-expand')),
        matching: find.byIcon(LucideIcons.chevronDown),
      ),
      findsOneWidget,
    );
    expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isNull);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], isNull);
    expect(find.text('管理分类'), findsNothing);
    expect(find.text('分类'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);

    await toggleTag(tester, '生活');
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tag-expand:生活')),
        matching: find.byIcon(LucideIcons.chevronDown),
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('旅行')).dx,
      greaterThan(tester.getTopLeft(find.text('生活')).dx),
    );
  });

  testWidgets('collapsing a parent preserves expanded descendants', (
    tester,
  ) async {
    await _pumpWidget(
      tester,
      wrap(const TagDrawer(), tags: ['生活/旅行/海边', '生活/摄影', '阅读/小说']),
    );
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsNothing);
    expect(find.text('海边'), findsNothing);

    await toggleTag(tester, '生活');
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('摄影'), findsOneWidget);
    expect(find.text('海边'), findsNothing);
    expect(find.text('小说'), findsNothing);

    await toggleTag(tester, '生活/旅行');
    expect(find.text('海边'), findsOneWidget);

    await toggleTag(tester, '生活');
    expect(find.text('旅行'), findsNothing);
    expect(find.text('摄影'), findsNothing);
    expect(find.text('海边'), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活/旅行']);

    await toggleTag(tester, '生活');
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('海边'), findsOneWidget);
    expect(find.text('小说'), findsNothing);

    await toggleTag(tester, '生活/旅行');
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('海边'), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);
  });

  testWidgets('restores expansion after closing and recreating the drawer', (
    tester,
  ) async {
    final key = GlobalKey<ScaffoldState>();
    await _pumpWidget(
      tester,
      wrap(Scaffold(key: key, drawer: const TagDrawer())),
    );
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await toggleTag(tester, '生活');

    key.currentState!.closeDrawer();
    await tester.pumpAndSettle();
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsOneWidget);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);

    await _pumpWidget(tester, const SizedBox.shrink());
    await _pumpWidget(tester, wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsOneWidget);

    await toggleTag(tester, '生活');
    await _pumpWidget(tester, const SizedBox.shrink());
    await _pumpWidget(tester, wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], isEmpty);
  });

  testWidgets('untagged count is independent of overlapping tag totals', (
    tester,
  ) async {
    await _pumpWidget(tester, wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('无标签'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets(
    'all diaries toggles filters without changing tags or selection',
    (tester) async {
      kv.data[MoodiaryKVs.expandedTagPaths.name] = ['生活', '生活/旅行'];
      final key = GlobalKey<ScaffoldState>();
      var filterPicks = 0;
      await _pumpWidget(
        tester,
        wrap(
          Scaffold(
            key: key,
            drawer: TagDrawer(onFilterSelected: () => filterPicks++),
          ),
          tags: ['生活/旅行/海边', '工作/项目', '阅读/小说', '运动/跑步'],
        ),
      );
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagDrawer)),
      );
      container
          .read(homeDiaryFilterProvider.notifier)
          .select(const DiaryFilter.tag('生活/旅行'));
      container.read(diarySelectionProvider.notifier).enter('selected-diary');
      await tester.pumpAndSettle();
      final rootLeft = tester.getTopLeft(find.text('生活')).dx;
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('海边'), findsOneWidget);

      await toggleAllDiaries(tester);
      for (final path in ['生活', '生活/旅行', '生活/旅行/海边', '工作', '阅读', '运动']) {
        expect(find.byKey(ValueKey('tag-row:$path')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('all-diaries-row')), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      for (final filter in ['untagged', 'images', 'links', 'audio']) {
        expect(find.byKey(ValueKey('filter-$filter')), findsNothing);
      }
      expect(find.byKey(const ValueKey('tag-search-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-sort-button')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('all-diaries-expand')),
          matching: find.byIcon(LucideIcons.chevronRight),
        ),
        findsOneWidget,
      );
      expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isFalse);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活', '生活/旅行']);
      expect(key.currentState!.isDrawerOpen, isTrue);
      expect(filterPicks, 0);
      expect(
        container.read(homeDiaryFilterProvider),
        const DiaryFilter.tag('生活/旅行'),
      );
      expect(container.read(diarySelectionProvider), {'selected-diary'});

      await toggleAllDiaries(tester);
      expect(find.text('生活'), findsOneWidget);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('海边'), findsOneWidget);
      expect(find.text('工作'), findsOneWidget);
      expect(find.text('项目'), findsNothing);
      for (final filter in ['untagged', 'images', 'links', 'audio']) {
        expect(find.byKey(ValueKey('filter-$filter')), findsOneWidget);
      }
      expect(tester.getTopLeft(find.text('生活')).dx, closeTo(rootLeft, 0.01));
      expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isTrue);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活', '生活/旅行']);
      expect(key.currentState!.isDrawerOpen, isTrue);
      expect(filterPicks, 0);
      expect(
        container.read(homeDiaryFilterProvider),
        const DiaryFilter.tag('生活/旅行'),
      );
      expect(container.read(diarySelectionProvider), {'selected-diary'});
    },
  );

  testWidgets('restores filter expansion when reopening or recreating', (
    tester,
  ) async {
    kv.data[MoodiaryKVs.expandedTagPaths.name] = ['生活'];
    final key = GlobalKey<ScaffoldState>();
    await _pumpWidget(
      tester,
      wrap(Scaffold(key: key, drawer: const TagDrawer())),
    );
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    await toggleAllDiaries(tester);

    key.currentState!.closeDrawer();
    await tester.pumpAndSettle();
    key.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-untagged')), findsNothing);
    expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isFalse);

    await _pumpWidget(tester, const SizedBox.shrink());
    await _pumpWidget(tester, wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-untagged')), findsNothing);
    expect(find.byKey(const ValueKey('all-diaries-expand')), findsOneWidget);

    await toggleAllDiaries(tester);
    await _pumpWidget(tester, const SizedBox.shrink());
    await _pumpWidget(tester, wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    for (final filter in ['untagged', 'images', 'links', 'audio']) {
      expect(find.byKey(ValueKey('filter-$filter')), findsOneWidget);
    }
    expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isTrue);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);
  });

  testWidgets('all diaries still expands filters when there are no tags', (
    tester,
  ) async {
    await _pumpWidget(tester, wrap(const TagDrawer(), tags: []));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('all-diaries-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('all-diaries-expand')), findsOneWidget);
    expect(find.text('日记'), findsOneWidget);
    expect(find.text('无标签'), findsOneWidget);
    await toggleAllDiaries(tester);
    expect(find.byKey(const ValueKey('filter-untagged')), findsNothing);
    expect(find.byKey(const ValueKey('all-diaries-expand')), findsOneWidget);
    await toggleAllDiaries(tester);
    expect(find.byKey(const ValueKey('filter-untagged')), findsOneWidget);
  });

  testWidgets(
    'picking tags and filters clears selection and closes the drawer',
    (tester) async {
      final key = GlobalKey<ScaffoldState>();
      final picked = <DiaryFilter>[];
      late ProviderContainer container;
      await _pumpWidget(
        tester,
        wrap(
          Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return Scaffold(
                key: key,
                drawer: TagDrawer(
                  onFilterSelected: () {
                    picked.add(container.read(homeDiaryFilterProvider));
                    expect(container.read(diarySelectionProvider), isEmpty);
                  },
                ),
              );
            },
          ),
        ),
      );
      for (final (label, expected) in const [
        ('旅行', DiaryFilter.tag('生活/旅行')),
        ('生活', DiaryFilter.tag('生活')),
        ('无标签', DiaryFilter.untagged()),
        ('有图片', DiaryFilter.images()),
        ('有链接', DiaryFilter.links()),
        ('有语音', DiaryFilter.audio()),
        ('日记', DiaryFilter.all()),
      ]) {
        container.read(diarySelectionProvider.notifier).enter('some-diary');
        key.currentState!.openDrawer();
        await tester.pumpAndSettle();
        if (label == '旅行') {
          await toggleTag(tester, '生活');
          expect(key.currentState!.isDrawerOpen, isTrue);
          expect(picked, isEmpty);
          expect(
            container.read(homeDiaryFilterProvider),
            const DiaryFilter.all(),
          );
          expect(container.read(diarySelectionProvider), {'some-diary'});
        }
        if (label == '日记') {
          await toggleAllDiaries(tester);
          expect(find.text('生活'), findsOneWidget);
          expect(find.byKey(const ValueKey('filter-untagged')), findsNothing);
          expect(key.currentState!.isDrawerOpen, isTrue);
          expect(container.read(diarySelectionProvider), {'some-diary'});
        }
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(picked.last, expected);
        expect(key.currentState!.isDrawerOpen, isFalse);
        if (label == '日记') {
          expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isFalse);
        }
      }
    },
  );

  testWidgets('search finds collapsed paths and preserves expansion state', (
    tester,
  ) async {
    await _pumpWidget(
      tester,
      wrap(const TagDrawer(), tags: ['生活/旅行', '工作/项目', '阅读/小说', '运动/跑步']),
    );
    await tester.pumpAndSettle();
    await toggleTag(tester, '生活');
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('项目'), findsNothing);
    expect(find.byType(SearchBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-search-toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SearchBar));
    await tester.enterText(find.byType(SearchBar), '工作/项');
    await tester.pumpAndSettle();
    expect(find.text('工作/项目'), findsOneWidget);
    expect(find.text('旅行'), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);

    await tester.enterText(find.byType(SearchBar), '');
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('项目'), findsNothing);
    expect(find.text('工作/项目'), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);

    await tester.enterText(find.byType(SearchBar), '工作/项');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsNothing);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('工作/项目'), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);

    await tester.tap(find.byKey(const ValueKey('tag-search-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    expect(find.text('旅行'), findsOneWidget);
  });

  testWidgets(
    'tag search after reopening tags preserves independent filter expansion',
    (tester) async {
      kv.data[MoodiaryKVs.tagTreeExpanded.name] = false;
      kv.data[MoodiaryKVs.diaryFiltersExpanded.name] = false;
      kv.data[MoodiaryKVs.expandedTagPaths.name] = ['生活'];
      await _pumpWidget(
        tester,
        wrap(const TagDrawer(), tags: ['生活/旅行', '工作/项目', '阅读/小说', '运动/跑步']),
      );
      await tester.pumpAndSettle();
      expect(find.text('生活'), findsNothing);
      expect(find.byKey(const ValueKey('tag-search-toggle')), findsNothing);
      await tester.tap(find.text('标签'));
      await tester.pumpAndSettle();
      expect(kv.data[MoodiaryKVs.tagTreeExpanded.name], isTrue);
      expect(find.text('生活'), findsOneWidget);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-untagged')), findsNothing);
      expect(find.byKey(const ValueKey('tag-search-toggle')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tag-search-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('生活'), findsOneWidget);
      await tester.enterText(find.byType(SearchBar), '工作/项');
      await tester.pumpAndSettle();
      expect(find.text('工作/项目'), findsOneWidget);
      expect(find.byKey(const ValueKey('all-diaries-row')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-untagged')), findsNothing);
      expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isFalse);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);

      await tester.enterText(find.byType(SearchBar), '');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-diaries-row')), findsOneWidget);
      expect(find.text('生活'), findsOneWidget);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('工作/项目'), findsNothing);
      expect(find.byKey(const ValueKey('filter-untagged')), findsNothing);

      await tester.enterText(find.byType(SearchBar), '生活');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-row:生活')), findsOneWidget);
      expect(find.text('生活/旅行'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tag-search-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(SearchBar), findsNothing);
      expect(find.text('生活'), findsOneWidget);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('生活/旅行'), findsNothing);
      expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isFalse);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);

      await toggleAllDiaries(tester);
      expect(find.text('生活'), findsOneWidget);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('工作'), findsOneWidget);
      expect(find.text('项目'), findsNothing);
      for (final filter in ['untagged', 'images', 'links', 'audio']) {
        expect(find.byKey(ValueKey('filter-$filter')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('tag-search-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'no-matching-tag');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-diaries-row')), findsOneWidget);
      for (final filter in ['untagged', 'images', 'links', 'audio']) {
        expect(find.byKey(ValueKey('filter-$filter')), findsOneWidget);
      }
      expect(kv.data[MoodiaryKVs.diaryFiltersExpanded.name], isTrue);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['生活']);
    },
  );

  testWidgets('tag management is available from a long press', (tester) async {
    await _pumpWidget(tester, wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('生活'));
    await tester.pumpAndSettle();
    expect(find.text('重命名标签'), findsOneWidget);
    expect(find.text('删除标签'), findsOneWidget);
  });
}
