import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moodiary_chatgpt/moodiary_chatgpt.dart';

final now = DateTime.utc(2026, 10, 6);
Map<String, dynamic> record({bool expired = false}) => {
  'ext_agent_host_id': 'urn:uuid:test-host',
  'client_id': 'oaiapp_test',
  'subject': 'test-user',
  'access_token': 'old-access',
  'refresh_token': 'old-refresh',
  'expires_at': now
      .add(Duration(minutes: expired ? -1 : 60))
      .millisecondsSinceEpoch,
  'scopes': ['chatgpt.tokens.use.direct'],
};

http.Response refreshed() => http.Response(
  jsonEncode({
    'access_token': 'new-access',
    'refresh_token': 'new-refresh',
    'token_type': 'Bearer',
    'expires_in': 3600,
    'scope': 'chatgpt.tokens.use.direct',
  }),
  200,
);

void main() {
  test('fresh credentials resolve without a network request', () async {
    final session = ChatGptSession(
      readState: () async => jsonEncode(record()),
      writeState: (_) async => fail('No write expected'),
      now: () => now,
      clientFactory: () => MockClient((_) async => fail('No network expected')),
    );
    addTearDown(session.close);
    expect(await session.validAccessToken(), 'old-access');
    expect(session.signedIn, isTrue);
  });

  test(
    'concurrent callers share one rotating refresh and persist it first',
    () async {
      var saved = jsonEncode(record(expired: true));
      var requests = 0;
      final response = Completer<http.Response>();
      final started = Completer<void>();
      final session = ChatGptSession(
        readState: () async => saved,
        writeState: (value) async => saved = value,
        now: () => now,
        clientFactory: () => MockClient((request) {
          requests++;
          expect(request.url.host, 'auth.openai.com');
          expect(request.bodyFields['refresh_token'], 'old-refresh');
          expect(request.followRedirects, isFalse);
          started.complete();
          return response.future;
        }),
      );
      addTearDown(session.close);
      final first = session.validAccessToken();
      await started.future;
      final second = session.validAccessToken();
      response.complete(refreshed());
      expect(await Future.wait([first, second]), ['new-access', 'new-access']);
      expect(requests, 1);
      expect(jsonDecode(saved)['refresh_token'], 'new-refresh');
    },
  );

  test(
    'invalid refresh removes credentials and exposes only a safe error',
    () async {
      var saved = jsonEncode(record(expired: true));
      final session = ChatGptSession(
        readState: () async => saved,
        writeState: (value) async => saved = value,
        now: () => now,
        clientFactory: () => MockClient(
          (_) async => http.Response(
            '{"error":{"code":"invalid_grant","message":"secret response"}}',
            400,
          ),
        ),
      );
      addTearDown(session.close);
      await expectLater(
        session.validAccessToken(),
        throwsA(
          isA<ChatGptException>().having(
            (e) => e.toString(),
            'safe code',
            'invalid_grant',
          ),
        ),
      );
      expect(session.signedIn, isFalse);
      expect(jsonDecode(saved)['refresh_token'], isNull);
    },
  );

  test('storage failure does not return a token as successful', () async {
    final session = ChatGptSession(
      readState: () async => jsonEncode(record(expired: true)),
      writeState: (_) async => throw StateError('private storage detail'),
      now: () => now,
      clientFactory: () => MockClient((_) async => refreshed()),
    );
    addTearDown(session.close);
    await expectLater(
      session.validAccessToken(),
      throwsA(
        isA<ChatGptException>().having((e) => e.code, 'code', 'storage_error'),
      ),
    );
  });

  test(
    'close drains a pending secure write before the owner deletes it',
    () async {
      String? saved = jsonEncode(record(expired: true));
      final writing = Completer<void>();
      final releaseWrite = Completer<void>();
      final session = ChatGptSession(
        readState: () async => saved,
        writeState: (value) async {
          writing.complete();
          await releaseWrite.future;
          saved = value;
        },
        now: () => now,
        clientFactory: () => MockClient((_) async => refreshed()),
      );
      final token = session.validAccessToken();
      final failed = expectLater(
        token,
        throwsA(
          isA<ChatGptException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await writing.future;
      var closed = false;
      final closing = session.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      releaseWrite.complete();
      await closing;
      await failed;
      saved = null;
      await Future<void>.delayed(Duration.zero);
      expect(saved, isNull);
      await expectLater(
        session.validAccessToken(),
        throwsA(isA<ChatGptException>()),
      );
    },
  );

  test(
    'retry persists the rotated credential without exchanging it again',
    () async {
      var saved = jsonEncode(record(expired: true));
      var writes = 0;
      var requests = 0;
      final session = ChatGptSession(
        readState: () async => saved,
        writeState: (value) async {
          if (++writes == 1) throw StateError('temporary storage failure');
          saved = value;
        },
        now: () => now,
        clientFactory: () => MockClient((_) async {
          requests++;
          return refreshed();
        }),
      );
      addTearDown(session.close);
      await expectLater(
        session.validAccessToken(),
        throwsA(isA<ChatGptException>()),
      );
      expect(await session.validAccessToken(), 'new-access');
      expect(requests, 1);
      expect(writes, 2);
      expect(jsonDecode(saved)['refresh_token'], 'new-refresh');
    },
  );
}
