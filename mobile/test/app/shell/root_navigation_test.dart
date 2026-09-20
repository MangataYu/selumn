import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/shell/root_navigation.dart';
import 'package:mui/mui.dart';

void main() {
  Widget host(
    RootNavigation navigation, {
    TextScaler? textScaler,
    ThemeData? theme,
  }) => TranslationProvider(
    child: MaterialApp(
      theme: theme ?? buildMuiTheme(brightness: Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        appBar: navigation,
        body: const SizedBox.expand(key: ValueKey('pageBody')),
      ),
    ),
  );

  testWidgets('顶部只保留品牌和打开侧栏的菜单按钮', (tester) async {
    var opened = false;

    await tester.pumpWidget(
      host(RootNavigation(onOpenDrawer: () => opened = true)),
    );

    expect(find.text(l10n.common.appName), findsOneWidget);
    for (final label in [
      l10n.app.homeNavigatorDiary,
      l10n.app.homeNavigatorAssistant,
      l10n.app.homeNavigatorMe,
    ]) {
      expect(find.byTooltip(label), findsNothing);
      expect(find.text(label), findsNothing);
    }
    final menu = find.widgetWithIcon(IconButton, LucideIcons.menu);
    expect(tester.widget<IconButton>(menu).tooltip, isNotEmpty);
    expect(tester.getSize(find.byType(AppBar)).height, 48);
    expect(tester.getRect(find.byKey(const ValueKey('pageBody'))).top, 48);
    expect(tester.getRect(find.text(l10n.common.appName)).left, 48);
    await tester.tap(menu);
    expect(opened, isTrue);
  });

  testWidgets('品牌顶栏遵循主题高度，保留底栏高度及菜单和操作点击', (tester) async {
    var menuOpens = 0;
    var saves = 0;
    final baseTheme = buildMuiTheme(brightness: Brightness.light);

    for (final toolbarHeight in [48.0, 60.0]) {
      await tester.pumpWidget(
        host(
          RootNavigation(
            onOpenDrawer: () => menuOpens++,
            actions: [
              IconButton(
                tooltip: l10n.common.save,
                icon: const Icon(LucideIcons.check),
                onPressed: () => saves++,
              ),
            ],
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(24),
              child: SizedBox(
                key: ValueKey('filterBar'),
                height: 24,
                width: double.infinity,
              ),
            ),
          ),
          theme: baseTheme.copyWith(
            appBarTheme: baseTheme.appBarTheme.copyWith(
              toolbarHeight: toolbarHeight,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final appBar = tester.getRect(find.byType(AppBar));
      final filterBar = tester.getRect(find.byKey(const ValueKey('filterBar')));
      final body = tester.getRect(find.byKey(const ValueKey('pageBody')));
      expect(appBar.height, toolbarHeight + 24);
      expect(filterBar.top, toolbarHeight);
      expect(filterBar.height, 24);
      expect(body.top, appBar.bottom);
      await tester.tap(find.widgetWithIcon(IconButton, LucideIcons.menu));
      await tester.tap(find.byTooltip(l10n.common.save));
      expect(tester.takeException(), isNull);
    }
    expect(menuOpens, 2);
    expect(saves, 2);
  });

  testWidgets('窄屏大字号仍可触达导航与页面操作', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var menuOpened = false;
    var chatOpened = false;

    await tester.pumpWidget(
      host(
        RootNavigation(
          onOpenDrawer: () => menuOpened = true,
          actions: [
            IconButton(
              icon: const Icon(LucideIcons.messageCirclePlus),
              tooltip: l10n.assistant.newChat,
              onPressed: () => chatOpened = true,
            ),
          ],
        ),
        textScaler: const TextScaler.linear(2),
      ),
    );

    expect(tester.takeException(), isNull);
    final menu = find.widgetWithIcon(IconButton, LucideIcons.menu);
    final menuSize = tester.getSize(menu);
    expect(menuSize.width, greaterThanOrEqualTo(48));
    expect(menuSize.height, greaterThanOrEqualTo(48));
    final action = find.byTooltip(l10n.assistant.newChat).hitTestable();
    expect(action, findsOneWidget);
    expect(tester.getRect(action).right, lessThanOrEqualTo(320));
    await tester.tap(menu);
    await tester.tap(find.byTooltip(l10n.assistant.newChat));
    expect(menuOpened, isTrue);
    expect(chatOpened, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
