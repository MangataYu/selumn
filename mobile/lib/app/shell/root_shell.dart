import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_assistant/moodiary_assistant.dart'
    show AssistantSessionListPage;
import 'package:moodiary_diary/moodiary_diary.dart'
    show CategoryDrawer, diarySelectionProvider, homeDiaryFilterProvider;
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/home/diary_home_page.dart'
    show DiaryHomePage;
import 'package:moodiary_mobile/app/me/me_page.dart' show MePage;
import 'package:moodiary_mobile/app/shell/root_navigation.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:mui/mui.dart';

enum _ShellTab { diary, assistant, me }

class MobileRootShell extends ConsumerStatefulWidget {
  const MobileRootShell({super.key});

  @override
  ConsumerState<MobileRootShell> createState() => _MobileRootShellState();
}

class _MobileRootShellState extends ConsumerState<MobileRootShell> {
  _ShellTab _tab = .diary;

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late final List<Widget> _pages = [
    DiaryHomePage(onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer()),
    const AssistantSessionListPage(),
    const MePage(),
  ];

  Future<void> _newDiary() async {
    final categoryId = _tab == .diary
        ? ref.read(homeDiaryFilterProvider).categoryId
        : null;
    await NewDiaryRoute(categoryId: categoryId).push(context);
  }

  void _selectTab(int index) {
    if (_tab.index == index) return;
    ref.read(diarySelectionProvider.notifier).clear();
    setState(() => _tab = _ShellTab.values[index]);
  }

  MNavAction? _navAction(BuildContext context) {
    final l10n = context.l10n;
    return switch (_tab) {
      .diary => null,
      .assistant => MNavAction(
        icon: const Icon(LucideIcons.messageCirclePlus),
        tooltip: l10n.assistant.newChat,
        onPressed: () => const AssistantConversationRoute().push(context),
      ),
      .me => MNavAction(
        icon: const Icon(LucideIcons.settings),
        tooltip: l10n.app.settingsTitle,
        onPressed: () => const SettingRoute().push(context),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final selecting =
        ref.watch(diarySelectionProvider).isNotEmpty && _tab == .diary;
    final drawerUsable = _tab == .diary && !selecting;
    return Scaffold(
      key: _scaffoldKey,
      drawer: drawerUsable ? const CategoryDrawer() : null,
      drawerEnableOpenDragGesture: drawerUsable,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Visibility(
              visible: !selecting,
              child: RootNavigation(
                selectedIndex: _tab.index,
                onDestinationSelected: _selectTab,
                action: _navAction(context),
              ),
            ),
            Expanded(
              child: MLazyIndexedStack(index: _tab.index, children: _pages),
            ),
          ],
        ),
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
