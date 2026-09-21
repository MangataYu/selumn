import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/shell/root_drawer_navigation.dart';
import 'package:moodiary_router/moodiary_router.dart';
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

  List<(String, String)> destinations() => [
    (l10n.common.media, MediaRoute.path),
    (l10n.diary.mapTitle, MapRoute.path),
    (l10n.app.homeNavigatorGraph, DiaryGraphRoute.path),
    (l10n.app.meCalendar, CalendarRoute.path),
  ];

  testWidgets('不同屏宽下四个回顾入口保持紧凑行高和整齐的图文间距', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 390.0, 800.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpWidget(host(const RootDrawerNavigation()));
      await tester.pumpAndSettle();

      final rows = find.byType(ListTile);
      expect(rows, findsNWidgets(4));
      expect(find.text(l10n.app.homeNavigatorDiary), findsNothing);
      expect(find.text(l10n.app.homeNavigatorMe), findsNothing);
      expect(find.text(l10n.app.homeNavigatorAssistant), findsNothing);
      for (var i = 0; i < destinations().length; i++) {
        expect(tester.getSize(rows.at(i)).height, 40);
        expect(
          find.descendant(
            of: rows.at(i),
            matching: find.text(destinations()[i].$1),
          ),
          findsOneWidget,
        );
        if (i > 0) {
          expect(
            tester.getRect(rows.at(i)).top,
            tester.getRect(rows.at(i - 1)).bottom,
          );
        }
      }
      if (width == 390) {
        final icon = find.byIcon(LucideIcons.image);
        expect(tester.getRect(icon).left, 16);
        expect(tester.getSize(icon), const Size(16, 16));
        expect(tester.getRect(find.text(destinations().first.$1)).left, 40);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('助手入口切换后向读屏标识当前页面', (tester) async {
    var selected = false;
    var visited = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => RootDrawerAssistant(
            selected: selected,
            onTap: () {
              visited++;
              setState(() => selected = true);
            },
          ),
        ),
      ),
    );

    final tile = find.widgetWithText(ListTile, l10n.app.homeNavigatorAssistant);
    expect(tester.getSize(tile).height, 40);
    expect(
      tester.getSemantics(tile).flagsCollection.isSelected == .isTrue,
      isFalse,
    );
    for (var i = 0; i < 2; i++) {
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(tile).flagsCollection.isSelected == .isTrue,
        isTrue,
      );
    }
    expect(visited, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上方统计加载后助手选中背景随入口一起下移', (tester) async {
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
                  RootDrawerAssistant(selected: true, onTap: () {}),
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

    final tile = find.widgetWithText(ListTile, l10n.app.homeNavigatorAssistant);
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

  for (final largeText in [false, true]) {
    testWidgets('四个回顾入口收起抽屉后打开正确页面，返回保持关闭${largeText ? '（窄屏大字号）' : ''}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scaffoldKey = GlobalKey<ScaffoldState>();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              key: scaffoldKey,
              drawer: const Drawer(child: RootDrawerNavigation()),
              body: const SizedBox.shrink(),
            ),
          ),
          for (final (label, path) in destinations())
            GoRoute(
              path: path,
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: Text(label)),
                body: Text('destination:$path'),
              ),
            ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildMuiTheme(brightness: Brightness.light),
            localizationsDelegates: const [
              ...GlobalMaterialLocalizations.delegates,
              GlobalMuiLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            locale: const Locale('zh'),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(largeText ? 2 : 1)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final (label, path) in destinations()) {
        scaffoldKey.currentState!.openDrawer();
        await tester.pumpAndSettle();
        final tile = find.widgetWithText(ListTile, label);
        final rect = tester.getRect(tile);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        if (largeText) expect(rect.height, greaterThan(40));
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.text('destination:$path'), findsOneWidget);
        expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
        router.pop();
        await tester.pumpAndSettle();
        expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
