import 'package:flutter_test/flutter_test.dart';
import 'package:mui/mui.dart';

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  theme: buildMuiTheme(brightness: Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Column(crossAxisAlignment: .stretch, children: [child]),
    ),
  ),
);

void main() {
  testWidgets('开关表单与设置项使用相同舒适高度和字号', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(const MSwitchField(label: 'Use SSL', value: true)),
    );

    expect(tester.getSize(find.byType(MSwitchField)).height, 48);
    expect(tester.widget<Text>(find.text('Use SSL')).style!.fontSize, 16);
    expect(tester.getTopLeft(find.text('Use SSL')).dx, 12);
    expect(tester.getSize(find.byType(Switch)).height, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击标签和开关各触发一次切换', (tester) async {
    var enabled = false;
    final changes = <bool>[];
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => MSwitchField(
            label: 'Toggle',
            value: enabled,
            onChanged: (value) {
              changes.add(value);
              setState(() => enabled = value);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Toggle'));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('禁用后标签和开关都不再触发回调', (tester) async {
    final interactive = ValueNotifier(true);
    addTearDown(interactive.dispose);
    var enabled = false;
    final changes = <bool>[];
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder(
          valueListenable: interactive,
          builder: (context, canChange, _) => StatefulBuilder(
            builder: (context, setState) => MSwitchField(
              label: 'Toggle',
              value: enabled,
              onChanged: canChange
                  ? (value) {
                      changes.add(value);
                      setState(() => enabled = value);
                    }
                  : null,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Toggle'));
    await tester.pumpAndSettle();
    interactive.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toggle'));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(changes, [true]);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320宽和两倍字号时长标签自然增高且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const label =
        'A longer setting label remains readable when the system text size '
        'is increased and the screen is narrow.';

    await tester.pumpWidget(
      _host(
        MSwitchField(label: label, value: true, onChanged: (_) {}),
        textScale: 2,
      ),
    );

    final field = tester.getRect(find.byType(MSwitchField));
    final text = tester.getRect(find.text(label));
    final control = tester.getRect(find.byType(Switch));
    expect(field.height, greaterThan(48));
    expect(text.top, greaterThan(field.top));
    expect(text.bottom, lessThan(field.bottom));
    expect(text.right, lessThanOrEqualTo(control.left));
    expect(control.bottom, lessThanOrEqualTo(field.bottom));
    expect(tester.takeException(), isNull);
  });
}
