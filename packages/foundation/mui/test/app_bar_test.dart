import 'package:flutter_test/flutter_test.dart';
import 'package:mui/mui.dart';

const _actionKey = Key('app-bar-action');
const _bodyKey = Key('detail-body');

Future<void> _openPage(
  WidgetTester tester, {
  required double width,
  required String title,
  required VoidCallback onAction,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 720);
  tester.view.padding = const FakeViewPadding(top: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildMuiTheme(brightness: Brightness.light)
          .copyWith(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(
                      title: Text(title),
                      actions: [
                        IconButton(
                          key: _actionKey,
                          onPressed: onAction,
                          icon: const Icon(LucideIcons.search),
                        ),
                      ],
                    ),
                    body: const SizedBox.expand(key: _bodyKey),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('$width 宽工具栏保留安全区、标题对齐且返回和动作可点击', (tester) async {
      var actions = 0;
      const title = '设置';
      await _openPage(
        tester,
        width: width,
        title: title,
        onAction: () => actions++,
      );

      final toolbar = tester.getRect(find.byType(NavigationToolbar));
      final titleFinder = find.text(title);
      expect(toolbar.top, 24);
      expect(toolbar.height, 48);
      expect(tester.getSize(find.byType(AppBar)).height, 72);
      expect(tester.getTopLeft(find.byKey(_bodyKey)).dy, 72);
      expect(tester.getTopLeft(titleFinder).dx, 56);
      expect(
        DefaultTextStyle.of(tester.element(titleFinder)).style.fontSize,
        18,
      );

      final back = find.byType(BackButton);
      expect(tester.getSize(back).width, 48);
      expect(
        tester.getSize(find.descendant(of: back, matching: find.byType(Icon))),
        const Size(20, 20),
      );
      expect(
        tester.getSize(find.byIcon(LucideIcons.search)),
        const Size(20, 20),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(_actionKey));
      await tester.pumpAndSettle();
      expect(actions, 1);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byKey(_bodyKey), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$width 宽长标题和两倍字号下不裁切高度或挤占动作', (tester) async {
      var actions = 0;
      const title = '日记显示与数据隐私设置的长中文标题';
      await _openPage(
        tester,
        width: width,
        title: title,
        textScale: 2,
        onAction: () => actions++,
      );

      final titleFinder = find.text(title);
      final titleContext = tester.element(titleFinder);
      final toolbar = tester.getRect(find.byType(NavigationToolbar));
      final titleRect = tester.getRect(titleFinder);
      final actionRect = tester.getRect(find.byKey(_actionKey));
      // material_ui caps AppBar titles at 1.34, independently of body scaling.
      expect(
        MediaQuery.textScalerOf(titleContext).scale(18),
        closeTo(18 * 1.34, 0.01),
      );
      expect(
        MediaQuery.textScalerOf(tester.element(find.byKey(_bodyKey))).scale(18),
        36,
      );
      expect(toolbar.top, 24);
      expect(toolbar.height, 48);
      expect(titleRect.left, 56);
      expect(titleRect.right, lessThanOrEqualTo(actionRect.left));
      expect(titleRect.top, greaterThanOrEqualTo(toolbar.top));
      expect(titleRect.bottom, lessThanOrEqualTo(toolbar.bottom));
      expect(actionRect.right, lessThanOrEqualTo(width));
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(_actionKey));
      await tester.pumpAndSettle();
      expect(actions, 1);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(_bodyKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
