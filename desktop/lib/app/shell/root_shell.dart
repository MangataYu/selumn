import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_desktop/app/home/diary_home_page.dart';
import 'package:moodiary_desktop/app/home/diary_navigation.dart';
import 'package:moodiary_desktop/app/shell/workspace_layout.dart';
import 'package:moodiary_diary/moodiary_diary.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:mui/mui.dart';

class DesktopRootShell extends ConsumerStatefulWidget {
  final Widget child;
  final bool showHome;

  const DesktopRootShell({
    super.key,
    required this.child,
    required this.showHome,
  });

  @override
  ConsumerState<DesktopRootShell> createState() => _DesktopRootShellState();
}

class _DesktopRootShellState extends ConsumerState<DesktopRootShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _newDiary() {
    final tag = ref.read(homeDiaryFilterProvider).tagPath;
    openNewDiary(context, tag: tag);
  }

  @override
  Widget build(BuildContext context) {
    final selecting = ref.watch(diarySelectionProvider).isNotEmpty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _newDiary,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            const DiarySearchRoute().push(context),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= DesktopWorkspaceLayout.wideBreakpoint;
            return Scaffold(
              key: _scaffoldKey,
              drawer: wide || selecting
                  ? null
                  : const TagDrawer(navigation: _DesktopNavigation()),
              drawerEnableOpenDragGesture: !wide && !selecting,
              body: SafeArea(
                child: DesktopWorkspaceLayout(
                  showHome: widget.showHome,
                  sidebar: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: context.theme.colors.outlineVariant,
                        ),
                      ),
                    ),
                    child: const TagDrawer(
                      persistent: true,
                      navigation: _DesktopNavigation(persistent: true),
                    ),
                  ),
                  diaryList: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: context.theme.colors.outlineVariant,
                        ),
                      ),
                    ),
                    child: DesktopDiaryHomePage(
                      onOpenDrawer: wide || selecting
                          ? null
                          : () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                  ),
                  content: widget.child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class DesktopHomeContent extends ConsumerWidget {
  const DesktopHomeContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.notebookPen,
            size: 56,
            color: context.theme.colors.onSurfaceVariant,
          ),
          SizedBox(height: context.spacing.lg),
          Text(
            context.l10n.common.appName,
            style: context.theme.typography.headlineSmall.onSurface,
          ),
          SizedBox(height: context.spacing.lg),
          FilledButton.icon(
            onPressed: () => openNewDiary(
              context,
              tag: ref.read(homeDiaryFilterProvider).tagPath,
            ),
            icon: const Icon(LucideIcons.pencilLine),
            label: Text(context.l10n.app.homePageAddDiaryButton),
          ),
        ],
      ),
    ),
  );
}

class _DesktopNavigation extends StatelessWidget {
  final bool persistent;

  const _DesktopNavigation({this.persistent = false});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (icon, label, route) in [
        (LucideIcons.image, context.l10n.common.media, const MediaRoute()),
        (
          LucideIcons.calendarDays,
          context.l10n.app.meCalendar,
          const CalendarRoute(),
        ),
        (
          LucideIcons.trash2,
          context.l10n.diary.recycleTitle,
          const RecycleRoute(),
        ),
      ])
        ListTile(
          dense: true,
          leading: Icon(icon, size: 18),
          title: Text(label),
          onTap: () {
            if (!persistent) Navigator.of(context).pop();
            route.push(context);
          },
        ),
    ],
  );
}
