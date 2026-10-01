import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_desktop/app/shell/workspace_layout.dart';
import 'package:mui/mui.dart';

const _sidebarKey = ValueKey('sidebar');
const _listKey = ValueKey('diary-list');
const _editorKey = ValueKey('editor');

class _Editor extends StatefulWidget {
  const _Editor();

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      TextField(key: _editorKey, controller: controller);
}

Widget _app({bool showHome = false}) => MaterialApp(
  theme: buildMuiTheme(brightness: Brightness.light),
  home: Scaffold(
    body: DesktopWorkspaceLayout(
      showHome: showHome,
      sidebar: const ColoredBox(key: _sidebarKey, color: Colors.white),
      diaryList: const ColoredBox(key: _listKey, color: Colors.white),
      content: const _Editor(),
    ),
  ),
);

void main() {
  testWidgets('wide window shows navigation, list and editor side by side', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());

    expect(tester.getSize(find.byKey(_sidebarKey)).width, 248);
    expect(tester.getSize(find.byKey(_listKey)).width, 352);
    expect(tester.getSize(find.byKey(_editorKey)).width, 840);
    expect(tester.getTopLeft(find.byKey(_listKey)).dx, 248);
    expect(tester.getTopLeft(find.byKey(_editorKey)).dx, 600);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resize and compact home preserve the current editor draft', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.enterText(find.byKey(_editorKey), '未保存的日记');
    final initialState = tester.state<_EditorState>(find.byType(_Editor));

    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(find.byKey(_sidebarKey), findsNothing);
    expect(find.byKey(_listKey), findsNothing);
    expect(tester.getSize(find.byKey(_editorKey)).width, 800);
    expect(
      tester.state<_EditorState>(find.byType(_Editor)),
      same(initialState),
    );
    expect(initialState.controller.text, '未保存的日记');

    await tester.pumpWidget(_app(showHome: true));
    expect(find.byKey(_editorKey), findsNothing);
    expect(tester.getSize(find.byKey(_listKey)).width, 800);
    expect(initialState.mounted, isTrue);
    expect(initialState.controller.text, '未保存的日记');

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(
      tester.state<_EditorState>(find.byType(_Editor)),
      same(initialState),
    );
    expect(find.text('未保存的日记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
