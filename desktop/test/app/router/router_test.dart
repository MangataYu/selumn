import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_desktop/app/router/route_error_page.dart';
import 'package:moodiary_desktop/app/router/router.dart';
import 'package:moodiary_desktop/app/shell/root_shell.dart';
import 'package:moodiary_editor/moodiary_editor.dart'
    show EditorMigrationService;
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

void main() {
  test('diary and sync routes live inside the desktop shell', () {
    final routes = buildDesktopRoutes();
    final shell = routes.whereType<ShellRoute>().single;
    final paths = shell.routes.whereType<GoRoute>().map((route) => route.path);
    expect(
      paths,
      containsAll([
        DiaryHomeRoute.path,
        DiaryRoute.path,
        NewDiaryRoute.path,
        DiarySearchRoute.path,
        SettingRoute.path,
        BackupSyncRoute.path,
        AssistantConversationRoute.path,
      ]),
    );
    expect(paths, isNot(contains(LockRoute.path)));
    expect(paths, isNot(contains(EditorMigrationRoute.path)));
    final rootPaths = routes.whereType<GoRoute>().map((route) => route.path);
    expect(rootPaths, containsAll([LockRoute.path, EditorMigrationRoute.path]));
  });

  testWidgets('unknown location shows the localized recovery page', (
    tester,
  ) async {
    final router = createDesktopRouter(
      initialLocation: '/missing',
      navigatorKey: GlobalKey<NavigatorState>(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp.router(
          theme: buildMuiTheme(brightness: Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RouteErrorPage), findsOneWidget);
    expect(find.byType(DesktopRootShell), findsNothing);
    expect(find.text('/missing'), findsOneWidget);
  });

  test(
    'migration gate covers desktop routes and permits lock and migration',
    () {
      EditorMigrationService.requiresMigration = true;
      addTearDown(() => EditorMigrationService.requiresMigration = false);
      expect(
        migrationGateRedirect(DiaryHomeRoute.path),
        EditorMigrationRoute.path,
      );
      expect(
        migrationGateRedirect(SettingRoute.path),
        EditorMigrationRoute.path,
      );
      expect(migrationGateRedirect(EditorMigrationRoute.path), isNull);
      expect(migrationGateRedirect(LockRoute.path), isNull);
    },
  );
}
