import 'package:moodiary_router/moodiary_router.dart';
import 'package:mui/mui.dart';

final _openingDiary = Expando<bool>();

/// The editor shares one draft provider, so only one new diary can be open.
Future<void> openNewDiary(BuildContext context, {String? tag}) async {
  final router = GoRouter.of(context);
  if (_openingDiary[router] == true ||
      _hasDraft(router.routerDelegate.currentConfiguration.matches)) {
    return;
  }
  _openingDiary[router] = true;
  late final Future<void> popped;
  try {
    popped = router.pushRoute<void>(NewDiaryRoute(tag: tag));
    // Protect repeated input until the new route appears in the navigator tree.
    await WidgetsBinding.instance.endOfFrame;
  } finally {
    _openingDiary[router] = false;
  }
  return popped;
}

bool _hasDraft(List<RouteMatchBase> matches) => matches.any(
  (match) =>
      match.route is GoRoute &&
          (match.route as GoRoute).path == NewDiaryRoute.path ||
      match is ShellRouteMatch && _hasDraft(match.matches),
);
