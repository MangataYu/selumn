import 'package:moodiary_router/moodiary_router.dart';

import 'src/presentation/account_page.dart';

export 'src/data/account_config.dart';
export 'src/data/account_models.dart';
export 'src/data/account_repository.dart';
export 'src/presentation/account_page.dart';

List<RouteBase> accountRoutes() => [
  GoRoute(path: AccountRoute.path, builder: (_, _) => const AccountPage()),
];
