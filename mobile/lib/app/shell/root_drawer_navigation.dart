import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

class RootDrawerNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const RootDrawerNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final spacing = context.spacing;
    final destinations = [
      (1, LucideIcons.astroid, context.l10n.app.homeNavigatorAssistant),
      (2, LucideIcons.circleUser, context.l10n.app.homeNavigatorMe),
    ];
    return Padding(
      padding: .fromLTRB(spacing.sm, 0, spacing.sm, spacing.xs),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final (index, icon, label) in destinations)
              Semantics(
                selected: index == selectedIndex,
                child: ListTile(
                  contentPadding: .symmetric(horizontal: spacing.sm),
                  minTileHeight: 40,
                  minVerticalPadding: spacing.xs,
                  minLeadingWidth: 16,
                  horizontalTitleGap: spacing.sm,
                  leading: Icon(icon, size: 16),
                  title: Text(label),
                  titleTextStyle: index == selectedIndex
                      ? context.theme.typography.bodyMedium.onSecondaryContainer
                      : context.theme.typography.bodyMedium.onSurface,
                  selected: index == selectedIndex,
                  selectedTileColor: colors.secondaryContainer,
                  selectedColor: colors.onSecondaryContainer,
                  shape: const RoundedRectangleBorder(
                    borderRadius: MuiRadius.sm,
                  ),
                  onTap: () => onDestinationSelected(index),
                ),
              ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}
