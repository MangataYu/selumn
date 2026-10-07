import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/chatgpt_provider_auth.dart';
import 'package:moodiary_chatgpt/moodiary_chatgpt.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

Map<String, Object?> _credentials({
  bool expired = false,
  String? refreshToken,
  List<String> scopes = const ['chatgpt.tokens.use.direct'],
}) => {
  'ext_agent_host_id': 'test-host',
  'client_id': 'test-client',
  'subject': 'test-subject',
  'access_token': 'test-access-token',
  'expires_at': DateTime.now()
      .add(Duration(hours: expired ? -1 : 1))
      .millisecondsSinceEpoch,
  'refresh_token': ?refreshToken,
  'scopes': scopes,
};

void main() {
  group('ChatGptProviderAuth', () {
    late MemorySecureKVStorage secure;
    late ChatGptProviderAuth auth;

    setUp(() {
      secure = MemorySecureKVStorage();
      auth = ChatGptProviderAuth(secure);
    });

    tearDown(() => auth.dispose());

    void store(Map<String, Object?> value, {String id = 'first'}) {
      secure.data[ChatGptProviderAuth.storageKey(id)] = jsonEncode(value);
    }

    test('valid subscription credentials are ready', () async {
      store(_credentials());

      expect(await auth.hasCredentials('first'), isTrue);
    });

    test('missing record is not ready', () async {
      expect(await auth.hasCredentials('first'), isFalse);
    });

    test('missing subscription permission is not ready', () async {
      store(_credentials(scopes: ['openid', 'profile', 'resource.invoke']));

      expect(await auth.hasCredentials('first'), isFalse);
    });

    test('expired token without a refresh token is not ready', () async {
      store(_credentials(expired: true));

      expect(await auth.hasCredentials('first'), isFalse);
    });

    test('expired token with a refresh token remains ready', () async {
      store(_credentials(expired: true, refreshToken: 'test-refresh-token'));
      final before = Map<String, String>.of(secure.data);

      expect(await auth.hasCredentials('first'), isTrue);
      expect(secure.data, before);
    });

    test('expired token with an empty refresh token is not ready', () async {
      store(_credentials(expired: true, refreshToken: ''));

      expect(await auth.hasCredentials('first'), isFalse);
    });

    for (final (label, raw) in <(String, String)>[
      ('invalid JSON', '{'),
      ('JSON list', '[]'),
      ('JSON null', 'null'),
      ('JSON scalar', '42'),
      ('empty object', '{}'),
    ]) {
      test('$label is not ready', () async {
        secure.data[ChatGptProviderAuth.storageKey('first')] = raw;

        expect(await auth.hasCredentials('first'), isFalse);
      });
    }

    for (final (label, patch) in <(String, Map<String, Object?>)>[
      ('missing host ID', {'ext_agent_host_id': null}),
      ('missing client ID', {'client_id': null}),
      ('reserved client ID', {'client_id': 'dynamic_agent_client'}),
      ('empty subject', {'subject': ''}),
      ('non-string subject', {'subject': 7}),
      ('empty access token', {'access_token': ''}),
      ('non-string access token', {'access_token': <String>[]}),
      ('non-list scopes', {'scopes': 'chatgpt.tokens.use.direct'}),
      (
        'non-string scope',
        {
          'scopes': ['chatgpt.tokens.use.direct', 7],
        },
      ),
      ('non-integer expiry', {'expires_at': 'tomorrow'}),
      (
        'non-integer expiry with refresh token',
        {'expires_at': 'tomorrow', 'refresh_token': 'test-refresh-token'},
      ),
    ]) {
      test('$label is not ready', () async {
        store({..._credentials(), ...patch});

        expect(await auth.hasCredentials('first'), isFalse);
      });
    }

    test('providers use separate records and never read the API key', () async {
      store(_credentials());
      store(_credentials(scopes: []), id: 'second');
      secure.data['llm_key_first'] = 'first-api-key';
      secure.data['llm_key_second'] = 'second-api-key';
      secure.data['llm_key_api-only'] = 'api-only-key';
      final before = Map<String, String>.of(secure.data);

      expect(await auth.hasCredentials('first'), isTrue);
      expect(await auth.hasCredentials('second'), isFalse);
      expect(await auth.hasCredentials('api-only'), isFalse);
      expect(secure.data, before);
    });

    test('initialization and removal affect only that subscription', () async {
      secure.data['llm_key_first'] = 'first-api-key';
      secure.data['llm_key_second'] = 'second-api-key';
      final first = auth.session('first', callbackMessage: 'Return to app');
      final second = auth.session('second', callbackMessage: 'Return to app');
      expect(first, isNot(same(second)));

      await first.initialize();
      await second.initialize();

      expect(first.errorCode, isNull);
      expect(second.errorCode, isNull);
      final firstKey = ChatGptProviderAuth.storageKey('first');
      final secondKey = ChatGptProviderAuth.storageKey('second');
      final firstRecord =
          jsonDecode(secure.data[firstKey]!) as Map<String, dynamic>;
      final secondRecord =
          jsonDecode(secure.data[secondKey]!) as Map<String, dynamic>;
      expect(firstRecord['ext_agent_host_id'], isNotEmpty);
      expect(secondRecord['ext_agent_host_id'], isNotEmpty);
      expect(
        firstRecord['ext_agent_host_id'],
        isNot(secondRecord['ext_agent_host_id']),
      );
      expect(await auth.hasCredentials('first'), isFalse);
      final remaining = Map<String, String>.of(secure.data)..remove(firstKey);

      await auth.remove('first');

      expect(secure.data, remaining);
      expect(await auth.hasCredentials('first'), isFalse);
      expect(auth.session('second'), same(second));
    });

    test('secure storage read failure propagates instead of ready', () async {
      store(_credentials());
      secure.failingReads.add(ChatGptProviderAuth.storageKey('first'));

      await expectLater(auth.hasCredentials('first'), throwsStateError);
    });
  });

  test(
    'removal waits for an in-flight write before clearing the record',
    () async {
      final firstKey = ChatGptProviderAuth.storageKey('first');
      final secondKey = ChatGptProviderAuth.storageKey('second');
      final secure = _DelayedSecureKVStorage(firstKey);
      secure.memory.data[secondKey] = jsonEncode(_credentials());
      secure.memory.data['llm_key_first'] = 'first-api-key';
      final remaining = Map<String, String>.of(secure.memory.data);
      final auth = ChatGptProviderAuth(secure);
      final session = auth.session('first', callbackMessage: 'Return to app');
      final initializing = session.initialize();
      Future<void>? removing;
      addTearDown(() async {
        secure.releaseWrite();
        await initializing;
        await removing;
        auth.dispose();
      });
      await secure.writeStarted.future.timeout(const Duration(seconds: 5));

      var removed = false;
      removing = auth.remove('first').then((_) {
        removed = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(removed, isFalse);
      expect(secure.operations, isEmpty);
      expect(await auth.hasCredentials('first'), isFalse);
      expect(
        () => auth.session('first'),
        throwsA(
          isA<ChatGptException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );

      secure.releaseWrite();
      await initializing;
      await removing;

      expect(removed, isTrue);
      expect(secure.operations, ['set:$firstKey', 'remove:$firstKey']);
      expect(secure.memory.data, remaining);
      expect(await auth.hasCredentials('first'), isFalse);
    },
  );
}

class _DelayedSecureKVStorage implements ISecureKVStorage {
  _DelayedSecureKVStorage(this.delayedKey);

  final String delayedKey;
  final memory = MemorySecureKVStorage();
  final writeStarted = Completer<void>();
  final _release = Completer<void>();
  final operations = <String>[];

  void releaseWrite() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> init() => memory.init();

  @override
  Future<String?> get(String key) => memory.get(key);

  @override
  Future<void> set(String key, String value) async {
    if (key == delayedKey) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await _release.future;
    }
    await memory.set(key, value);
    operations.add('set:$key');
  }

  @override
  Future<void> remove(String key) async {
    await memory.remove(key);
    operations.add('remove:$key');
  }

  @override
  Future<void> clear() => memory.clear();
}
