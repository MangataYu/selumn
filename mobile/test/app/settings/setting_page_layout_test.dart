import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/settings/presentation/diary_setting_page.dart';
import 'package:moodiary_mobile/app/settings/presentation/setting_page.dart';
import 'package:moodiary_mobile/app/settings/presentation/widget/theme_mode_dialog.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

class _Settings extends AppSettingsController {
  @override
  AppSettings build() => AppSettings(
    lightTheme: buildMuiTheme(brightness: Brightness.light),
    darkTheme: buildMuiTheme(brightness: Brightness.dark),
    themeMode: ThemeMode.system,
  );

  @override
  Future<void> bumpTheme() async {
    state = state.copyWith(
      themeMode: ThemeMode.values[MoodiaryKVs.themeMode.get()!],
    );
  }
}

class _Cache extends CacheController {
  @override
  Future<CacheUsage> build() async =>
      const CacheUsage(display: '6.65 MB', bytes: 6973030);
}

class _Places extends PlaceController {
  @override
  List<Place> build() => [
    for (var i = 0; i < 2; i++)
      Place(
        id: 'place-$i',
        name: '地点 $i',
        latitude: 0,
        longitude: 0,
        lastModified: DateTime(2026),
      ),
  ];

  void clear() => state = const AsyncData([]);
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  double width = 390,
  double height = 900,
  double textScale = 1,
  List<GoRoute> routes = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => page),
      ...routes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsControllerProvider.overrideWith(_Settings.new),
        cacheControllerProvider.overrideWith(_Cache.new),
        placeControllerProvider.overrideWith(_Places.new),
      ],
      child: TranslationProvider(
        child: MaterialApp.router(
          theme: buildMuiTheme(brightness: Brightness.light),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            GlobalMuiLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          locale: const Locale('zh'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
}

Finder _row(String title) => find.widgetWithText(SettingListTile, title);

void main() {
  setUp(() {
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(MemoryKVStorage());
        gi.registerSingleton<ISecureKVStorage>(MemorySecureKVStorage());
      },
    );
  });
  tearDown(getIt.popScope);

  testWidgets('设置保留六组独立背景和紧凑组间距，管理入口位于功能设置之后', (tester) async {
    await _pumpPage(tester, const SettingPage(), height: 1200);

    expect(find.byType(SettingTitleTile), findsNothing);
    expect(find.byType(MSliverSettingGroup), findsNWidgets(6));
    expect(find.byType(DecoratedSliver), findsNWidgets(6));
    final groups = [
      (first: l10n.app.diarySettings, last: l10n.app.assistantEntry),
      (first: l10n.diary.tagManagerTitle, last: l10n.app.syncBackup),
      (first: l10n.app.themeMode, last: l10n.app.fontStyle),
      (first: l10n.lock.title, last: l10n.app.backgroundPrivacy),
      (first: l10n.app.repairTitle, last: l10n.app.cacheClear),
      (first: l10n.app.about, last: l10n.app.services),
    ];
    for (var i = 0; i < groups.length; i++) {
      final first = tester.getRect(_row(groups[i].first));
      expect(first.left, 8);
      expect(first.right, 382);
      if (i > 0) {
        final previous = tester.getRect(_row(groups[i - 1].last));
        expect(first.top - previous.bottom, closeTo(12, 0.01));
      }
    }
    final diaryText = tester.widget<Text>(find.text(l10n.app.diarySettings));
    expect(diaryText.style?.fontSize, 16);
    expect(tester.getSize(_row(l10n.app.diarySettings)).height, 48);
    final managementRows = [
      l10n.diary.tagManagerTitle,
      l10n.app.placeManager,
      l10n.app.recycle,
      l10n.export.pageTitle,
      l10n.app.syncBackup,
    ];
    for (var i = 0; i < managementRows.length; i++) {
      expect(_row(managementRows[i]), findsOneWidget);
      expect(tester.getSize(_row(managementRows[i])).height, 48);
      if (i > 0) {
        expect(
          tester.getTopLeft(_row(managementRows[i])).dy,
          greaterThan(tester.getTopLeft(_row(managementRows[i - 1])).dy),
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('常用地点数量随地点数据更新', (tester) async {
    await _pumpPage(tester, const SettingPage());
    final places = _row(l10n.app.placeManager);
    expect(
      find.descendant(of: places, matching: find.text('2')),
      findsOneWidget,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingPage)),
    );
    (container.read(placeControllerProvider.notifier) as _Places).clear();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: places, matching: find.text('0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final entry in [
    (label: () => l10n.diary.tagManagerTitle, path: TagManagerRoute.path),
    (label: () => l10n.app.placeManager, path: PlaceManagerRoute.path),
    (label: () => l10n.app.recycle, path: RecycleRoute.path),
    (label: () => l10n.export.pageTitle, path: ExportRoute.path),
    (label: () => l10n.app.syncBackup, path: BackupSyncRoute.path),
  ]) {
    testWidgets('管理入口 ${entry.path} 导航到原路由且可返回设置', (tester) async {
      final destinationKey = ValueKey(entry.path);
      await _pumpPage(
        tester,
        const SettingPage(),
        routes: [
          GoRoute(
            path: entry.path,
            builder: (_, _) => Scaffold(
              key: destinationKey,
              appBar: AppBar(),
              body: const SizedBox.shrink(),
            ),
          ),
        ],
      );
      await tester.tap(_row(entry.label()));
      await tester.pumpAndSettle();
      expect(find.byKey(destinationKey), findsOneWidget);
      expect(find.byType(SettingPage), findsNothing);
      final backButton = find.descendant(
        of: find.byKey(destinationKey),
        matching: find.byType(BackButton),
      );
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(find.byType(SettingPage), findsOneWidget);
      expect(_row(entry.label()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('收紧后的设置行仍能打开主题选项并保存选择', (tester) async {
    await _pumpPage(tester, const SettingPage());
    await tester.tap(_row(l10n.app.themeMode));
    await tester.pumpAndSettle();
    expect(find.byType(ThemeModeDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ThemeModeDialog),
        matching: find.text(l10n.app.themeModeLight),
      ),
    );
    await tester.pumpAndSettle();
    expect(MoodiaryKVs.themeMode.get(), 1);
    expect(find.byType(ThemeModeDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 宽两倍字号时设置自然增高并可滚动到底部', (tester) async {
    await _pumpPage(
      tester,
      const SettingPage(),
      width: 320,
      height: 560,
      textScale: 2,
    );
    expect(find.byType(SettingTitleTile), findsNothing);
    expect(
      tester.getSize(_row(l10n.app.diarySettings)).height,
      greaterThan(48),
    );
    expect(tester.takeException(), isNull);

    for (final title in [
      l10n.diary.tagManagerTitle,
      l10n.app.placeManager,
      l10n.app.recycle,
      l10n.export.pageTitle,
      l10n.app.syncBackup,
    ]) {
      await tester.scrollUntilVisible(
        _row(title),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(_row(title).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.scrollUntilVisible(
      find.text(l10n.app.services),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.app.services).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日记设置用两组块组织，编辑开关仍可直接点击', (tester) async {
    await _pumpPage(tester, const DiarySettingPage());
    expect(find.byType(SettingTitleTile), findsNothing);
    expect(find.byType(MSliverSettingGroup), findsNWidgets(2));
    expect(find.byType(DecoratedSliver), findsNWidgets(2));
    final before = MoodiaryKVs.showWritingTime.get();
    await tester.tap(find.text(l10n.app.showWritingTime));
    await tester.pumpAndSettle();
    expect(MoodiaryKVs.showWritingTime.get(), !before!);
    expect(tester.takeException(), isNull);
  });
}
