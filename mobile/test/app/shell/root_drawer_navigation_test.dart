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
    l10n.app.homeNavigatorDiary,
    l10n.app.homeNavigatorAssistant,
    l10n.app.homeNavigatorMe,
  ];

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
          i == index,
          reason: destinations[i],
        );
      }
    }

    expectSelected(0);
    for (final index in [1, 2, 0]) {
      await tester.tap(find.widgetWithText(ListTile, labels()[index]));
      await tester.pumpAndSettle();
      expectSelected(index);
    }
    expect(visited, [1, 2, 0]);
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
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
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
      expect(rect.height, greaterThanOrEqualTo(48));
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(visited, [0, 1, 2]);
  });
}
