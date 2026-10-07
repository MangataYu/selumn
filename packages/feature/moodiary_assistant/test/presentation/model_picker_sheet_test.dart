import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/model_resolver.dart';
import 'package:moodiary_assistant/src/presentation/model_picker_sheet.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';

LlmProvider _provider(String name) => LlmProvider.create(
  name: name,
  type: AssistantProviderType.openaiCompletions,
  baseUrl: '',
  defaultModel: 'a',
  sortOrder: 0,
);

ModelOption _option(String id, {List<String> levels = const []}) =>
    ModelOption(id: id, label: id, preset: null, levels: levels);

void main() {
  late LlmProvider alpha;
  late LlmProvider beta;
  GlobalModelChoice? choice;
  var opened = false;

  setUp(() {
    alpha = _provider('Alpha');
    beta = _provider('Beta');
    choice = null;
    opened = false;
  });

  Widget host({
    required String modelId,
    String? level,
    List<ProviderModels>? groups,
    ValueChanged<LlmProvider>? onFillKey,
    double textScale = 1,
  }) {
    final data = buildMuiTheme(brightness: Brightness.light);
    return TranslationProvider(
      child: MuiTheme(
        data: data,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          theme: data,
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            GlobalMuiLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  opened = true;
                  choice = await showGlobalModelPicker(
                    context,
                    groups:
                        groups ??
                        [
                          (
                            provider: alpha,
                            options: [
                              _option('a', levels: ['low', 'high']),
                              _option('b'),
                            ],
                            hasKey: true,
                          ),
                          (
                            provider: beta,
                            options: [_option('c')],
                            hasKey: false,
                          ),
                        ],
                    providerId: alpha.id,
                    modelId: modelId,
                    level: level,
                    catalogUpdatedAt: 0,
                    onDownloadCatalog: () async => const [],
                    onManageProviders: () {},
                    onFillKey: onFillKey ?? (_) {},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('点模型行只是选中，确认后才带回；档位原样保留', (tester) async {
    await tester.pumpWidget(host(modelId: 'a', level: 'high'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(choice, isNull);
    expect(find.text('b'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(choice, (providerId: alpha.id, modelId: 'b', level: 'high'));
    expect(find.text('b'), findsNothing);
  });

  testWidgets('档位 chip 跟着选中的行走，点了也不关', (tester) async {
    await tester.pumpWidget(host(modelId: 'a', level: null));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('低'), findsOneWidget);
    expect(find.text('高'), findsOneWidget);
    expect(find.text('跟随模型'), findsNothing);
    await tester.tap(find.text('不思考'));
    await tester.pumpAndSettle();
    expect(choice, isNull);

    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    expect(find.text('不思考'), findsNothing);

    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
    expect(find.text('不思考'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(choice, (
      providerId: alpha.id,
      modelId: 'a',
      level: reasoningOffValue,
    ));
  });

  testWidgets('取消不带回任何选择', (tester) async {
    await tester.pumpWidget(host(modelId: 'a', level: 'high'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(choice, isNull);
  });

  testWidgets('缺 Key 的供应商给出去填写的路，模型行不可点', (tester) async {
    await tester.pumpWidget(host(modelId: 'a'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('去填写 →'), findsOneWidget);
    await tester.tap(find.text('c'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(choice, isNull);
    expect(find.text('c'), findsOneWidget);
  });

  testWidgets('订阅缺凭据时提示登录并把对应供应商交给登录入口', (tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final subscription = beta.copyWith(
      name: 'ChatGPT',
      type: AssistantProviderType.chatgptSubscription.id,
    );
    LlmProvider? loginProvider;
    await tester.pumpWidget(
      host(
        modelId: 'a',
        textScale: 2,
        groups: [
          (provider: alpha, options: [_option('a')], hasKey: true),
          (provider: subscription, options: [_option('c')], hasKey: false),
        ],
        onFillKey: (provider) => loginProvider = provider,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('需要登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('登录 ChatGPT →'), findsOneWidget);
    expect(find.text('缺少 Key'), findsNothing);
    expect(find.text('去填写 →'), findsNothing);
    expect(find.textContaining('API Key'), findsNothing);

    await tester.tap(find.text('登录 ChatGPT →'));
    await tester.pumpAndSettle();

    expect(loginProvider, subscription);
    expect(choice, isNull);
    expect(find.text('需要登录'), findsNothing);
  });

  testWidgets('钉住的模型已不在目录里：造一条合成行，仍可重钉', (tester) async {
    await tester.pumpWidget(host(modelId: 'gone'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('gone'), findsOneWidget);
    expect(find.text('目录中已无此模型'), findsOneWidget);
    await tester.tap(find.text('a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(choice?.modelId, 'a');
  });
}
