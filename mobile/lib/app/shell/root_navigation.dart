import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

class RootNavigation extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onOpenDrawer;
  final Widget? menuIcon;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  const RootNavigation({
    super.key,
    required this.onOpenDrawer,
    this.menuIcon,
    this.actions = const [],
    this.bottom,
  });

  @override
  Size get preferredSize => AppBar(bottom: bottom).preferredSize;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
        onPressed: onOpenDrawer,
        icon: menuIcon ?? const Icon(LucideIcons.menu),
      ),
      titleSpacing: 0,
      centerTitle: false,
      title: Text(context.l10n.common.appName),
      actions: actions,
      bottom: bottom,
    );
  }
}
