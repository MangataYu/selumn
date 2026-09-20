import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';
import 'package:moodiary_diary/src/application/diary_selection.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_drawer.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

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
  testWidgets('renders parent paths and counts without a category manager', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('管理分类'), findsNothing);
    expect(find.text('分类'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('旅行')).dx,
      greaterThan(tester.getTopLeft(find.text('生活')).dx),
    );
  });

  testWidgets('untagged count is independent of overlapping tag totals', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('无标签'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('picking a tag clears selection and closes the drawer', (
    tester,
  ) async {
    final key = GlobalKey<ScaffoldState>();
    final picked = <DiaryFilter>[];
    late ProviderContainer container;
    await tester.pumpWidget(
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
      ('全部日记', DiaryFilter.all()),
    ]) {
      container.read(diarySelectionProvider.notifier).enter('some-diary');
      key.currentState!.openDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(picked.last, expected);
      expect(key.currentState!.isDrawerOpen, isFalse);
    }
  });

  testWidgets('search finds full paths and hides unmatched tags', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const TagDrawer(),
        tags: ['生活/旅行', for (var i = 0; i < 8; i++) '标签$i'],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), '生活/旅');
    await tester.pumpAndSettle();
    expect(find.text('生活/旅行'), findsOneWidget);
    expect(find.text('标签0'), findsNothing);
  });

  testWidgets('tag management is available from a long press', (tester) async {
    await tester.pumpWidget(wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('生活'));
    await tester.pumpAndSettle();
    expect(find.text('重命名标签'), findsOneWidget);
    expect(find.text('删除标签'), findsOneWidget);
  });
}
