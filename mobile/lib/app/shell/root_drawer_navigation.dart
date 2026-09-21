import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:mui/mui.dart';

class RootDrawerNavigation extends StatelessWidget {
  const RootDrawerNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = [
      (LucideIcons.image, l10n.common.media, const MediaRoute()),
      (LucideIcons.map, l10n.diary.mapTitle, const MapRoute()),
      (
        LucideIcons.waypoints,
        l10n.app.homeNavigatorGraph,
        const DiaryGraphRoute(),
      ),
      (LucideIcons.calendarDays, l10n.app.meCalendar, const CalendarRoute()),
    ];
    return Column(
      mainAxisSize: .min,
      children: [
        for (final (icon, label, route) in destinations)
          _DrawerDestination(
            icon: icon,
            label: label,
            onTap: () {
              Navigator.of(context).pop();
              route.push(context);
            },
          ),
      ],
    );
  }
}

class RootDrawerAssistant extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const RootDrawerAssistant({
    super.key,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => _DrawerDestination(
    icon: LucideIcons.astroid,
    label: context.l10n.app.homeNavigatorAssistant,
    selected: selected,
    onTap: onTap,
  );
}

class _DrawerDestination extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerDestination({
    required this.icon,
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final spacing = context.spacing;
    return Padding(
      padding: .symmetric(horizontal: spacing.sm),
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          selected: selected,
          child: ListTile(
            contentPadding: .symmetric(horizontal: spacing.sm),
            minTileHeight: 40,
            minVerticalPadding: spacing.xs,
            minLeadingWidth: 16,
            horizontalTitleGap: spacing.sm,
            leading: Icon(icon, size: 16),
            title: Text(label),
            titleTextStyle: selected
                ? context.theme.typography.bodyMedium.onSecondaryContainer
                : context.theme.typography.bodyMedium.onSurface,
            selected: selected,
            selectedTileColor: colors.secondaryContainer,
            selectedColor: colors.onSecondaryContainer,
            shape: const RoundedRectangleBorder(borderRadius: MuiRadius.sm),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
