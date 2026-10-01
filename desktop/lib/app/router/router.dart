import 'package:moodiary_assistant/moodiary_assistant.dart'
    show assistantRoutes;
import 'package:moodiary_desktop/app/router/route_error_page.dart';
import 'package:moodiary_desktop/app/settings/setting_page.dart';
import 'package:moodiary_desktop/app/shell/root_shell.dart';
import 'package:moodiary_diary/moodiary_diary.dart';
import 'package:moodiary_editor/moodiary_editor.dart'
    show EditorMigrationService, editorRoutes;
import 'package:moodiary_export/moodiary_export.dart' show exportRoutes;
import 'package:moodiary_lock/moodiary_lock.dart' show lockRoutes;
import 'package:moodiary_media/moodiary_media.dart' show mediaRoutes;
import 'package:moodiary_migration/moodiary_migration.dart'
    show EngineMigrationService;
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_sync/moodiary_sync.dart' show syncRoutes;
import 'package:mui/mui.dart';

export 'package:moodiary_router/moodiary_router.dart';

final moodiaryNavigationKey = GlobalKey<NavigatorState>();

late final GoRouter router;

void buildRouter({String initialLocation = '/'}) {
  router = createDesktopRouter(initialLocation: initialLocation);
}

@visibleForTesting
GoRouter createDesktopRouter({
  String initialLocation = '/',
  GlobalKey<NavigatorState>? navigatorKey,
}) => GoRouter(
  routes: buildDesktopRoutes(),
  initialLocation: initialLocation,
  navigatorKey: navigatorKey ?? moodiaryNavigationKey,
  observers: [FlutterSmartDialog.observer],
  redirect: (_, state) => migrationGateRedirect(state.matchedLocation),
  errorBuilder: (_, state) =>
      RouteErrorPage(uri: state.uri, error: state.error),
);

@visibleForTesting
List<RouteBase> buildDesktopRoutes() => [
  ShellRoute(
    observers: [moodiaryRouteObserver],
    builder: (_, state, child) => DesktopRootShell(
      showHome: state.uri.path == DiaryHomeRoute.path,
      child: child,
    ),
    routes: [
      GoRoute(
        path: DiaryHomeRoute.path,
        builder: (_, _) => const DesktopHomeContent(),
      ),
      ...diaryRoutes(),
      ...mediaRoutes(),
      GoRoute(
        path: SettingRoute.path,
        builder: (_, _) => const DesktopSettingPage(),
      ),
      ...syncRoutes(),
      ...exportRoutes(),
      ...assistantRoutes(),
    ],
  ),
  ...lockRoutes(),
  ...editorRoutes(),
];

@visibleForTesting
String? migrationGateRedirect(String matchedLocation) {
  if (!EngineMigrationService.requiresMigration &&
      !EditorMigrationService.requiresMigration) {
    return null;
  }
  if (matchedLocation == EditorMigrationRoute.path ||
      matchedLocation == LockRoute.path) {
    return null;
  }
  return EditorMigrationRoute.path;
}
