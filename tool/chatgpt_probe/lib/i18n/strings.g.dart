/// Generated file. Do not edit.
///
/// Source: i18n
/// To regenerate, run: `dart run slang`

// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'package:slang_flutter/slang_flutter.dart';
export 'package:slang_flutter/slang_flutter.dart';

import 'strings_en.g.dart' as l_en;
part 'strings_zh.g.dart';

/// Supported locales.
///
/// Usage:
/// - LocaleSettings.setLocale(ProbeLocale.zh) // set locale
/// - Locale locale = ProbeLocale.zh.flutterLocale // get flutter locale from enum
/// - if (LocaleSettings.currentLocale == ProbeLocale.zh) // locale check
enum ProbeLocale with BaseAppLocale<ProbeLocale, ProbeTranslations> {
  zh(languageCode: 'zh'),
  en(languageCode: 'en');

  const ProbeLocale({
    required this.languageCode,
    this.scriptCode, // ignore: unused_element, unused_element_parameter
    this.countryCode, // ignore: unused_element, unused_element_parameter
  });

  @override
  final String languageCode;
  @override
  final String? scriptCode;
  @override
  final String? countryCode;

  @override
  Future<ProbeTranslations> build({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
  }) async {
    return buildSync(
      overrides: overrides,
      cardinalResolver: cardinalResolver,
      ordinalResolver: ordinalResolver,
    );
  }

  @override
  ProbeTranslations buildSync({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
  }) {
    switch (this) {
      case ProbeLocale.zh:
        return ProbeTranslationsZh(
          overrides: overrides,
          cardinalResolver: cardinalResolver,
          ordinalResolver: ordinalResolver,
        );
      case ProbeLocale.en:
        return l_en.ProbeTranslationsEn(
          overrides: overrides,
          cardinalResolver: cardinalResolver,
          ordinalResolver: ordinalResolver,
        );
    }
  }

  /// Gets current instance managed by [LocaleSettings].
  ProbeTranslations get translations =>
      LocaleSettings.instance.getTranslations(this);
}

/// Method A: Simple
///
/// No rebuild after locale change.
/// Translation happens during initialization of the widget (call of probeL10n).
/// Configurable via 'translate_var'.
///
/// Usage:
/// String a = probeL10n.someKey.anotherKey;
ProbeTranslations get probeL10n => LocaleSettings.instance.currentTranslations;

/// Method B: Advanced
///
/// All widgets using this method will trigger a rebuild when locale changes.
/// Use this if you have e.g. a settings page where the user can select the locale during runtime.
///
/// Step 1:
/// wrap your App with
/// TranslationProvider(
/// 	child: MyApp()
/// );
///
/// Step 2:
/// final probeL10n = ProbeTranslations.of(context); // Get probeL10n variable.
/// String a = probeL10n.someKey.anotherKey; // Use probeL10n variable.
class TranslationProvider
    extends BaseTranslationProvider<ProbeLocale, ProbeTranslations> {
  TranslationProvider({required super.child})
    : super(settings: LocaleSettings.instance);

  static InheritedLocaleData<ProbeLocale, ProbeTranslations> of(
    BuildContext context,
  ) => InheritedLocaleData.of<ProbeLocale, ProbeTranslations>(context);
}

/// Method B shorthand via [BuildContext] extension method.
/// Configurable via 'translate_var'.
///
/// Usage (e.g. in a widget's build method):
/// context.probeL10n.someKey.anotherKey
extension BuildContextTranslationsExtension on BuildContext {
  ProbeTranslations get probeL10n => TranslationProvider.of(this).translations;
}

/// Manages all translation instances and the current locale
class LocaleSettings
    extends BaseFlutterLocaleSettings<ProbeLocale, ProbeTranslations> {
  LocaleSettings._() : super(utils: AppLocaleUtils.instance, lazy: false);

  static final instance = LocaleSettings._();

  // static aliases (checkout base methods for documentation)
  static ProbeLocale get currentLocale => instance.currentLocale;
  static Stream<ProbeLocale> getLocaleStream() => instance.getLocaleStream();
  static Future<ProbeLocale> setLocale(
    ProbeLocale locale, {
    bool? listenToDeviceLocale = false,
  }) => instance.setLocale(locale, listenToDeviceLocale: listenToDeviceLocale);
  static Future<ProbeLocale> setLocaleRaw(
    String rawLocale, {
    bool? listenToDeviceLocale = false,
  }) => instance.setLocaleRaw(
    rawLocale,
    listenToDeviceLocale: listenToDeviceLocale,
  );
  static Future<ProbeLocale> useDeviceLocale() => instance.useDeviceLocale();
  static Future<void> setPluralResolver({
    String? language,
    ProbeLocale? locale,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
  }) => instance.setPluralResolver(
    language: language,
    locale: locale,
    cardinalResolver: cardinalResolver,
    ordinalResolver: ordinalResolver,
  );

  // synchronous versions
  static ProbeLocale setLocaleSync(
    ProbeLocale locale, {
    bool? listenToDeviceLocale = false,
  }) => instance.setLocaleSync(
    locale,
    listenToDeviceLocale: listenToDeviceLocale,
  );
  static ProbeLocale setLocaleRawSync(
    String rawLocale, {
    bool? listenToDeviceLocale = false,
  }) => instance.setLocaleRawSync(
    rawLocale,
    listenToDeviceLocale: listenToDeviceLocale,
  );
  static ProbeLocale useDeviceLocaleSync() => instance.useDeviceLocaleSync();
  static void setPluralResolverSync({
    String? language,
    ProbeLocale? locale,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
  }) => instance.setPluralResolverSync(
    language: language,
    locale: locale,
    cardinalResolver: cardinalResolver,
    ordinalResolver: ordinalResolver,
  );
}

/// Provides utility functions without any side effects.
class AppLocaleUtils
    extends BaseAppLocaleUtils<ProbeLocale, ProbeTranslations> {
  AppLocaleUtils._()
    : super(baseLocale: ProbeLocale.zh, locales: ProbeLocale.values);

  static final instance = AppLocaleUtils._();

  // static aliases (checkout base methods for documentation)
  static ProbeLocale parse(String rawLocale) => instance.parse(rawLocale);
  static ProbeLocale parseLocaleParts({
    required String languageCode,
    String? scriptCode,
    String? countryCode,
  }) => instance.parseLocaleParts(
    languageCode: languageCode,
    scriptCode: scriptCode,
    countryCode: countryCode,
  );
  static ProbeLocale findDeviceLocale() => instance.findDeviceLocale();
  static List<Locale> get supportedLocales => instance.supportedLocales;
  static List<String> get supportedLocalesRaw => instance.supportedLocalesRaw;
}
