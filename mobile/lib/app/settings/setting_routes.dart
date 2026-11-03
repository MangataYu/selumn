import 'package:moodiary_mobile/app/settings/presentation/about_page.dart';
import 'package:moodiary_mobile/app/settings/presentation/accent_page.dart';
import 'package:moodiary_mobile/app/settings/presentation/diary_setting_page.dart';
import 'package:moodiary_mobile/app/settings/presentation/services_page.dart';
import 'package:moodiary_mobile/app/settings/presentation/setting_page.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:moodiary_router/moodiary_router.dart';

class AccentRoute extends MoodiaryRouteBase {
  static const String path = '/setting/accent';

  const AccentRoute() : super(path);
}

class ServicesRoute extends MoodiaryRouteBase {
  static const String path = '/setting/services';

  const ServicesRoute() : super(path);
}

class ModelManagementRoute extends MoodiaryRouteBase {
  static const String path = '/setting/models';

  const ModelManagementRoute() : super(path);
}

class AboutRoute extends MoodiaryRouteBase {
  static const String path = '/setting/about';

  const AboutRoute() : super(path);
}

class DiarySettingRoute extends MoodiaryRouteBase {
  static const String path = '/setting/diary_setting';

  const DiarySettingRoute() : super(path);
}

List<RouteBase> settingRoutes() => [
  GoRoute(path: SettingRoute.path, builder: (_, _) => const SettingPage()),
  GoRoute(
    path: StorageRoute.path,
    builder: (context, _) => StoragePage(
      onManageModels: () => const ModelManagementRoute().push(context),
    ),
  ),
  GoRoute(
    path: ModelManagementRoute.path,
    builder: (_, _) => const ModelManagementPage(),
  ),
  GoRoute(
    path: DiarySettingRoute.path,
    builder: (_, _) => const DiarySettingPage(),
  ),
  GoRoute(path: AccentRoute.path, builder: (_, _) => const AccentPage()),
  GoRoute(path: ServicesRoute.path, builder: (_, _) => const ServicesPage()),
  GoRoute(path: AboutRoute.path, builder: (_, _) => const AboutPage()),
];
