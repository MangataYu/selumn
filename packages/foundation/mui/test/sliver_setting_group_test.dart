import 'package:flutter_test/flutter_test.dart';
import 'package:mui/mui.dart';

Widget _host({
  required int itemCount,
  String? title,
  double viewportHeight = 600,
  ScrollController? controller,
}) => MaterialApp(
  theme: buildMuiTheme(brightness: Brightness.light),
  home: Scaffold(
    body: SizedBox(
      height: viewportHeight,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          MSliverSettingGroup(
            title: title,
            children: [
              for (var i = 0; i < itemCount; i++)
                SettingListTile(title: 'item$i', onTap: () {}),
            ],
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('n 项之间 n-1 条分隔线，首尾不画', (tester) async {
    await tester.pumpWidget(_host(itemCount: 3));
    expect(find.byType(SettingListTile), findsNWidgets(3));
    expect(find.byType(MSettingDivider), findsNWidgets(2));
  });

  testWidgets('分隔线是一个设备像素：thickness 0 即 Skia hairline', (tester) async {
    await tester.pumpWidget(_host(itemCount: 2));
    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.thickness, 0, reason: '改成 1/devicePixelRatio 会跨两行各画一半');
    expect(divider.height, 0, reason: '线本身不该占额外高度');
  });

  testWidgets('给了标题才有标题行', (tester) async {
    await tester.pumpWidget(_host(itemCount: 2));
    expect(find.byType(SettingTitleTile), findsNothing);

    await tester.pumpWidget(_host(itemCount: 2, title: '显示'));
    expect(find.byType(SettingTitleTile), findsOneWidget);
    expect(find.text('显示'), findsOneWidget);
  });

  group('圆角落在首末项上', () {
    final radius = buildMuiTheme(brightness: Brightness.light)
        .extension<MuiTokens>()!
        .radii
        .sm;

    List<BorderRadius> radiiOf(WidgetTester tester) => tester
        .widgetList<ClipRRect>(
          find.descendant(
            of: find.byType(MSliverSettingGroup),
            matching: find.byType(ClipRRect),
          ),
        )
        .map((c) => c.borderRadius as BorderRadius)
        .toList();

    testWidgets('首项只圆上面、末项只圆下面，中间项不包', (tester) async {
      await tester.pumpWidget(_host(itemCount: 3));
      final radii = radiiOf(tester);
      expect(radii.length, 2, reason: '中间那项不该多包一层');
      expect(radii.first, BorderRadius.vertical(top: Radius.circular(radius)));
      expect(
        radii.last,
        BorderRadius.vertical(bottom: Radius.circular(radius)),
      );
    });

    testWidgets('只有一项时四个角都圆', (tester) async {
      await tester.pumpWidget(_host(itemCount: 1));
      expect(radiiOf(tester).single, BorderRadius.all(Radius.circular(radius)));
    });

    testWidgets('按压反馈是 MInkWell 的自绘遮罩，不吃 material 水波', (tester) async {
      await tester.pumpWidget(_host(itemCount: 2));
      expect(find.byType(MInkWell), findsNWidgets(2));
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });
  });

  testWidgets('无标题组块用短留白分开，组内仍连续', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMuiTheme(brightness: Brightness.light),
        home: const Scaffold(
          body: CustomScrollView(
            slivers: [
              MSliverSettingGroup(
                children: [
                  SettingListTile(title: 'First'),
                  SettingListTile(title: 'Second'),
                ],
              ),
              MSliverSettingGroup(children: [SettingListTile(title: 'Third')]),
            ],
          ),
        ),
      ),
    );
    final rows = find.byType(SettingListTile);
    expect(find.byType(SettingTitleTile), findsNothing);
    expect(
      tester.getRect(rows.at(1)).top,
      closeTo(tester.getRect(rows.first).bottom, 0.01),
    );
    final gap =
        tester.getRect(rows.at(2)).top - tester.getRect(rows.at(1)).bottom;
    expect(gap, closeTo(12, 0.01));
    expect(find.byType(MSettingDivider), findsOneWidget);
  });
}
