import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_desktop/app/settings/setting_page.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

int _themeUpdates = 0;

class _TestAppSettings extends AppSettingsController {
  @override
  AppSettings build() => AppSettings(
    lightTheme: buildMuiTheme(brightness: Brightness.light),
    darkTheme: buildMuiTheme(brightness: Brightness.dark),
    themeMode: ThemeMode.system,
  );

  @override
  Future<void> bumpTheme() async {
    _themeUpdates++;
    state = state.copyWith(
      themeMode: ThemeMode.values[MoodiaryKVs.themeMode.get()!],
    );
  }
}

Future<GoRouter> _pumpSettings(WidgetTester tester) async {
  final router = GoRouter(
    routes: [
      ShellRoute(
        builder: (_, _, child) => child,
        routes: [
          GoRoute(
            path: DiaryHomeRoute.path,
            builder: (_, _) => const Scaffold(body: Text('home page')),
          ),
          GoRoute(
            path: SettingRoute.path,
            builder: (_, _) => const DesktopSettingPage(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsControllerProvider.overrideWith(_TestAppSettings.new),
      ],
      child: TranslationProvider(
        child: MaterialApp.router(
          theme: buildMuiTheme(brightness: Brightness.light),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            GlobalMuiLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          routerConfig: router,
        ),
      ),
    ),
  );
  router.push(SettingRoute.path);
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  return router;
}

void main() {
  setUp(() async {
    _themeUpdates = 0;
    getIt.pushNewScope(
      init: (gi) => gi.registerSingleton<IKVStorage>(MemoryKVStorage()),
    );
    await LocaleSettings.setLocale(AppLocale.zh);
  });
  tearDown(() async {
    await getIt.popScope();
    await LocaleSettings.setLocale(AppLocale.zh);
  });

  testWidgets('language selection closes its dialog and keeps settings open', (
    tester,
  ) async {
    final router = await _pumpSettings(tester);
    await tester.tap(find.text(l10n.app.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.languageEnglish));
    await tester.pumpAndSettle();

    expect(MoodiaryKVs.language.get(), 'en');
    expect(LocaleSettings.currentLocale, AppLocale.en);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(find.byType(DesktopSettingPage), findsOneWidget);
    expect(router.canPop(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme selection persists mode and keeps settings open', (
    tester,
  ) async {
    final router = await _pumpSettings(tester);
    await tester.tap(find.text(l10n.app.themeMode));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.themeModeDark));
    await tester.pumpAndSettle();

    expect(MoodiaryKVs.themeMode.get(), 2);
    expect(_themeUpdates, 1);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(find.byType(DesktopSettingPage), findsOneWidget);
    expect(router.canPop(), isTrue);
    expect(tester.takeException(), isNull);
  });
}
