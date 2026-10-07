import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:selume_chatgpt_probe/src/probe_controller.dart';
import 'package:selume_chatgpt_probe/src/protocol.dart';

Matcher _error(String code) =>
    isA<ProbeException>().having((error) => error.code, 'code', code);

Uri _callback(Uri authorization, {Map<String, String>? query}) =>
    Uri.parse(authorization.queryParameters['redirect_uri']!).replace(
      queryParameters:
          query ??
          {
            'state': authorization.queryParameters['state']!,
            'client_id': 'oaiapp_test',
            'code': 'test-authorization-code',
          },
    );

class _Fixture {
  String? saved;
  DateTime now = DateTime.utc(2026, 10, 6);
  Uri? authorization;
  final launched = Completer<Uri>();
  final requests = <http.Request>[];
  final writes = <String>[];
  Future<void> Function(String)? beforeWrite;
  int launches = 0;

  int get exchanges => requests
      .where((request) => request.url.path == '/api/accounts/oauth/token')
      .length;

  ProbeController controller() => ProbeController(
    readState: () async => saved,
    writeState: (value) async {
      await beforeWrite?.call(value);
      saved = value;
      writes.add(value);
    },
    now: () => now,
    verifySignature: (_, _, _) async => true,
    launchBrowser: (uri) async {
      authorization = uri;
      launches++;
      final pending = (jsonDecode(saved!) as Map)['pending_sign_in'] as Map;
      expect(pending['state'], uri.queryParameters['state']);
      expect(pending['nonce'], uri.queryParameters['nonce']);
      expect(
        pkceChallenge(pending['verifier'] as String),
        uri.queryParameters['code_challenge'],
      );
      if (!launched.isCompleted) launched.complete(uri);
      return true;
    },
    clientFactory: () => MockClient((request) async {
      requests.add(request);
      expect(request.url.host, anyOf('auth.openai.com', 'api.openai.com'));
      if (request.url.path == '/api/accounts/oauth/token') {
        expect(
          (jsonDecode(saved!) as Map).containsKey('pending_sign_in'),
          isFalse,
        );
        expect(request.bodyFields['code'], 'test-authorization-code');
        expect(
          request.bodyFields['redirect_uri'],
          authorization!.queryParameters['redirect_uri'],
        );
        expect(
          pkceChallenge(request.bodyFields['code_verifier']!),
          authorization!.queryParameters['code_challenge'],
        );
        String encode(Object value) => base64Url
            .encode(utf8.encode(jsonEncode(value)))
            .replaceAll('=', '');
        final jwt =
            '${encode({'alg': 'RS256', 'kid': 'test'})}.'
            '${encode({'iss': 'https://auth.openai.com', 'aud': 'oaiapp_test', 'sub': 'test-subject', 'nonce': authorization!.queryParameters['nonce'], 'iat': now.millisecondsSinceEpoch ~/ 1000, 'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.c2ln';
        return _json({
          'id_token': jwt,
          'access_token': 'test-access',
          'refresh_token': 'test-refresh',
          'token_type': 'Bearer',
          'expires_in': 3600,
          'scope': 'openid chatgpt.tokens.use.direct',
        });
      }
      if (request.url.path == '/.well-known/openid-configuration') {
        return _json({
          'issuer': 'https://auth.openai.com',
          'jwks_uri': 'https://auth.openai.com/jwks',
          'revocation_endpoint': 'https://auth.openai.com/revoke',
        });
      }
      if (request.url.path == '/jwks') {
        return _json({
          'keys': [
            {'kid': 'test', 'kty': 'RSA', 'n': 'bm90LXJlYWw', 'e': 'AQAB'},
          ],
        });
      }
      if (request.url.path == '/revoke') return _json({});
      fail('Unexpected endpoint');
    }),
  );

  http.Response _json(Object value) => http.Response(jsonEncode(value), 200);
}

void main() {
  test(
    'manual callback completes the active request without fetching localhost',
    () async {
      final fixture = _Fixture();
      final controller = fixture.controller();
      addTearDown(controller.dispose);
      final attempt = controller.signIn();
      final authorization = await fixture.launched.future;
      expect(controller.canPasteCallback, isTrue);
      await controller.submitCallbackUrl(_callback(authorization).toString());
      await attempt;
      expect(controller.errorCode, isNull);
      expect(controller.signedIn, isTrue);
      expect(controller.canPasteCallback, isFalse);
      expect(controller.hasPendingSignIn, isFalse);
      expect(fixture.exchanges, 1);
      expect(
        fixture.writes.any(
          (value) => value.contains('test-authorization-code'),
        ),
        isFalse,
      );
      await expectLater(
        controller.submitCallbackUrl(_callback(authorization).toString()),
        throwsA(_error('no_pending_authorization')),
      );
      expect(fixture.exchanges, 1);
    },
  );

  test('process restart restores the same PKCE and nonce without binding the old port', () async {
    final fixture = _Fixture();
    final first = fixture.controller();
    final attempt = first.signIn();
    final authorization = await fixture.launched.future;
    first.dispose();
    await attempt;
    expect(
      (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
      isTrue,
    );
    final redirect = _callback(authorization);
    final otherServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      redirect.port,
    );
    var localhostRequests = 0;
    otherServer.listen((request) {
      localhostRequests++;
      request.response.statusCode = 404;
      unawaited(request.response.close());
    });
    addTearDown(() => otherServer.close(force: true));
    final restored = fixture.controller();
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.phase, 'pending_authorization');
    expect(restored.canPasteCallback, isTrue);
    await restored.submitCallbackUrl(redirect.toString());
    expect(restored.errorCode, isNull);
    expect(restored.signedIn, isTrue);
    expect(fixture.exchanges, 1);
    expect(localhostRequests, 0);
    expect(fixture.launches, 1);
  });

  test(
    'invalid pasted URLs leave the current request usable and send nothing',
    () async {
      final fixture = _Fixture();
      final controller = fixture.controller();
      addTearDown(controller.dispose);
      final attempt = controller.signIn();
      final authorization = await fixture.launched.future;
      final callback = _callback(authorization);
      final invalid = <String>[
        authorization.toString(),
        callback
            .replace(port: callback.port == 65535 ? 65534 : callback.port + 1)
            .toString(),
        callback.replace(scheme: 'https').toString(),
        callback.replace(host: 'localhost').toString(),
        callback.replace(userInfo: 'user').toString(),
        callback.replace(fragment: 'fragment').toString(),
        callback.replace(path: '/wrong').toString(),
        '/auth/callback?${callback.query}',
        callback
            .replace(
              queryParameters: {...callback.queryParameters, 'state': 'wrong'},
            )
            .toString(),
        '$callback&state=duplicate',
        'a' * (20 * 1024 + 1),
      ];
      for (final value in invalid) {
        await expectLater(
          controller.submitCallbackUrl(value),
          throwsA(isA<ProbeException>()),
        );
        expect(controller.canPasteCallback, isTrue);
        expect(fixture.requests, isEmpty);
        expect(
          (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
          isTrue,
        );
      }
      await controller.submitCallbackUrl(callback.toString());
      await attempt;
      expect(controller.signedIn, isTrue);
    },
  );

  test('expired and absent requests cannot be redeemed', () async {
    final fixture = _Fixture();
    final controller = fixture.controller();
    addTearDown(controller.dispose);
    await controller.initialize();
    await expectLater(
      controller.submitCallbackUrl('http://127.0.0.1:1/auth/callback?code=x'),
      throwsA(_error('no_pending_authorization')),
    );
    final attempt = controller.signIn();
    final authorization = await fixture.launched.future;
    fixture.now = fixture.now.add(const Duration(minutes: 16));
    expect(controller.canPasteCallback, isFalse);
    await expectLater(
      controller.submitCallbackUrl(_callback(authorization).toString()),
      throwsA(_error('authorization_timeout')),
    );
    await attempt;
    expect(controller.errorCode, 'authorization_timeout');
    expect(fixture.requests, isEmpty);
    expect(
      (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
      isFalse,
    );
  });

  test('cancel removes pending data and rejects the old callback', () async {
    final fixture = _Fixture();
    final controller = fixture.controller();
    addTearDown(controller.dispose);
    final attempt = controller.signIn();
    final authorization = await fixture.launched.future;
    await controller.cancelSignIn();
    await attempt;
    expect(controller.errorCode, 'cancelled');
    expect(
      (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
      isFalse,
    );
    await expectLater(
      controller.submitCallbackUrl(_callback(authorization).toString()),
      throwsA(_error('no_pending_authorization')),
    );
    expect(fixture.requests, isEmpty);
  });

  test(
    'cancel during a pending storage write cannot resurrect that request',
    () async {
      final fixture = _Fixture();
      final started = Completer<void>();
      final release = Completer<void>();
      fixture.beforeWrite = (value) async {
        if ((jsonDecode(value) as Map).containsKey('pending_sign_in')) {
          started.complete();
          await release.future;
        }
      };
      final controller = fixture.controller();
      addTearDown(controller.dispose);
      final attempt = controller.signIn();
      await started.future;
      final cancel = controller.cancelSignIn();
      release.complete();
      await cancel;
      await attempt;
      expect(
        (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
        isFalse,
      );
      expect(fixture.launches, 0);
      expect(fixture.requests, isEmpty);
    },
  );

  test('failed pending removal never redeems a code', () async {
    final fixture = _Fixture();
    final controller = fixture.controller();
    addTearDown(controller.dispose);
    final attempt = controller.signIn();
    final authorization = await fixture.launched.future;
    fixture.beforeWrite = (_) async =>
        throw StateError('simulated storage failure');
    await controller.submitCallbackUrl(_callback(authorization).toString());
    await attempt;
    expect(controller.errorCode, 'storage_error');
    expect(controller.canPasteCallback, isFalse);
    expect(fixture.requests, isEmpty);
  });

  test('cancel preserves a concurrent consumption storage failure', () async {
    final fixture = _Fixture();
    final controller = fixture.controller();
    addTearDown(controller.dispose);
    final attempt = controller.signIn();
    final callback = _callback(await fixture.launched.future);
    final removing = Completer<void>();
    final release = Completer<void>();
    fixture.beforeWrite = (_) async {
      removing.complete();
      await release.future;
      throw StateError('simulated storage failure');
    };
    final submit = controller.submitCallbackUrl(callback.toString());
    await removing.future;
    final cancel = controller.cancelSignIn();
    release.complete();
    await Future.wait([attempt, submit, cancel]);
    expect(controller.errorCode, 'storage_error');
    expect(controller.phase, 'failed');
    expect(controller.busy, isFalse);
    expect(controller.canPasteCallback, isFalse);
    expect(fixture.requests, isEmpty);
  });

  test('cancel reports failure when pending data cannot be removed', () async {
    final fixture = _Fixture();
    final controller = fixture.controller();
    addTearDown(controller.dispose);
    final attempt = controller.signIn();
    await fixture.launched.future;
    fixture.beforeWrite = (_) async =>
        throw StateError('simulated storage failure');
    await controller.cancelSignIn();
    await attempt;
    expect(controller.errorCode, 'storage_error');
    expect(controller.phase, 'failed');
    expect(controller.canPasteCallback, isFalse);
    expect(fixture.requests, isEmpty);
  });

  test(
    'a validated OAuth denial ends pending authorization without any request',
    () async {
      final fixture = _Fixture();
      final controller = fixture.controller();
      addTearDown(controller.dispose);
      final attempt = controller.signIn();
      final authorization = await fixture.launched.future;
      await controller.submitCallbackUrl(
        _callback(
          authorization,
          query: {
            'state': authorization.queryParameters['state']!,
            'error': 'access_denied',
          },
        ).toString(),
      );
      await attempt;
      expect(controller.errorCode, 'oauth_access_denied');
      expect(
        (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
        isFalse,
      );
      expect(fixture.requests, isEmpty);
    },
  );

  test('automatic and manual callbacks race without redeeming twice', () async {
    final fixture = _Fixture();
    final controller = fixture.controller();
    addTearDown(controller.dispose);
    final attempt = controller.signIn();
    final callback = _callback(await fixture.launched.future);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(callback);
    final automatic = () async {
      try {
        final response = await request.close();
        await response.drain<void>();
      } on SocketException {
        // The winning manual callback can close the listener first.
      } on HttpException {
        // The winning manual callback can close an accepted connection.
      }
    }();
    final manual = () async {
      try {
        await controller.submitCallbackUrl(callback.toString());
      } on ProbeException catch (error) {
        expect(error.code, 'no_pending_authorization');
      }
    }();
    await Future.wait([automatic, manual, attempt]);
    expect(controller.errorCode, isNull);
    expect(controller.signedIn, isTrue);
    expect(fixture.exchanges, 1);
  });

  test(
    'restored cancellation blocks a new login until its removal finishes',
    () async {
      final fixture = _Fixture();
      final first = fixture.controller();
      final original = first.signIn();
      await fixture.launched.future;
      first.dispose();
      await original;
      final restored = fixture.controller();
      addTearDown(restored.dispose);
      await restored.initialize();
      final removing = Completer<void>();
      final release = Completer<void>();
      fixture.beforeWrite = (_) async {
        removing.complete();
        await release.future;
      };
      final cancel = restored.cancelSignIn();
      await removing.future;
      expect(restored.busy, isTrue);
      await restored.signIn();
      expect(fixture.launches, 1);
      release.complete();
      await cancel;
      expect(
        (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
        isFalse,
      );
      expect(restored.busy, isFalse);
      expect(fixture.requests, isEmpty);
    },
  );

  for (final change in [
    'expired',
    'clock_rollback',
    'long_ttl',
    'malformed',
    'malformed_port',
  ]) {
    test('restart rejects and removes $change pending data', () async {
      final fixture = _Fixture();
      final first = fixture.controller();
      final original = first.signIn();
      await fixture.launched.future;
      first.dispose();
      await original;
      final record = jsonDecode(fixture.saved!) as Map<String, dynamic>;
      final pending = record['pending_sign_in'] as Map<String, dynamic>;
      if (change == 'expired')
        fixture.now = fixture.now.add(const Duration(minutes: 16));
      if (change == 'clock_rollback')
        fixture.now = fixture.now.subtract(const Duration(seconds: 1));
      if (change == 'long_ttl')
        pending['expires_at'] =
            (pending['created_at'] as int) +
            const Duration(hours: 1).inMilliseconds;
      if (change == 'malformed') pending['nonce'] = '';
      if (change == 'malformed_port')
        pending['redirect_uri'] = 'http://127.0.0.1:invalid/auth/callback';
      fixture.saved = jsonEncode(record);
      final restored = fixture.controller();
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(
        restored.errorCode,
        anyOf('authorization_timeout', 'pending_authorization_invalid'),
      );
      expect(restored.canPasteCallback, isFalse);
      expect(
        (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
        isFalse,
      );
      expect(fixture.requests, isEmpty);
    });
  }

  test('sign-out also removes an unconsumed restored authorization', () async {
    final fixture = _Fixture();
    final first = fixture.controller();
    final attempt = first.signIn();
    final callback = _callback(await fixture.launched.future);
    first.dispose();
    await attempt;
    final restored = fixture.controller();
    addTearDown(restored.dispose);
    await restored.initialize();
    await restored.signOut();
    expect(restored.errorCode, isNull);
    expect(restored.hasPendingSignIn, isFalse);
    expect(
      (jsonDecode(fixture.saved!) as Map).containsKey('pending_sign_in'),
      isFalse,
    );
    await expectLater(
      restored.submitCallbackUrl(callback.toString()),
      throwsA(_error('no_pending_authorization')),
    );
    expect(fixture.exchanges, 0);
  });
}
