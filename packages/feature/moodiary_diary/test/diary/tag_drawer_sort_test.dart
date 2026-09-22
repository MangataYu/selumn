import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/presentation/tag/tag_manager_page.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_drawer.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

void main() {
  late MemoryKVStorage kv;

  setUp(() {
    kv = MemoryKVStorage();
    getIt.pushNewScope(init: (gi) => gi.registerSingleton<IKVStorage>(kv));
  });
  tearDown(() => getIt.popScope());

  Future<GlobalKey<ScaffoldState>> pumpDrawer(
    WidgetTester tester, {
    List<String> tags = const ['a/child', 'b', 'c'],
  }) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scaffoldKey = GlobalKey<ScaffoldState>();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            key: scaffoldKey,
            drawer: const TagDrawer(),
            body: const SizedBox.shrink(),
          ),
        ),
        GoRoute(
          path: TagManagerRoute.path,
          builder: (_, _) => const TagManagerPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diaryTagsProvider.overrideWith((ref) async => tags),
          tagDiaryCountsProvider.overrideWith(
            (ref) async =>
                (byTag: const <String, int>{}, total: 0, untagged: 0),
          ),
        ],
        child: TranslationProvider(
          child: MaterialApp.router(
            theme: buildMuiTheme(brightness: Brightness.light),
            localizationsDelegates: const [
              ...GlobalMaterialLocalizations.delegates,
              GlobalMuiLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            locale: const Locale('zh'),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    return scaffoldKey;
  }

  List<String> visibleRoots(WidgetTester tester) {
    final roots = ['a', 'b', 'c'];
    roots.sort(
      (a, b) => tester
          .getTopLeft(find.byKey(ValueKey('tag-row:$a')))
          .dy
          .compareTo(tester.getTopLeft(find.byKey(ValueKey('tag-row:$b'))).dy),
    );
    return roots;
  }

  Future<void> openManager(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('tag-manager-button')));
    await tester.pumpAndSettle();
    expect(find.byType(TagManagerPage), findsOneWidget);
  }

  Future<void> returnToDrawer(
    WidgetTester tester,
    GlobalKey<ScaffoldState> scaffoldKey,
  ) async {
    await tester.tap(find.byKey(const ValueKey('tag-manager-back')));
    await tester.pumpAndSettle();
    expect(find.byType(TagManagerPage), findsNothing);
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'unified manager saves sorting immediately and survives drawer recreation',
    (tester) async {
      kv.data[MoodiaryKVs.expandedTagPaths.name] = ['a'];
      final scaffoldKey = await pumpDrawer(tester);
      expect(visibleRoots(tester), ['a', 'b', 'c']);
      expect(find.byTooltip(l10n.diary.tagManagerTitle), findsOneWidget);
      await openManager(tester);
      expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(0, 2);
      await tester.pumpAndSettle();
      expect(kv.data[MoodiaryKVs.tagOrder.name], ['b', 'c', 'a', 'a/child']);
      await returnToDrawer(tester, scaffoldKey);
      expect(visibleRoots(tester), ['b', 'c', 'a']);
      expect(find.byKey(const ValueKey('tag-row:a/child')), findsOneWidget);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['a']);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDrawer(tester);
      expect(visibleRoots(tester), ['b', 'c', 'a']);
    },
  );

  for (final savedOrder in <List<String>?>[
    null,
    ['c', 'a', 'a/child', 'b'],
  ]) {
    testWidgets(
      'opening and leaving manager preserves ${savedOrder == null ? 'unset' : 'saved'} order',
      (tester) async {
        if (savedOrder != null) {
          kv.data[MoodiaryKVs.tagOrder.name] = savedOrder;
        }
        final scaffoldKey = await pumpDrawer(tester);
        await openManager(tester);
        await returnToDrawer(tester, scaffoldKey);
        expect(kv.data[MoodiaryKVs.tagOrder.name], savedOrder);
        expect(
          visibleRoots(tester),
          savedOrder == null ? ['a', 'b', 'c'] : ['c', 'a', 'b'],
        );
      },
    );
  }

  testWidgets('empty drawer can still open tag management', (tester) async {
    final scaffoldKey = await pumpDrawer(tester, tags: []);
    await openManager(tester);
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
    expect(find.text(l10n.diary.tagSortEmpty), findsOneWidget);
    await returnToDrawer(tester, scaffoldKey);
    expect(kv.data[MoodiaryKVs.tagOrder.name], isNull);
  });

  testWidgets(
    'external preferences update the existing drawer and detach on disposal',
    (tester) async {
      await pumpDrawer(tester);
      final drawerState = tester.state(find.byType(TagDrawer));
      expect(visibleRoots(tester), ['a', 'b', 'c']);
      expect(find.byKey(const ValueKey('tag-row:a/child')), findsNothing);

      MoodiaryKVs.tagOrder.set(['c', 'a', 'a/child', 'b']);
      MoodiaryKVs.expandedTagPaths.set(['a']);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TagDrawer)), same(drawerState));
      expect(visibleRoots(tester), ['c', 'a', 'b']);
      expect(find.byKey(const ValueKey('tag-row:a/child')), findsOneWidget);

      MoodiaryKVs.expandedTagPaths.set([]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tag-row:a/child')), findsNothing);
      expect(visibleRoots(tester), ['c', 'a', 'b']);

      await tester.pumpWidget(const SizedBox.shrink());
      MoodiaryKVs.tagOrder.set(['b', 'a', 'a/child', 'c']);
      MoodiaryKVs.expandedTagPaths.set(['a']);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
