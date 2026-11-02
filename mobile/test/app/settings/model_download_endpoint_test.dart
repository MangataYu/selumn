import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:moodiary_assistant/src/data/llm_provider_repository.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_ml/moodiary_ml.dart';
import 'package:moodiary_mobile/app/settings/presentation/services_page.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

class _NoLlmProvider extends Fake implements LlmProviderRepository {
  @override
  Stream<void> get providerEvents => const Stream.empty();

  @override
  Future<LlmProvider?> getActiveProvider() async => null;
}

class _NoModel extends Fake implements EmbeddingModelManager {
  @override
  EmbeddingModelSpec? get active => null;
}

void main() {
  late String? initialIntlLocale;

  setUp(() async {
    initialIntlLocale = Intl.defaultLocale;
    await LocaleSettings.setLocale(AppLocale.zh);
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(MemoryKVStorage());
        gi.registerSingleton<ISecureKVStorage>(MemorySecureKVStorage());
        gi.registerSingleton<LlmProviderRepository>(_NoLlmProvider());
        gi.registerSingleton<EmbeddingModelManager>(_NoModel());
      },
    );
  });

  tearDown(() async {
    await getIt.popScope();
    await LocaleSettings.setLocale(AppLocale.zh);
    Intl.defaultLocale = initialIntlLocale;
  });

  testWidgets('模型下载地址可切换，非法地址不会保存', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: TranslationProvider(
          child: MaterialApp(
            theme: buildMuiTheme(brightness: Brightness.light),
            localizationsDelegates: const [
              ...GlobalMaterialLocalizations.delegates,
              GlobalMuiLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            locale: const Locale('zh'),
            builder: FlutterSmartDialog.init(),
            home: const ServicesPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> choose(String label) async {
      await tester.tap(find.text(l10n.app.servicesHfEndpoint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    expect(HfHub.endpoint, HfHub.mirrorEndpoint);
    await choose(l10n.app.servicesHfOfficial);
    expect(HfHub.endpoint, HfHub.officialEndpoint);
    await choose(l10n.app.servicesHfMirror);
    expect(HfHub.endpoint, HfHub.mirrorEndpoint);

    await choose(l10n.app.servicesHfCustom);
    await tester.enterText(find.byType(TextField), 'ftp://example.com');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.app.servicesHfInvalid), findsOneWidget);
    expect(HfHub.endpoint, HfHub.mirrorEndpoint);

    await tester.enterText(find.byType(TextField), 'mirror.example/base/');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(HfHub.endpoint, 'https://mirror.example/base');
    expect(find.text('https://mirror.example/base'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
