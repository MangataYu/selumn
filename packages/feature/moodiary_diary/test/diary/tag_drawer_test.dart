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

  testWidgets('shows only root tags until a parent is expanded', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('生活'), findsOneWidget);
    expect(find.text('旅行'), findsNothing);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    expect(find.byKey(const ValueKey('tag-expand:阅读')), findsNothing);
    expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], isNull);
    expect(find.text('管理分类'), findsNothing);
    expect(find.text('分类'), findsNothing);
    expect(find.byTooltip('设置'), findsOneWidget);

    await toggleTag(tester, '生活');
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('旅行')).dx,
      greaterThan(tester.getTopLeft(find.text('生活')).dx),
    );
  });

  testWidgets('collapsing a parent preserves expanded descendants', (
    tester,
  ) async {
    await tester.pumpWidget(
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
    await tester.pumpWidget(
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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsOneWidget);

    await toggleTag(tester, '生活');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(wrap(const TagDrawer()));
    await tester.pumpAndSettle();
    expect(find.text('旅行'), findsNothing);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], isEmpty);
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
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(picked.last, expected);
      expect(key.currentState!.isDrawerOpen, isFalse);
    }
  });

  testWidgets('search finds collapsed paths and preserves expansion state', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const TagDrawer(), tags: ['生活/旅行', '工作/项目', '阅读/小说', '运动/跑步']),
    );
    await tester.pumpAndSettle();
    await toggleTag(tester, '生活');
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('项目'), findsNothing);
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
