import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_assistant/moodiary_assistant.dart'
    show AssistantSessionListPage;
import 'package:moodiary_data/moodiary_data.dart'
    show dashboardControllerProvider;
import 'package:moodiary_diary/moodiary_diary.dart'
    show TagDrawer, diarySelectionProvider, homeDiaryFilterProvider;
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/home/diary_home_page.dart'
    show DiaryHomePage;
import 'package:moodiary_mobile/app/shell/drawer_dashboard.dart';
import 'package:moodiary_mobile/app/shell/root_drawer_navigation.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:mui/mui.dart';

enum _ShellTab { diary, assistant }

class MobileRootShell extends ConsumerStatefulWidget {
  const MobileRootShell({super.key});

  @override
  ConsumerState<MobileRootShell> createState() => _MobileRootShellState();
}

class _MobileRootShellState extends ConsumerState<MobileRootShell> {
  _ShellTab _tab = .diary;

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late final List<Widget> _pages = [
    DiaryHomePage(onOpenDrawer: _openDrawer),
    AssistantSessionListPage(onOpenDrawer: _openDrawer),
  ];

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  Future<void> _newDiary() async {
    final tag = _tab == .diary
        ? ref.read(homeDiaryFilterProvider).tagPath
        : null;
    await NewDiaryRoute(tag: tag).push(context);
  }

  void _selectAssistant() {
    _scaffoldKey.currentState?.closeDrawer();
    _selectTab(.assistant);
  }

  void _selectTab(_ShellTab tab) {
    ref.read(diarySelectionProvider.notifier).clear();
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(homeDiaryFilterProvider, (_, _) => _selectTab(.diary));
    final selecting =
        ref.watch(diarySelectionProvider).isNotEmpty && _tab == .diary;
    final drawerUsable = !selecting;
    return Scaffold(
      key: _scaffoldKey,
      drawer: drawerUsable
          ? TagDrawer(
              overview: const DrawerDashboard(),
              navigation: const RootDrawerNavigation(),
              afterDiary: RootDrawerAssistant(
                selected: _tab == .assistant,
                onTap: _selectAssistant,
              ),
              isDiarySelected: _tab == .diary,
              onFilterSelected: () => _selectTab(.diary),
            )
          : null,
      drawerEnableOpenDragGesture: drawerUsable,
      onDrawerChanged: (opened) {
        if (opened) ref.invalidate(dashboardControllerProvider);
      },
      body: SafeArea(
        bottom: false,
        child: MLazyIndexedStack(index: _tab.index, children: _pages),
      ),
      floatingActionButton: _tab == .diary && !selecting
          ? FloatingActionButton(
              tooltip: context.l10n.app.homePageAddDiaryButton,
              backgroundColor: context.theme.colors.primary,
              foregroundColor: context.theme.colors.onPrimary,
              shape: const CircleBorder(),
              onPressed: _newDiary,
              child: const Icon(LucideIcons.pencilLine),
            )
          : null,
    );
  }
}
