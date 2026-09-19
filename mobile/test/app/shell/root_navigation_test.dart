import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/shell/root_navigation.dart';
import 'package:mui/mui.dart';

void main() {
  Widget host(Widget child) => TranslationProvider(
    child: MaterialApp(
      theme: buildMuiTheme(brightness: Brightness.light),
      home: Scaffold(
        body: Align(alignment: .topLeft, child: child),
      ),
    ),
  );

  testWidgets('顶部三个入口可切换，并向读屏标识当前页面', (tester) async {
    var selected = 0;
    final visited = <int>[];

    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => RootNavigation(
            selectedIndex: selected,
            onDestinationSelected: (index) {
              visited.add(index);
              setState(() => selected = index);
            },
          ),
        ),
      ),
    );

    final labels = [
      l10n.app.homeNavigatorDiary,
      l10n.app.homeNavigatorAssistant,
      l10n.app.homeNavigatorMe,
    ];
    for (final index in [1, 2, 0]) {
      await tester.tap(find.byTooltip(labels[index]));
      await tester.pumpAndSettle();
      for (var i = 0; i < labels.length; i++) {
        expect(
          tester
                  .getSemantics(find.byTooltip(labels[i]))
                  .flagsCollection
                  .isSelected ==
              .isTrue,
          i == index,
        );
      }
    }
    expect(visited, [1, 2, 0]);
  });

  testWidgets('窄屏大字号仍可触达导航与页面操作', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;

    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: RootNavigation(
            selectedIndex: 1,
            onDestinationSelected: (_) {},
            action: MNavAction(
              icon: const Icon(LucideIcons.messageCirclePlus),
              tooltip: l10n.assistant.newChat,
              onPressed: () => opened = true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final label in [
      l10n.app.homeNavigatorDiary,
      l10n.app.homeNavigatorAssistant,
      l10n.app.homeNavigatorMe,
    ]) {
      final size = tester.getSize(find.byTooltip(label));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byTooltip(l10n.assistant.newChat));
    expect(opened, isTrue);
  });
}
