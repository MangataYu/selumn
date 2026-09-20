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
    final destinations = [
      (LucideIcons.bookText, context.l10n.app.homeNavigatorDiary),
      (LucideIcons.astroid, context.l10n.app.homeNavigatorAssistant),
      (LucideIcons.circleUser, context.l10n.app.homeNavigatorMe),
    ];
    return Padding(
      padding: const .fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          for (var i = 0; i < destinations.length; i++)
            Semantics(
              selected: i == selectedIndex,
              child: ListTile(
                leading: Icon(destinations[i].$1, size: 22),
                title: Text(destinations[i].$2),
                selected: i == selectedIndex,
                selectedTileColor: colors.secondaryContainer,
                selectedColor: colors.onSecondaryContainer,
                shape: const StadiumBorder(),
                onTap: () => onDestinationSelected(i),
              ),
            ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
