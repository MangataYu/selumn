import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_desktop/app/home/diary_home_page.dart';
import 'package:moodiary_desktop/app/shell/root_shell.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/moodiary_diary.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_sync/src/application/sync_runner.dart';
import 'package:mui/mui.dart';

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

class _IdleSyncRunner extends Fake implements SyncRunner {
  @override
  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());
}

Future<GoRouter> _pumpShell(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      ShellRoute(
        builder: (_, state, child) => DesktopRootShell(
          showHome: state.uri.path == DiaryHomeRoute.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: DiaryHomeRoute.path,
            builder: (_, _) => const DesktopHomeContent(),
          ),
          GoRoute(
            path: NewDiaryRoute.path,
            builder: (_, state) => Scaffold(
              body: Column(
                children: [
                  Text('initial-tag:${state.params['tag']}'),
                  const TextField(key: ValueKey('draft'), autofocus: true),
                ],
              ),
            ),
          ),
          GoRoute(
            path: DiarySearchRoute.path,
            builder: (_, _) => const Scaffold(body: Text('search page')),
          ),
          GoRoute(
            path: DiaryRoute.path,
            builder: (_, _) => const Scaffold(body: Text('existing diary')),
          ),
          GoRoute(
            path: SettingRoute.path,
            builder: (_, _) => const Scaffold(body: Text('settings page')),
          ),
          GoRoute(
            path: TagManagerRoute.path,
            builder: (_, _) => const Scaffold(body: Text('tag manager page')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        diaryControllerProvider.overrideWith2((_) => _EmptyDiaries()),
        diaryTagsProvider.overrideWith((ref) async => ['生活', '阅读']),
        tagDiaryCountsProvider.overrideWith(
          (ref) async => (byTag: const <String, int>{}, total: 0, untagged: 0),
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
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  return router;
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
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
      },
    );
  });
  tearDown(getIt.popScope);

  testWidgets('Ctrl+N preserves the selected tag and Ctrl+F opens search', (
    tester,
  ) async {
    final router = await _pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('tag-row:生活')));
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyN);

    expect(find.text('initial-tag:生活'), findsOneWidget);
    expect(find.byType(DesktopDiaryHomePage), findsOneWidget);
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    expect(find.text('search page'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing an open editor preserves its draft and navigator', (
    tester,
  ) async {
    final router = await _pumpShell(tester);
    await tester.tap(find.byTooltip(l10n.app.homePageAddDiaryButton).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('draft')), '继续写作');
    final editorState = tester.state(find.byType(EditableText));

    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopDiaryHomePage), findsNothing);
    expect(find.text('继续写作'), findsOneWidget);
    expect(tester.state(find.byType(EditableText)), same(editorState));

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(EditableText)), same(editorState));
    router.pop();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(find.byType(DesktopDiaryHomePage), findsOneWidget);
    expect(find.byIcon(LucideIcons.menu), findsOneWidget);
    await tester.tap(find.byIcon(LucideIcons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tag-row:阅读')).hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(TagDrawer), findsNothing);
    expect(find.text('#阅读'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated new diary actions keep a single draft route', (
    tester,
  ) async {
    final router = await _pumpShell(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyN);
    await tester.enterText(find.byKey(const ValueKey('draft')), '同一份草稿');
    await tester.tap(find.byKey(const ValueKey('tag-drawer-settings')));
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyN);
    expect(find.text('settings page'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyN);
    await tester.tap(find.byTooltip(l10n.app.homePageAddDiaryButton).first);
    await tester.pumpAndSettle();
    expect(find.text('同一份草稿'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('draft')), findsNothing);
    expect(find.byType(DesktopHomeContent), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new diary is available after draft route becomes an existing diary',
    (tester) async {
      final router = await _pumpShell(tester);
      await _shortcut(tester, LogicalKeyboardKey.keyN);
      router.replace(DiaryRoute.path, extra: const {'diary_id': 'saved'});
      await tester.pumpAndSettle();
      expect(find.text('existing diary'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyN);
      expect(find.byKey(const ValueKey('draft')), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('existing diary'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sidebar settings and tag manager keep the editor underneath', (
    tester,
  ) async {
    final router = await _pumpShell(tester);
    await _shortcut(tester, LogicalKeyboardKey.keyN);
    await tester.enterText(find.byKey(const ValueKey('draft')), '侧栏导航后保留');
    for (final (key, text) in [
      ('tag-drawer-settings', 'settings page'),
      ('tag-manager-button', 'tag manager page'),
    ]) {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('侧栏导航后保留'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
