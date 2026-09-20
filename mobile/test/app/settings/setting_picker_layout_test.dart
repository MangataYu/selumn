import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/settings/presentation/widget/accent_sheet.dart';
import 'package:moodiary_mobile/app/settings/presentation/widget/language_dialog.dart';
import 'package:moodiary_mobile/app/settings/presentation/widget/theme_mode_dialog.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
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

class _ThemeManager extends ThemeManager {
  @override
  bool get supportDynamic => true;

  @override
  Color get systemAccentSeed => const Color(0xFF336699);
}

enum _Picker { accent, theme, language }

Future<void> _pumpPicker(
  WidgetTester tester,
  _Picker picker, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 560);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appSettingsControllerProvider.overrideWith(_Settings.new)],
      child: TranslationProvider(
        child: MaterialApp(
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
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => switch (picker) {
                    .accent => AccentSheet.show(context),
                    .theme => showDialog<void>(
                      context: context,
                      builder: (_) => const ThemeModeDialog(),
                    ),
                    .language => showDialog<void>(
                      context: context,
                      builder: (_) => const LanguageDialog(),
                    ),
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _choice(_Picker picker) => switch (picker) {
  .accent => l10n.app.accentSystem,
  .theme => l10n.app.themeModeDark,
  .language => l10n.app.languageEnglish,
};

Object? _stored(_Picker picker) => switch (picker) {
  .accent => MoodiaryKVs.themeAccentMode.get(),
  .theme => MoodiaryKVs.themeMode.get(),
  .language => MoodiaryKVs.language.get(),
};

Object _expected(_Picker picker) => switch (picker) {
  .accent => ThemeAccentMode.system.index,
  .theme => ThemeMode.dark.index,
  .language => Language.english.languageCode,
};

Finder _row(_Picker picker, String label) => find
    .ancestor(
      of: find.text(label),
      matching: picker == .accent
          ? find.byType(MInkWell)
          : find.byType(SimpleDialogOption),
    )
    .first;

void main() {
  late String? initialIntlLocale;

  setUp(() async {
    initialIntlLocale = Intl.defaultLocale;
    await LocaleSettings.setLocale(AppLocale.zh);
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(MemoryKVStorage());
        gi.registerSingleton<ThemeManager>(_ThemeManager());
      },
    );
  });

  tearDown(() async {
    await getIt.popScope();
    await LocaleSettings.setLocale(AppLocale.zh);
    Intl.defaultLocale = initialIntlLocale;
  });

  for (final picker in _Picker.values) {
    testWidgets('${picker.name} 选项保持适中密度，关闭不改值，点击后保存', (tester) async {
      await _pumpPicker(tester, picker);
      final before = _stored(picker);
      final label = _choice(picker);
      await _open(tester);

      expect(tester.getSize(_row(picker, label)).height, 48);
      expect(tester.widget<Text>(find.text(label)).style?.fontSize, 16);
      if (picker == .accent) {
        expect(
          tester.widget<Text>(find.text(l10n.app.accentTitle)).style?.fontSize,
          16,
        );
      } else {
        expect(
          tester
              .widget<SimpleDialog>(find.byType(SimpleDialog))
              .titleTextStyle
              ?.fontSize,
          16,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(_stored(picker), before);

      await _open(tester);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(_stored(picker), _expected(picker));
      if (picker == .accent) {
        expect(find.byType(AccentSheet), findsOneWidget);
        expect(
          find.descendant(
            of: _row(picker, label),
            matching: find.byIcon(LucideIcons.check),
          ),
          findsOneWidget,
        );
      } else {
        expect(find.byType(SimpleDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('${picker.name} 在320宽两倍字号下换行增高并可选择', (tester) async {
      await _pumpPicker(tester, picker, width: 320, textScale: 2);
      final label = _choice(picker);
      await _open(tester);
      expect(tester.getSize(_row(picker, label)).height, greaterThan(48));
      if (picker != .accent) {
        final title = picker == .theme ? l10n.app.themeMode : l10n.app.language;
        expect(
          tester.getTopLeft(find.text(title)).dx -
              tester.getTopLeft(_row(picker, label)).dx,
          closeTo(10, 0.01),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(_stored(picker), _expected(picker));
      expect(tester.takeException(), isNull);
    });
  }
}
