import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

class RootNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final MNavAction? action;

  const RootNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.action,
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
      padding: const .symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (var i = 0; i < destinations.length; i++)
            SizedBox.square(
              dimension: 48,
              child: IconButton(
                isSelected: i == selectedIndex,
                tooltip: destinations[i].$2,
                icon: Icon(destinations[i].$1, size: 22),
                style: IconButton.styleFrom(
                  backgroundColor: i == selectedIndex
                      ? colors.secondaryContainer
                      : Colors.transparent,
                  foregroundColor: i == selectedIndex
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                ),
                onPressed: () => onDestinationSelected(i),
              ),
            ),
          const Spacer(),
          if (action case final action?)
            IconButton(
              tooltip: action.tooltip,
              icon: action.icon,
              onPressed: action.onPressed,
            ),
        ],
      ),
    );
  }
}
