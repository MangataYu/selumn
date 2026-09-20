import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';
import 'package:moodiary_diary/src/application/diary_selection.dart';
import 'package:moodiary_diary/src/presentation/widget/category_drawer.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

final _mui = buildMuiTheme(brightness: Brightness.light);

Category cat(String id, String name) =>
    Category(id: id, categoryName: name, lastModified: DateTime(2026));

Widget wrap({
  required List<Category> categories,
  required Map<String, int> byCategory,
  required int total,
  CategoryDrawer drawer = const CategoryDrawer(),
}) => muiTestApp(
  drawer,
  overrides: [
    orderedCategoriesProvider.overrideWithValue(.data(categories)),
    categoryDiaryCountsProvider.overrideWith(
      (ref) async => (byCategory: byCategory, total: total),
    ),
  ],
);

void main() {
  setUp(() => getIt.registerSingleton(SyncPendingTracker()));
  tearDown(getIt.reset);

  final three = [cat('tr', '旅行'), cat('dy', '日常'), cat('rd', '阅读')];

  testWidgets('lists every category with its count', (t) async {
    await t.pumpWidget(
      wrap(
        categories: three,
        byCategory: const {'tr': 2, 'dy': 4, 'rd': 1},
        total: 8,
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('日常'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('uncategorized count is total minus the categorised ones', (
    t,
  ) async {
    await t.pumpWidget(
      wrap(
        categories: three,
        byCategory: const {'tr': 2, 'dy': 4, 'rd': 1},
        total: 8,
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('未分类'), findsNothing);
    expect(find.text('无分类'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('never shows a negative uncategorized count', (t) async {
    await t.pumpWidget(
      wrap(categories: three, byCategory: const {'tr': 9}, total: 2),
    );
    await t.pumpAndSettle();
    expect(find.text('-7'), findsNothing);
  });

  testWidgets('filter picks notify after updating state and close the drawer', (
    t,
  ) async {
    final key = GlobalKey<ScaffoldState>();
    late ProviderContainer container;
    final selectedFilters = <DiaryFilter>[];
    final selectionsAtCallback = <Set<String>>[];
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          orderedCategoriesProvider.overrideWithValue(.data(three)),
          categoryDiaryCountsProvider.overrideWith(
            (ref) async => (byCategory: const {'tr': 2}, total: 8),
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return TranslationProvider(
              child: MuiTheme(
                data: _mui,
                child: MaterialApp(
                  localizationsDelegates: const [
                    ...GlobalMaterialLocalizations.delegates,
                    GlobalMuiLocalizations.delegate,
                  ],
                  supportedLocales: AppLocaleUtils.supportedLocales,
                  locale: const Locale('zh'),
                  home: Scaffold(
                    key: key,
                    drawer: CategoryDrawer(
                      isDiarySelected: false,
                      onFilterSelected: () {
                        selectedFilters.add(
                          container.read(homeDiaryFilterProvider),
                        );
                        selectionsAtCallback.add(
                          container.read(diarySelectionProvider),
                        );
                      },
                    ),
                    body: const SizedBox.expand(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(container.read(homeDiaryFilterProvider).isAll, isTrue);

    const picks = [
      ('旅行', DiaryFilter.category('tr')),
      ('全部日记', DiaryFilter.all()),
      ('无分类', DiaryFilter.uncategorized()),
    ];
    for (final (label, expectedFilter) in picks) {
      container.read(diarySelectionProvider.notifier).enter('some-diary-id');
      key.currentState!.openDrawer();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text(label), 200);
      await t.tap(find.text(label));
      await t.pumpAndSettle();

      expect(container.read(homeDiaryFilterProvider), expectedFilter);
      expect(container.read(diarySelectionProvider), isEmpty);
      expect(key.currentState!.isDrawerOpen, isFalse);
    }
    expect(selectedFilters, picks.map((pick) => pick.$2).toList());
    expect(selectionsAtCallback, everyElement(isEmpty));
  });

  testWidgets('picking a category drops the pending multi-selection', (
    t,
  ) async {
    final key = GlobalKey<ScaffoldState>();
    late ProviderContainer container;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          orderedCategoriesProvider.overrideWithValue(.data(three)),
          categoryDiaryCountsProvider.overrideWith(
            (ref) async => (byCategory: const {'tr': 2}, total: 8),
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return TranslationProvider(
              child: MuiTheme(
                data: _mui,
                child: MaterialApp(
                  localizationsDelegates: const [
                    ...GlobalMaterialLocalizations.delegates,
                    GlobalMuiLocalizations.delegate,
                  ],
                  supportedLocales: AppLocaleUtils.supportedLocales,
                  locale: const Locale('zh'),
                  home: Scaffold(
                    key: key,
                    drawer: const CategoryDrawer(),
                    body: const SizedBox.expand(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    container.read(diarySelectionProvider.notifier).enter('some-diary-id');
    expect(container.read(diarySelectionProvider), isNotEmpty);

    key.currentState!.openDrawer();
    await t.pumpAndSettle();
    await t.tap(find.text('旅行'));
    await t.pumpAndSettle();

    expect(container.read(diarySelectionProvider), isEmpty);
  });

  testWidgets('counts stay blank until the query lands', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          orderedCategoriesProvider.overrideWithValue(.data(three)),
          categoryDiaryCountsProvider.overrideWith(
            (ref) =>
                Completer<({Map<String, int> byCategory, int total})>().future,
          ),
        ],
        child: TranslationProvider(
          child: MuiTheme(
            data: _mui,
            child: MaterialApp(
              localizationsDelegates: const [
                ...GlobalMaterialLocalizations.delegates,
                GlobalMuiLocalizations.delegate,
              ],
              supportedLocales: AppLocaleUtils.supportedLocales,
              locale: const Locale('zh'),
              home: const Scaffold(body: CategoryDrawer()),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    expect(find.text('旅行'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the manage entry is always reachable', (t) async {
    await t.pumpWidget(
      wrap(
        categories: [for (var i = 0; i < 30; i++) cat('c$i', '分类$i')],
        byCategory: const {},
        total: 0,
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('管理分类'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('管理分类').hitTestable(), findsOneWidget);
  });

  testWidgets('injected navigation is shown below the header', (t) async {
    await t.pumpWidget(
      wrap(
        categories: three,
        byCategory: const {},
        total: 0,
        drawer: const CategoryDrawer(
          navigation: Column(
            children: [
              ListTile(title: Text('智能助手')),
              ListTile(title: Text('我的')),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('智能助手').hitTestable(), findsOneWidget);
    expect(find.text('我的').hitTestable(), findsOneWidget);
    expect(
      t.getTopLeft(find.text('智能助手')).dy,
      greaterThan(t.getBottomLeft(find.text('Selume')).dy),
    );
    expect(
      t.getBottomLeft(find.text('我的')).dy,
      lessThan(t.getTopLeft(find.text('分类')).dy),
    );
  });

  testWidgets('category highlights are cleared outside the diary page', (
    t,
  ) async {
    for (final isDiarySelected in [true, false]) {
      await t.pumpWidget(
        wrap(
          categories: three,
          byCategory: const {},
          total: 0,
          drawer: CategoryDrawer(isDiarySelected: isDiarySelected),
        ),
      );
      await t.pumpAndSettle();

      final container = ProviderScope.containerOf(
        t.element(find.byType(CategoryDrawer)),
      );
      for (final filter in const [
        DiaryFilter.all(),
        DiaryFilter.category('tr'),
        DiaryFilter.uncategorized(),
      ]) {
        container.read(homeDiaryFilterProvider.notifier).select(filter);
        await t.pumpAndSettle();

        final selectedTiles = find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        );
        expect(selectedTiles, isDiarySelected ? findsOneWidget : findsNothing);
      }
    }
  });

  testWidgets(
    'all drawer entries scroll with large text and an open keyboard',
    (t) async {
      t.view.physicalSize = const Size(320, 480);
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      final key = GlobalKey<ScaffoldState>();
      await t.pumpWidget(
        muiTestApp(
          Scaffold(
            key: key,
            drawer: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: const CategoryDrawer(
                  navigation: Column(
                    children: [
                      ListTile(title: Text('智能助手')),
                      ListTile(title: Text('我的')),
                    ],
                  ),
                ),
              ),
            ),
            body: const SizedBox.expand(),
          ),
          wrapScaffold: false,
          overrides: [
            orderedCategoriesProvider.overrideWithValue(
              .data([for (var i = 0; i < 30; i++) cat('c$i', '分类$i')]),
            ),
            categoryDiaryCountsProvider.overrideWith(
              (ref) async => (byCategory: const <String, int>{}, total: 0),
            ),
          ],
        ),
      );
      key.currentState!.openDrawer();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);

      for (final label in ['分类29', '无分类', '管理分类']) {
        await t.scrollUntilVisible(
          find.text(label),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        expect(find.text(label).hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
      }
      await t.drag(find.byType(ListView), const Offset(0, -500));
      await t.pumpAndSettle();
      expect(find.text('管理分类').hitTestable(), findsOneWidget);
      expect(find.byTooltip('设置').hitTestable(), findsOneWidget);
      expect(t.getBottomLeft(find.text('管理分类')).dy, lessThanOrEqualTo(300));
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('search box only appears once categories pile up', (t) async {
    await t.pumpWidget(wrap(categories: three, byCategory: const {}, total: 0));
    await t.pumpAndSettle();
    expect(find.byType(SearchBar), findsNothing);

    await t.pumpWidget(
      wrap(
        categories: [for (var i = 0; i < 9; i++) cat('c$i', '分类$i')],
        byCategory: const {},
        total: 0,
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(SearchBar), findsOneWidget);
  });
}
