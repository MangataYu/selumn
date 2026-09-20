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
      (LucideIcons.bookText, context.l10n.app.homeNavigatorDiary),
      (LucideIcons.astroid, context.l10n.app.homeNavigatorAssistant),
      (LucideIcons.circleUser, context.l10n.app.homeNavigatorMe),
    ];
    return Padding(
      padding: .fromLTRB(spacing.sm, 0, spacing.sm, spacing.xs),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Semantics(
                selected: i == selectedIndex,
                child: ListTile(
                  contentPadding: .symmetric(horizontal: spacing.sm),
                  minTileHeight: 40,
                  minVerticalPadding: spacing.xs,
                  minLeadingWidth: 16,
                  horizontalTitleGap: spacing.sm,
                  leading: Icon(destinations[i].$1, size: 16),
                  title: Text(destinations[i].$2),
                  titleTextStyle: i == selectedIndex
                      ? context.theme.typography.bodyMedium.onSecondaryContainer
                      : context.theme.typography.bodyMedium.onSurface,
                  selected: i == selectedIndex,
                  selectedTileColor: colors.secondaryContainer,
                  selectedColor: colors.onSecondaryContainer,
                  shape: const RoundedRectangleBorder(
                    borderRadius: MuiRadius.sm,
                  ),
                  onTap: () => onDestinationSelected(i),
                ),
              ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}
