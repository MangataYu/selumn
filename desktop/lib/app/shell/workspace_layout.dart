import 'package:mui/mui.dart';

/// Keeps all three panes mounted while the window switches to a single page.
class DesktopWorkspaceLayout extends StatelessWidget {
  static const wideBreakpoint = 1100.0;
  static const sidebarWidth = 248.0;
  static const diaryListWidth = 352.0;

  final Widget sidebar;
  final Widget diaryList;
  final Widget content;
  final bool showHome;

  const DesktopWorkspaceLayout({
    super.key,
    required this.sidebar,
    required this.diaryList,
    required this.content,
    required this.showHome,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= wideBreakpoint;
      final listVisible = wide || showHome;
      final listWidth = wide ? diaryListWidth : constraints.maxWidth;
      final contentVisible = wide || !showHome;
      final contentWidth = wide
          ? constraints.maxWidth - sidebarWidth - diaryListWidth
          : constraints.maxWidth;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: wide ? sidebarWidth : 0,
            child: Offstage(
              offstage: !wide,
              child: ExcludeFocus(
                excluding: !wide,
                child: OverflowBox(
                  minWidth: sidebarWidth,
                  maxWidth: sidebarWidth,
                  child: sidebar,
                ),
              ),
            ),
          ),
          SizedBox(
            width: listVisible ? listWidth : 0,
            child: Offstage(
              offstage: !listVisible,
              child: ExcludeFocus(
                excluding: !listVisible,
                child: OverflowBox(
                  minWidth: listWidth,
                  maxWidth: listWidth,
                  child: diaryList,
                ),
              ),
            ),
          ),
          Expanded(
            child: Offstage(
              offstage: !contentVisible,
              child: ExcludeFocus(
                excluding: !contentVisible,
                child: OverflowBox(
                  minWidth: contentWidth,
                  maxWidth: contentWidth,
                  child: content,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
