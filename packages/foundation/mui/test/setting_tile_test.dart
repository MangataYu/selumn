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
  for (final (width, inset) in [(320.0, 10.0), (390.0, 12.0), (768.0, 16.0)]) {
    testWidgets('$width 宽下设置行保留舒适字号和完整点击高度', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var taps = 0;

      await tester.pumpWidget(
        _host(
          Column(
            crossAxisAlignment: .stretch,
            children: [
              const SettingTitleTile(title: 'Group'),
              SettingListTile(
                key: const ValueKey('single'),
                title: 'Title',
                leading: const Icon(LucideIcons.tag),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => taps++,
              ),
              const MSettingDivider(),
              const SettingListTile(
                key: ValueKey('double'),
                title: 'Second',
                subtitle: 'Description',
              ),
            ],
          ),
        ),
      );

      final row = tester.getRect(find.byKey(const ValueKey('single')));
      expect(row.height, closeTo(48, 0.01));
      expect(tester.getTopLeft(find.text('Group')).dx, closeTo(inset, 0.01));
      expect(
        tester.getTopLeft(find.byIcon(LucideIcons.tag)).dx,
        closeTo(inset, 0.01),
      );
      expect(
        tester.getTopLeft(find.text('Title')).dx,
        closeTo(inset + 20 + inset, 0.01),
      );
      expect(
        width - tester.getTopRight(find.byIcon(LucideIcons.chevronRight)).dx,
        closeTo(inset, 0.01),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('double'))).height,
        closeTo(64, 0.01),
      );
      expect(tester.widget<Text>(find.text('Title')).style!.fontSize, 16);
      expect(tester.widget<Text>(find.text('Description')).style!.fontSize, 14);
      expect(tester.widget<Text>(find.text('Group')).style!.fontSize, 12);
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.indent, closeTo(inset, 0.01));
      expect(divider.endIndent, closeTo(inset, 0.01));

      await tester.tapAt(row.topLeft + const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('窄屏大字号时按内容增高，标题与说明不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const SettingListTile(
          title: 'A longer setting title that wraps',
          subtitle: 'A description that remains readable with large text.',
          leading: Icon(LucideIcons.tag),
          trailing: Icon(LucideIcons.chevronRight),
        ),
        textScale: 2,
      ),
    );

    final tile = tester.getRect(find.byType(SettingListTile));
    final title = tester.getRect(
      find.text('A longer setting title that wraps'),
    );
    final subtitle = tester.getRect(
      find.text('A description that remains readable with large text.'),
    );
    expect(tile.height, greaterThan(64));
    expect(title.bottom, lessThanOrEqualTo(subtitle.top));
    expect(subtitle.bottom, lessThanOrEqualTo(tile.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('调用方显式内容边距继续生效', (tester) async {
    await tester.pumpWidget(
      _host(
        const SettingListTile(
          title: 'Custom',
          contentPadding: EdgeInsets.symmetric(horizontal: 25, vertical: 20),
        ),
      ),
    );

    final title = tester.getRect(find.text('Custom'));
    final tile = tester.getRect(find.byType(SettingListTile));
    expect(title.left - tile.left, 25);
    expect(title.top - tile.top, 20);
    expect(tile.bottom - title.bottom, 20);
  });

  testWidgets('开关与普通设置同高，点击文字和开关各只切换一次', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var enabled = false;
    final changes = <bool>[];
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              const SettingListTile(title: 'Plain'),
              SettingSwitchListTile(
                title: 'Toggle',
                value: enabled,
                onChanged: (value) {
                  changes.add(value);
                  setState(() => enabled = value);
                },
              ),
            ],
          ),
        ),
      ),
    );
    final rows = tester.getSize(find.byType(SettingListTile).first);
    expect(rows.height, 48);
    expect(
      tester.getSize(find.byType(SettingSwitchListTile)).height,
      rows.height,
    );
    await tester.tap(find.text('Toggle'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('组合副标题继承说明字号，同时保留显式样式', (tester) async {
    await tester.pumpWidget(
      _host(
        SettingListTile(
          title: Builder(builder: (_) => const Text('Nested title')),
          subtitle: Builder(
            builder: (_) => const Row(
              children: [
                Text('Details'),
                Text('Custom', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('Nested title')))
          .style
          .fontSize,
      16,
    );
    expect(
      DefaultTextStyle.of(tester.element(find.text('Details'))).style.fontSize,
      14,
    );
    expect(tester.widget<Text>(find.text('Custom')).style!.fontSize, 11);
  });
}
