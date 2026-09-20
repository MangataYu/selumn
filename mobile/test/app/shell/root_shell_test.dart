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
import 'package:moodiary_mobile/app/me/me_page.dart';
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
  List<Diary> build({String? categoryId, bool uncategorized = false}) => [];
}

class _Categories extends CategoryController {
  @override
  List<Category> build() => [_category];
}

class _EmptyPlaces extends PlaceController {
  @override
  List<Place> build() => [];
}

class _EmptyDashboard extends DashboardController {
  @override
  Future<DashboardStats> build() async => const DashboardStats(
    useDays: 1,
    diaryCount: 0,
    wordCount: 0,
    categoryCount: 1,
    streakDays: 0,
    thisMonthCount: 0,
    tagCount: 0,
    byDay: {},
    lastYearCount: 0,
  );
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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        diaryControllerProvider.overrideWith2((_) => _EmptyDiaries()),
        categoryControllerProvider.overrideWith(_Categories.new),
        categoryDiaryCountsProvider.overrideWith(
          (ref) async => (byCategory: <String, int>{}, total: 0),
        ),
        dashboardControllerProvider.overrideWith(_EmptyDashboard.new),
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
}

Future<void> _pickDestination(WidgetTester tester, String label) async {
  await _openDrawer(tester);
  await tester.tap(find.widgetWithText(ListTile, label));
  await tester.pumpAndSettle();
  expect(_shellScaffold(tester).isDrawerOpen, isFalse);
  expect(find.byType(AppBar), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
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

  testWidgets('三个页面均可打开抽屉切换，点击当前页面也会收起抽屉', (tester) async {
    await _pumpShell(tester);
    expect(find.byType(DiaryHomePage), findsOneWidget);

    await _pickDestination(tester, l10n.app.homeNavigatorAssistant);
    expect(find.byType(AssistantSessionListPage), findsOneWidget);
    await _pickDestination(tester, l10n.app.homeNavigatorAssistant);
    expect(find.byType(AssistantSessionListPage), findsOneWidget);

    await _pickDestination(tester, l10n.app.homeNavigatorMe);
    expect(find.byType(MePage), findsOneWidget);
    await _pickDestination(tester, l10n.app.homeNavigatorMe);
    expect(find.byType(MePage), findsOneWidget);

    await _pickDestination(tester, l10n.app.homeNavigatorDiary);
    expect(find.byType(DiaryHomePage), findsOneWidget);
    await _pickDestination(tester, l10n.app.homeNavigatorDiary);
    expect(find.byType(DiaryHomePage), findsOneWidget);
  });

  testWidgets('从助手或我的选择同一分类仍返回日记，日记菜单恢复全部日记', (tester) async {
    final container = await _pumpShell(tester);
    await _openDrawer(tester);
    await tester.tap(find.text(_category.categoryName));
    await tester.pumpAndSettle();
    expect(
      container.read(homeDiaryFilterProvider),
      const DiaryFilter.category('travel'),
    );

    for (final label in [
      l10n.app.homeNavigatorAssistant,
      l10n.app.homeNavigatorMe,
    ]) {
      await _pickDestination(tester, label);
      expect(
        container.read(homeDiaryFilterProvider),
        const DiaryFilter.category('travel'),
      );
      await _openDrawer(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(CategoryDrawer),
          matching: find.text(_category.categoryName),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiaryHomePage), findsOneWidget);
      expect(_shellScaffold(tester).isDrawerOpen, isFalse);
      expect(
        container.read(homeDiaryFilterProvider),
        const DiaryFilter.category('travel'),
      );
      expect(tester.takeException(), isNull);
    }

    await _pickDestination(tester, l10n.app.homeNavigatorDiary);
    expect(container.read(homeDiaryFilterProvider).isAll, isTrue);
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
