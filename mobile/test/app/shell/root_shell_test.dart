import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/moodiary_assistant.dart';
import 'package:moodiary_assistant/src/data/chat_repository.dart';
import 'package:moodiary_assistant/src/data/llm_provider_repository.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/moodiary_diary.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/home/diary_home_page.dart';
import 'package:moodiary_mobile/app/shell/root_drawer_navigation.dart';
import 'package:moodiary_mobile/app/shell/root_shell.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_sync/src/application/sync_runner.dart';
import 'package:mui/mui.dart';

final _category = Category(
  id: 'travel',
  categoryName: '旅行',
  lastModified: DateTime(2026),
);

class _EmptyDiaries extends DiaryController {
  @override
  List<Diary> build({
    String? categoryId,
    bool uncategorized = false,
    String? tag,
    bool untagged = false,
    DiaryContentFilter? content,
  }) => [];
}

const _contentCounts = {
  DiaryContentFilter.images: 3,
  DiaryContentFilter.links: 5,
  DiaryContentFilter.audio: 7,
};

class _Categories extends CategoryController {
  @override
  List<Category> build() => [_category];
}

class _EmptyPlaces extends PlaceController {
  @override
  List<Place> build() => [];
}

int _dashboardBuilds = 0;

class _Dashboard extends DashboardController {
  @override
  Future<DashboardStats> build() async {
    _dashboardBuilds++;
    return const DashboardStats(
      useDays: 1,
      diaryCount: 1,
      wordCount: 100,
      categoryCount: 1,
      streakDays: 0,
      thisMonthCount: 1,
      tagCount: 1,
      byDay: {},
      lastYearCount: 1,
    );
  }
}

class _IdleSyncRunner extends Fake implements SyncRunner {
  @override
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());
}

class _EmptyChats extends Fake implements ChatRepository {
  @override
  Stream<void> get sessionEvents => const Stream.empty();

  @override
  Future<List<ChatSession>> getAllSessions() async => [];
}

class _NoLlmProvider extends Fake implements LlmProviderRepository {
  @override
  Stream<void> get providerEvents => const Stream.empty();

  @override
  Future<LlmProvider?> getActiveProvider() async => null;
}

Future<ProviderContainer> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        diaryControllerProvider.overrideWith2((_) => _EmptyDiaries()),
        categoryControllerProvider.overrideWith(_Categories.new),
        tagDiaryCountsProvider.overrideWith(
          (ref) async => (byTag: <String, int>{'旅行': 0}, total: 0, untagged: 0),
        ),
        diaryTagsProvider.overrideWith((ref) async => ['旅行']),
        for (final entry in _contentCounts.entries)
          timelineMonthCountsProvider(
            content: entry.key,
            sort: DiarySort.timeDesc,
          ).overrideWith(
            (ref) async => {
              DateTime(2026, 6): entry.value - 1,
              DateTime(2026, 7): 1,
            },
          ),
        dashboardControllerProvider.overrideWith(_Dashboard.new),
        placeControllerProvider.overrideWith(_EmptyPlaces.new),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          theme: buildMuiTheme(brightness: Brightness.light),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            GlobalMuiLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          locale: const Locale('zh'),
          home: const MobileRootShell(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  return ProviderScope.containerOf(
    tester.element(find.byType(MobileRootShell)),
  );
}

ScaffoldState _shellScaffold(WidgetTester tester) =>
    tester.state<ScaffoldState>(
      find
          .descendant(
            of: find.byType(MobileRootShell),
            matching: find.byType(Scaffold),
          )
          .first,
    );

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.menu));
  await tester.pumpAndSettle();
  expect(_shellScaffold(tester).isDrawerOpen, isTrue);
  expect(find.byType(RootDrawerNavigation), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(RootDrawerNavigation),
      matching: find.text(l10n.app.homeNavigatorDiary),
    ),
    findsNothing,
  );
}

Future<void> _pickDestination(WidgetTester tester, String label) async {
  await _openDrawer(tester);
  final destination = find.widgetWithText(ListTile, label);
  await tester.ensureVisible(destination);
  await tester.tap(destination);
  await tester.pumpAndSettle();
  expect(_shellScaffold(tester).isDrawerOpen, isFalse);
  expect(find.byType(AppBar), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<void> _pickAllDiaries(WidgetTester tester) async {
  await _openDrawer(tester);
  final row = find.byKey(const ValueKey('all-diaries-row'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
  expect(_shellScaffold(tester).isDrawerOpen, isFalse);
  expect(find.byType(DiaryHomePage), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    _dashboardBuilds = 0;
    final runner = _IdleSyncRunner();
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(MemoryKVStorage());
        gi.registerSingleton<SyncPendingTracker>(SyncPendingTracker());
        gi.registerSingleton<SyncDirtyTracker>(SyncDirtyTracker());
        gi.registerSingleton<SyncRunner>(
          runner,
          dispose: (_) => runner.status.dispose(),
        );
        gi.registerSingleton<ChatRepository>(_EmptyChats());
        gi.registerSingleton<LlmProviderRepository>(_NoLlmProvider());
      },
    );
  });
  tearDown(getIt.popScope);

  testWidgets('抽屉顶部显示热力统计，回顾入口、日记、助手、标签顺序正确且没有我的', (tester) async {
    await _pumpShell(tester);
    await _openDrawer(tester);

    final entries = [
      find.byType(MHeatmap),
      find.widgetWithText(ListTile, l10n.common.media),
      find.widgetWithText(ListTile, l10n.diary.mapTitle),
      find.widgetWithText(ListTile, l10n.app.homeNavigatorGraph),
      find.widgetWithText(ListTile, l10n.app.meCalendar),
      find.byKey(const ValueKey('all-diaries-row')),
      find.byType(RootDrawerAssistant),
      find.byKey(const ValueKey('tags-row')),
    ];
    final drawerList = find.descendant(
      of: find.byType(TagDrawer),
      matching: find.byType(ListView),
    );
    expect(drawerList, findsOneWidget);
    for (var i = 0; i < entries.length; i++) {
      expect(entries[i], findsOneWidget);
      expect(
        find.ancestor(of: entries[i], matching: drawerList),
        findsOneWidget,
      );
      if (i > 0) {
        expect(
          tester.getRect(entries[i]).top,
          greaterThanOrEqualTo(tester.getRect(entries[i - 1]).bottom),
        );
      }
    }
    expect(find.text(l10n.app.homeNavigatorMe), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tag-drawer-header')),
        matching: find.text(l10n.diary.searchResult(count: 0)),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('重新打开抽屉会刷新热力统计', (tester) async {
    await _pumpShell(tester);
    await _openDrawer(tester);
    final firstOpenBuilds = _dashboardBuilds;
    expect(firstOpenBuilds, greaterThan(0));

    _shellScaffold(tester).closeDrawer();
    await tester.pumpAndSettle();
    await _openDrawer(tester);

    expect(_dashboardBuilds, greaterThan(firstOpenBuilds));
    expect(find.byType(MHeatmap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏上热力统计与菜单共同滚动，仍可到达标签', (tester) async {
    await _pumpShell(tester);
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    await _openDrawer(tester);
    expect(find.byType(MHeatmap).hitTestable(), findsOneWidget);
    final initialHeatmapTop = tester.getTopLeft(find.byType(MHeatmap)).dy;

    final tags = find.byKey(const ValueKey('tags-row'));
    final scrollable = find
        .descendant(
          of: find.byType(TagDrawer),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(tags, 200, scrollable: scrollable);
    await tester.pumpAndSettle();

    expect(tags.hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(MHeatmap)).dy,
      lessThan(initialHeatmapTop),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文再次选择同一标签时从助手返回日记', (tester) async {
    final container = await _pumpShell(tester);
    container
        .read(homeDiaryFilterProvider.notifier)
        .select(const DiaryFilter.tag('旅行'));
    await tester.pumpAndSettle();
    await _pickDestination(tester, l10n.app.homeNavigatorAssistant);
    expect(find.byType(AssistantSessionListPage), findsOneWidget);
    container
        .read(homeDiaryFilterProvider.notifier)
        .select(const DiaryFilter.tag('旅行'));
    await tester.pumpAndSettle();
    expect(find.byType(DiaryHomePage), findsOneWidget);
    expect(container.read(homeDiaryFilterProvider).tagPath, '旅行');
  });

  testWidgets('日记与助手均可打开抽屉切换，点击当前页面也会收起抽屉', (tester) async {
    await _pumpShell(tester);
    expect(find.byType(DiaryHomePage), findsOneWidget);

    await _pickDestination(tester, l10n.app.homeNavigatorAssistant);
    expect(find.byType(AssistantSessionListPage), findsOneWidget);
    expect(find.byTooltip(l10n.assistant.menuSettings), findsOneWidget);
    expect(find.byTooltip(l10n.assistant.newChat), findsOneWidget);
    await _pickDestination(tester, l10n.app.homeNavigatorAssistant);
    expect(find.byType(AssistantSessionListPage), findsOneWidget);

    await _pickAllDiaries(tester);
    expect(find.byType(DiaryHomePage), findsOneWidget);
    await _pickAllDiaries(tester);
    expect(find.byType(DiaryHomePage), findsOneWidget);
  });

  testWidgets('从助手选择同一标签仍返回日记，日记入口恢复所有内容', (tester) async {
    final container = await _pumpShell(tester);
    await _openDrawer(tester);
    await tester.ensureVisible(find.text(_category.categoryName));
    await tester.tap(find.text(_category.categoryName));
    await tester.pumpAndSettle();
    expect(
      container.read(homeDiaryFilterProvider),
      const DiaryFilter.tag('旅行'),
    );

    await _pickDestination(tester, l10n.app.homeNavigatorAssistant);
    expect(
      container.read(homeDiaryFilterProvider),
      const DiaryFilter.tag('旅行'),
    );
    await _openDrawer(tester);
    final tag = find.descendant(
      of: find.byType(TagDrawer),
      matching: find.text(_category.categoryName),
    );
    await tester.ensureVisible(tag);
    await tester.tap(tag);
    await tester.pumpAndSettle();
    expect(find.byType(DiaryHomePage), findsOneWidget);
    expect(_shellScaffold(tester).isDrawerOpen, isFalse);
    expect(
      container.read(homeDiaryFilterProvider),
      const DiaryFilter.tag('旅行'),
    );
    expect(tester.takeException(), isNull);

    await _pickAllDiaries(tester);
    expect(container.read(homeDiaryFilterProvider).isAll, isTrue);
  });

  testWidgets('从助手选择内容筛选返回日记并显示相应标题和总数', (tester) async {
    final container = await _pumpShell(tester);
    for (final (key, label, filter) in [
      ('filter-images', l10n.diary.filterImages, const DiaryFilter.images()),
      ('filter-links', l10n.diary.filterLinks, const DiaryFilter.links()),
      ('filter-audio', l10n.diary.filterAudio, const DiaryFilter.audio()),
    ]) {
      await _pickDestination(tester, l10n.app.homeNavigatorAssistant);
      await _openDrawer(tester);
      final row = find.byKey(ValueKey(key));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(DiaryHomePage), findsOneWidget);
      expect(_shellScaffold(tester).isDrawerOpen, isFalse);
      expect(container.read(homeDiaryFilterProvider), filter);
      expect(container.read(diarySelectionProvider), isEmpty);
      final appBar = find.byType(AppBar);
      expect(
        find.descendant(of: appBar, matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: appBar,
          matching: find.text(
            l10n.diary.searchResult(count: _contentCounts[filter.content]!),
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }

    await _pickAllDiaries(tester);
    expect(container.read(homeDiaryFilterProvider).isAll, isTrue);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(l10n.diary.filterAudio),
      ),
      findsNothing,
    );
  });

  testWidgets('日记多选时隐藏菜单并禁用抽屉，取消后恢复', (tester) async {
    final container = await _pumpShell(tester);
    container.read(diarySelectionProvider.notifier).enter('selected-diary');
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.menu), findsNothing);
    expect(_shellScaffold(tester).widget.drawer, isNull);
    expect(_shellScaffold(tester).widget.drawerEnableOpenDragGesture, isFalse);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byTooltip(l10n.common.cancel));
    await tester.pumpAndSettle();

    expect(container.read(diarySelectionProvider), isEmpty);
    expect(find.byIcon(LucideIcons.menu), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await _openDrawer(tester);
    expect(tester.takeException(), isNull);
  });
}
