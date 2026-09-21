import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/shell/root_drawer_navigation.dart';
import 'package:mui/mui.dart';

void main() {
  Widget host(Widget child) => TranslationProvider(
    child: MaterialApp(
      theme: buildMuiTheme(brightness: Brightness.light),
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        GlobalMuiLocalizations.delegate,
      ],
      supportedLocales: AppLocaleUtils.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Align(alignment: .topLeft, child: child),
      ),
    ),
  );

  List<String> labels() => [
    l10n.app.homeNavigatorAssistant,
    l10n.app.homeNavigatorMe,
  ];

  testWidgets('不同屏宽下导航保持紧凑行高和整齐的图文间距', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 390.0, 800.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpWidget(
        host(
          RootDrawerNavigation(selectedIndex: 0, onDestinationSelected: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      final rows = find.byType(ListTile);
      expect(rows, findsNWidgets(2));
      expect(find.text(l10n.app.homeNavigatorDiary), findsNothing);
      for (var i = 0; i < labels().length; i++) {
        expect(tester.getSize(rows.at(i)).height, 40);
      }
      expect(tester.getRect(rows.at(1)).top, tester.getRect(rows.at(0)).bottom);
      expect(
        tester.getRect(find.byType(Divider)).top,
        tester.getRect(rows.last).bottom,
      );
      if (width == 390) {
        final icon = find.byIcon(LucideIcons.astroid);
        expect(tester.getRect(icon).left, 16);
        expect(tester.getSize(icon), const Size(16, 16));
        expect(tester.getRect(find.text(labels().first)).left, 40);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('抽屉入口逐项切换，并向读屏标识当前页面', (tester) async {
    var selected = 0;
    final visited = <int>[];

    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => RootDrawerNavigation(
            selectedIndex: selected,
            onDestinationSelected: (index) {
              visited.add(index);
              setState(() => selected = index);
            },
          ),
        ),
      ),
    );

    void expectSelected(int index) {
      final destinations = labels();
      for (var i = 0; i < destinations.length; i++) {
        expect(
          tester
                  .getSemantics(find.text(destinations[i]))
                  .flagsCollection
                  .isSelected ==
              .isTrue,
          i + 1 == index,
          reason: destinations[i],
        );
      }
    }

    expectSelected(0);
    for (final index in [1, 2, 1]) {
      await tester.tap(find.widgetWithText(ListTile, labels()[index - 1]));
      await tester.pumpAndSettle();
      expectSelected(index);
    }
    expect(visited, [1, 2, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上方统计加载后选中背景随导航一起下移', (tester) async {
    final boundaryKey = GlobalKey();
    var headerHeight = 40.0;
    late StateSetter updateHeader;
    await tester.pumpWidget(
      host(
        RepaintBoundary(
          key: boundaryKey,
          child: StatefulBuilder(
            builder: (context, setState) {
              updateHeader = setState;
              return Column(
                mainAxisSize: .min,
                children: [
                  SizedBox(height: headerHeight),
                  RootDrawerNavigation(
                    selectedIndex: 1,
                    onDestinationSelected: (_) {},
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    updateHeader(() => headerHeight = 100);
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, labels().first);
    final tileRect = tester.getRect(tile);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final sample = boundary.globalToLocal(
      Offset(tileRect.left + 2, tileRect.center.dy),
    );
    final expected = tester.element(tile).theme.colors.secondaryContainer;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final offset = (sample.dy.floor() * image.width + sample.dx.floor()) * 4;
      final pixel = Color.fromARGB(
        bytes!.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
      image.dispose();
      expect(pixel, expected);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字号下所有抽屉入口可点击且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final visited = <int>[];

    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: RootDrawerNavigation(
            selectedIndex: 0,
            onDestinationSelected: visited.add,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final destinations = labels();
    for (var i = 0; i < destinations.length; i++) {
      final tile = find.widgetWithText(ListTile, destinations[i]);
      final rect = tester.getRect(tile);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.height, greaterThan(40));
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(visited, [1, 2]);
  });
}
