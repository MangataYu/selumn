import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/chatgpt_provider_auth.dart';
import 'package:moodiary_assistant/src/data/model_resolver.dart';
import 'package:moodiary_chatgpt/moodiary_chatgpt.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/testing.dart';

LlmProvider _subscription({
  List<String> models = const ['account-model'],
  String defaultModel = 'account-model',
}) => LlmProvider(
  id: 'subscription',
  name: 'ChatGPT',
  type: AssistantProviderType.chatgptSubscription.id,
  baseUrl: 'https://custom-provider.invalid/v1',
  defaultModel: defaultModel,
  createdAt: DateTime.utc(2026),
  sortOrder: 0,
  presetId: 'openai',
  models: models,
  reasoning: true,
);

void main() {
  group('ChatGPT subscription model resolution', () {
    late _CachedChatGptAuth auth;

    setUp(() {
      auth = _CachedChatGptAuth();
      getIt.pushNewScope(
        init: (scope) => scope.registerSingleton<ChatGptProviderAuth>(
          auth,
          dispose: (value) => value.dispose(),
        ),
      );
      // No preset repository is registered: subscription resolution must not
      // consult models.dev even if a stored provider has a presetId.
    });

    tearDown(() => getIt.popScope());

    for (final modelId in ['', 'another-account-model']) {
      test('resolve uses the official endpoint for model "$modelId"', () {
        final provider = _subscription();

        final result = ModelResolver.resolve(provider, modelId);

        expect(result.protocol, AssistantProviderType.chatgptSubscription);
        expect(result.baseUrl, 'https://api.openai.com/v1');
        expect(result.modelId, modelId.isEmpty ? 'account-model' : modelId);
        expect(result.preset, isNull);
      });
    }

    test(
      'options use account labels and only the saved available model IDs',
      () {
        final provider = _subscription(
          models: ['account-model', 'uncached-model'],
          defaultModel: 'removed-model',
        );
        auth.modelsByProvider[provider.id] = const [
          ChatGptModel('account-model', 'Account Model'),
          ChatGptModel('removed-model', 'Removed Model'),
          ChatGptModel('cached-only-model', 'Cached Only Model'),
        ];

        final options = ModelResolver.optionsFor(provider);

        expect(options.map((option) => option.id), [
          'account-model',
          'uncached-model',
        ]);
        expect(options.map((option) => option.label), [
          'Account Model',
          'uncached-model',
        ]);
        expect(options.map((option) => option.preset), everyElement(isNull));
        expect(options.map((option) => option.levels), everyElement(isEmpty));
      },
    );

    test('an empty model list does not restore the removed default model', () {
      final provider = _subscription(models: [], defaultModel: 'removed-model');
      auth.modelsByProvider[provider.id] = const [
        ChatGptModel('removed-model', 'Removed Model'),
      ];

      expect(ModelResolver.optionsFor(provider), isEmpty);
    });

    test('model labels are read from the corresponding provider account', () {
      final first = _subscription();
      final second = first.copyWith(id: 'second-subscription');
      auth.modelsByProvider[first.id] = const [
        ChatGptModel('account-model', 'First Account Model'),
      ];
      auth.modelsByProvider[second.id] = const [
        ChatGptModel('account-model', 'Second Account Model'),
      ];

      expect(
        ModelResolver.optionsFor(first).single.label,
        'First Account Model',
      );
      expect(
        ModelResolver.optionsFor(second).single.label,
        'Second Account Model',
      );
    });

    test(
      'reasoning levels stay empty despite saved custom capability flags',
      () {
        final provider = _subscription();

        expect(ModelResolver.levelsFor(provider, 'account-model'), isEmpty);
        expect(ModelResolver.levelsFor(provider, 'removed-model'), isEmpty);
      },
    );

    test('an empty subscription model cannot be sent', () {
      expect(
        () => ModelResolver.validateForRequest(_subscription(), ''),
        throwsA(
          isA<ChatGptException>().having(
            (error) => error.code,
            'code',
            'model_not_selected',
          ),
        ),
      );
    });

    test('a subscription model removed from the catalogue cannot be sent', () {
      expect(
        () =>
            ModelResolver.validateForRequest(_subscription(), 'removed-model'),
        throwsA(
          isA<ChatGptException>().having(
            (error) => error.code,
            'code',
            'model_not_selected',
          ),
        ),
      );
    });

    test('an available subscription model can be sent', () {
      expect(
        () =>
            ModelResolver.validateForRequest(_subscription(), 'account-model'),
        returnsNormally,
      );
    });

    test('custom API model IDs do not require a subscription catalogue', () {
      final provider = _subscription(models: []).copyWith(
        type: AssistantProviderType.openaiCompletions.id,
        presetId: '',
      );

      expect(
        () =>
            ModelResolver.validateForRequest(provider, 'custom-unlisted-model'),
        returnsNormally,
      );
    });
  });
}

class _CachedChatGptAuth extends ChatGptProviderAuth {
  _CachedChatGptAuth() : super(MemorySecureKVStorage());

  final modelsByProvider = <String, List<ChatGptModel>>{};

  @override
  List<ChatGptModel> cachedModels(String id) =>
      modelsByProvider[id] ?? const [];
}
