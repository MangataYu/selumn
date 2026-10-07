import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:selume_chatgpt_probe/src/probe_controller.dart';
import 'package:selume_chatgpt_probe/src/protocol.dart';

final _now = DateTime.utc(2026, 10, 6);

Map<String, dynamic> _savedSession({bool permission = true}) => {
  'ext_agent_host_id': 'urn:uuid:test-host',
  'client_id': 'oaiapp_test',
  'issuer': 'https://auth.openai.com',
  'subject': 'test-user',
  'email': 'test@example.invalid',
  'access_token': 'test-access',
  'refresh_token': 'test-refresh',
  'id_token': 'test-id',
  'nonce': 'test-nonce',
  'token_type': 'Bearer',
  'expires_at': _now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
  'scopes': ['openid', if (permission) 'chatgpt.tokens.use.direct'],
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', 'x-request-id': 'req_test'},
);

http.Response _models() => _json({
  'models': [
    {'slug': 'hidden', 'display_name': 'Hidden', 'visibility': 'hide'},
    {
      'slug': 'available-model',
      'display_name': 'Available model',
      'visibility': 'list',
    },
  ],
});

http.Response _stream({bool completed = true}) => http.Response(
  'data: {"type":"response.output_text.delta","delta":"OK"}\n\n'
  '${completed ? 'data: {"type":"response.completed","response":{"status":"completed"}}\n\n' : ''}',
  200,
  headers: {'content-type': 'text/event-stream', 'x-request-id': 'req_test'},
);

MockClient _missingContentTypeClient(
  Stream<List<int>> body, {
  required void Function() onResponse,
}) => MockClient.streaming((request, requestBody) async {
  final sentBytes = await requestBody.toBytes();
  if (request.url.path == '/v1/models') {
    final models = _models();
    return http.StreamedResponse(
      Stream.value(models.bodyBytes),
      models.statusCode,
      headers: models.headers,
    );
  }
  expect(request.url.path, '/v1/responses');
  expect(request.method, 'POST');
  expect(request.followRedirects, isFalse);
  expect(jsonDecode(utf8.decode(sentBytes))['stream'], isTrue);
  onResponse();
  return http.StreamedResponse(
    body,
    200,
    headers: {'x-request-id': 'req_test'},
  );
});

Future<void> _expectResponseDiagnosticsReset(ProbeController controller) async {
  await controller.loadModels();
  expect(controller.errorCode, isNull);
  expect(controller.errorHttpStatus, isNull);
  expect(controller.errorRequestId, isNull);
  expect(controller.responseFormat, isNull);
  expect(controller.responseBodyFormat, isNull);
  expect(controller.responseBytes, isNull);
  expect(controller.failedPhase, isNull);
  expect(controller.failedElapsedSeconds, isNull);
}

String _jwt(String nonce, {String subject = 'test-user'}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'RS256', 'kid': 'test-key'})}.'
      '${encode({'iss': 'https://auth.openai.com', 'aud': 'oaiapp_test', 'sub': subject, 'email': 'test@example.invalid', 'iat': _now.millisecondsSinceEpoch ~/ 1000, 'exp': _now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000, 'nonce': nonce})}.c2ln';
}

Future<String> _returnCallback(
  Uri authorization, {
  bool wrongState = false,
}) async {
  final callback = Uri.parse(authorization.queryParameters['redirect_uri']!)
      .replace(
        queryParameters: {
          'state': wrongState
              ? 'wrong-state'
              : authorization.queryParameters['state']!,
          'client_id': 'oaiapp_test',
          'code': 'test-code',
        },
      );
  final client = HttpClient();
  try {
    final request = await client.getUrl(callback);
    final response = await request.close();
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}

void main() {
  test(
    'new sign-in handles a callback after browser launch has returned',
    () async {
      String? saved;
      Uri? authorization;
      final launched = Completer<Uri>();
      final requests = <http.Request>[];
      String? callbackPage;
      final controller = ProbeController(
        callbackMessage: 'Return <safe> & ready',
        readState: () async => saved,
        writeState: (value) async {
          saved = value;
        },
        now: () => _now,
        verifySignature: (_, _, _) async => true,
        launchBrowser: (uri) async {
          authorization = uri;
          launched.complete(uri);
          return true;
        },
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/accounts/oauth/token') {
            final form = request.bodyFields;
            expect(form['client_id'], 'oaiapp_test');
            expect(form['client_secret'], isNull);
            expect(
              form['redirect_uri'],
              authorization!.queryParameters['redirect_uri'],
            );
            expect(
              pkceChallenge(form['code_verifier']!),
              authorization!.queryParameters['code_challenge'],
            );
            return _json({
              'access_token': 'test-access',
              'refresh_token': 'test-refresh',
              'id_token': _jwt(authorization!.queryParameters['nonce']!),
              'token_type': 'Bearer',
              'expires_in': 3600,
              'scope': 'openid chatgpt.tokens.use.direct',
            });
          }
          if (request.url.path == '/.well-known/openid-configuration') {
            return _json({
              'issuer': 'https://auth.openai.com',
              'jwks_uri': 'https://auth.openai.com/jwks',
            });
          }
          if (request.url.path == '/jwks')
            return _json({
              'keys': [
                {
                  'kid': 'test-key',
                  'kty': 'RSA',
                  'n': 'bm90LXJlYWw',
                  'e': 'AQAB',
                },
              ],
            });
          fail('Unexpected endpoint');
        }),
      );
      addTearDown(controller.dispose);
      final attempt = controller.signIn();
      final launchedUri = await launched.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.phase, 'waiting_browser');
      callbackPage = await _returnCallback(launchedUri);
      await attempt;
      expect(controller.errorCode, isNull);
      expect(controller.signedIn, isTrue);
      expect(controller.planEnabled, isTrue);
      expect(authorization!.host, 'auth.openai.com');
      expect(
        authorization!.queryParameters['client_id'],
        'dynamic_agent_client',
      );
      expect(
        authorization!.queryParameters['agent_name_hint'],
        'Selume ChatGPT Probe',
      );
      expect(
        authorization!.queryParameters['scope'],
        contains('chatgpt.tokens.use.direct'),
      );
      expect(jsonDecode(saved!)['client_id'], 'oaiapp_test');
      expect(callbackPage, contains('Return &lt;safe&gt; &amp; ready'));
      expect(callbackPage, isNot(contains('test-code')));
      expect(requests.every((r) => !r.followRedirects), isTrue);
      expect(
        controller.steps.where((s) => s.code == 'identity').single.passed,
        isTrue,
      );
    },
  );

  test(
    'authorization deadline reports its stage and closes the listener',
    () async {
      final launched = Completer<Uri>();
      var requests = 0;
      final controller = ProbeController(
        signInTimeout: const Duration(milliseconds: 30),
        readState: () async => null,
        writeState: (_) async {},
        launchBrowser: (uri) async {
          launched.complete(uri);
          return true;
        },
        clientFactory: () => MockClient((_) async {
          requests++;
          return _json({});
        }),
      );
      addTearDown(controller.dispose);
      final attempt = controller.signIn();
      final authorization = await launched.future;
      await attempt;
      expect(controller.errorCode, 'authorization_timeout');
      expect(controller.failedPhase, 'waiting_browser');
      expect(controller.failedElapsedSeconds, isNonNegative);
      expect(controller.busy, isFalse);
      expect(controller.signedIn, isFalse);
      expect(requests, 0);
      final redirect = Uri.parse(
        authorization.queryParameters['redirect_uri']!,
      );
      await expectLater(
        Socket.connect(
          redirect.host,
          redirect.port,
          timeout: const Duration(seconds: 1),
        ).then((socket) => socket.destroy()),
        throwsA(isA<SocketException>()),
      );
      await controller.initialize();
      expect(controller.failedPhase, isNull);
      expect(controller.failedElapsedSeconds, isNull);
      expect(controller.errorCode, isNull);
    },
  );

  test(
    'browser launch timeout is distinct from authorization timeout',
    () async {
      final controller = ProbeController(
        requestTimeout: const Duration(milliseconds: 30),
        readState: () async => null,
        writeState: (_) async {},
        launchBrowser: (_) => Completer<bool>().future,
        clientFactory: () => MockClient((_) async => _json({})),
      );
      addTearDown(controller.dispose);
      await controller.signIn();
      expect(controller.errorCode, 'browser_launch_timeout');
      expect(controller.failedPhase, 'waiting_browser');
      expect(controller.busy, isFalse);
    },
  );

  for (final stalledPath in ['/api/accounts/oauth/token', '/jwks']) {
    test(
      'sign-in preserves the failed stage when $stalledPath times out',
      () async {
        final launched = Completer<Uri>();
        Uri? authorization;
        final controller = ProbeController(
          requestTimeout: const Duration(milliseconds: 30),
          readState: () async => null,
          writeState: (_) async {},
          now: () => _now,
          launchBrowser: (uri) async {
            authorization = uri;
            launched.complete(uri);
            return true;
          },
          clientFactory: () => MockClient((request) async {
            if (request.url.path == stalledPath) {
              return Completer<http.Response>().future;
            }
            if (request.url.path == '/api/accounts/oauth/token') {
              return _json({
                'access_token': 'test-access',
                'refresh_token': 'test-refresh',
                'id_token': _jwt(authorization!.queryParameters['nonce']!),
                'token_type': 'Bearer',
                'expires_in': 3600,
                'scope': 'openid chatgpt.tokens.use.direct',
              });
            }
            if (request.url.path == '/.well-known/openid-configuration') {
              return _json({
                'issuer': 'https://auth.openai.com',
                'jwks_uri': 'https://auth.openai.com/jwks',
              });
            }
            fail('Unexpected endpoint');
          }),
        );
        addTearDown(controller.dispose);
        final attempt = controller.signIn();
        await _returnCallback(await launched.future);
        await attempt;
        expect(controller.errorCode, 'timeout');
        expect(
          controller.failedPhase,
          stalledPath == '/jwks' ? 'validating' : 'exchanging',
        );
        expect(
          controller.steps
              .where((step) => step.code == 'callback')
              .single
              .passed,
          isTrue,
        );
        expect(controller.signedIn, isFalse);
        expect(controller.busy, isFalse);
      },
    );
  }

  test('state mismatch does not redeem a code', () async {
    var requests = 0;
    final controller = ProbeController(
      readState: () async => null,
      writeState: (_) async {},
      launchBrowser: (uri) async {
        await _returnCallback(uri, wrongState: true);
        return true;
      },
      clientFactory: () => MockClient((_) async {
        requests++;
        return _json({});
      }),
    );
    addTearDown(controller.dispose);
    await controller.signIn();
    expect(controller.errorCode, 'state_mismatch');
    expect(controller.signedIn, isFalse);
    expect(requests, 0);
  });

  test('cancel closes the active authorization attempt', () async {
    final launched = Completer<void>();
    final controller = ProbeController(
      readState: () async => null,
      writeState: (_) async {},
      launchBrowser: (_) async {
        launched.complete();
        return true;
      },
      clientFactory: () => MockClient((_) async => _json({})),
    );
    addTearDown(controller.dispose);
    final attempt = controller.signIn();
    await launched.future;
    await controller.cancelSignIn();
    await attempt;
    expect(controller.busy, isFalse);
    expect(controller.errorCode, 'cancelled');
    expect(controller.signedIn, isFalse);
  });

  test('restores credentials and keeps account-specific model order without auto-selecting', () async {
    final controller = ProbeController(
      readState: () async => jsonEncode(_savedSession()),
      writeState: (_) async {},
      now: () => _now,
      clientFactory: () => MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-access');
        expect(request.followRedirects, isFalse);
        return _models();
      }),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.phase, 'restored');
    await controller.loadModels();
    expect(controller.errorCode, isNull);
    expect(controller.models.map((model) => model.id), ['available-model']);
    expect(controller.selectedModel, isNull);
  });

  test('identity-only grant cannot make model or inference requests', () async {
    var requests = 0;
    final controller = ProbeController(
      readState: () async => jsonEncode(_savedSession(permission: false)),
      writeState: (_) async {},
      now: () => _now,
      clientFactory: () => MockClient((_) async {
        requests++;
        return _json({});
      }),
    );
    addTearDown(controller.dispose);
    await controller.loadModels();
    expect(controller.errorCode, 'permission_missing');
    expect(controller.signedIn, isTrue);
    await controller.sendTest();
    expect(controller.errorCode, 'permission_missing');
    expect(requests, 0);
  });

  test(
    'refresh test uses rotating refresh grant and completed Responses event',
    () async {
      String? saved = jsonEncode(_savedSession());
      var refreshes = 0;
      var responses = 0;
      final controller = ProbeController(
        readState: () async => saved,
        writeState: (value) async {
          saved = value;
        },
        now: () => _now,
        clientFactory: () => MockClient((request) async {
          expect(request.followRedirects, isFalse);
          if (request.url.path == '/v1/models') return _models();
          if (request.url.path == '/api/accounts/oauth/token') {
            refreshes++;
            expect(request.bodyFields['grant_type'], 'refresh_token');
            expect(request.bodyFields['client_id'], 'oaiapp_test');
            expect(request.bodyFields['refresh_token'], 'test-refresh');
            expect(request.bodyFields.containsKey('scope'), isFalse);
            return _json({
              'access_token': 'refreshed-access',
              'refresh_token': 'rotated-refresh',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'id_token': 'new-unverified-id-without-nonce',
              'earliest_refresh_at': 1791244800,
            });
          }
          if (request.url.path == '/v1/responses') {
            responses++;
            expect(request.headers['Authorization'], 'Bearer refreshed-access');
            final body = jsonDecode(request.body);
            expect(body['model'], 'available-model');
            expect(body['store'], isFalse);
            expect(body['stream'], isTrue);
            expect(body['input'], [
              {'role': 'user', 'content': 'Reply with exactly OK.'},
            ]);
            return _stream();
          }
          fail('Unexpected endpoint');
        }),
      );
      addTearDown(controller.dispose);
      await controller.loadModels();
      controller.selectedModel = 'available-model';
      await controller.refreshAndTest();
      expect(controller.errorCode, isNull);
      expect(refreshes, 1);
      expect(responses, 1);
      expect(controller.reply, 'OK');
      expect(
        controller.steps.where((s) => s.code == 'response').single.passed,
        isTrue,
      );
      expect(jsonDecode(saved!)['refresh_token'], 'rotated-refresh');
      expect(jsonDecode(saved!)['id_token'], 'test-id');
      expect(jsonDecode(saved!)['earliest_refresh_at'], 1791244800);
      expect(
        jsonDecode(saved!)['scopes'],
        contains('chatgpt.tokens.use.direct'),
      );
    },
  );

  for (final responseCase
      in <
        ({
          String label,
          String? contentType,
          String body,
          String error,
          String format,
        })
      >[
        (
          label: 'HTML',
          contentType: 'text/html; charset=utf-8',
          body: '<html>private gateway page</html>',
          error: 'unexpected_html_response',
          format: 'html',
        ),
        (
          label: 'completed JSON response',
          contentType: 'Application/JSON; charset=utf-8',
          body: '{"object":"response","status":"completed","output_text":"OK"}',
          error: 'unexpected_json_response',
          format: 'json',
        ),
        (
          label: 'known structured JSON error',
          contentType: 'application/json',
          body: '{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"private details"}}',
          error: 'subscription_sharing_usage_limit_exceeded',
          format: 'json',
        ),
        (
          label: 'unknown structured JSON error',
          contentType: 'application/json',
          body: '{"error":{"code":"private_unknown_code","message":"private details"}}',
          error: 'unexpected_json_response',
          format: 'json',
        ),
        (
          label: 'unstructured JSON error',
          contentType: 'application/json',
          body: '{"error":"subscription_sharing_usage_limit_exceeded"}',
          error: 'unexpected_json_response',
          format: 'json',
        ),
        (
          label: 'malformed JSON',
          contentType: 'application/json',
          body: '{invalid',
          error: 'unexpected_json_response',
          format: 'json',
        ),
        (
          label: 'missing media type',
          contentType: null,
          body: 'OK',
          error: 'response_stream_incomplete',
          format: 'missing',
        ),
        (
          label: 'SSE body declared as HTML',
          contentType: 'text/html',
          body: _stream().body,
          error: 'unexpected_html_response',
          format: 'html',
        ),
        (
          label: 'SSE body declared as JSON',
          contentType: 'application/json',
          body: _stream().body,
          error: 'unexpected_json_response',
          format: 'json',
        ),
        (
          label: 'SSE body declared as plain text',
          contentType: 'text/plain',
          body: _stream().body,
          error: 'unexpected_response_content_type',
          format: 'text',
        ),
        (
          label: 'plain text',
          contentType: 'text/plain',
          body: 'OK',
          error: 'unexpected_response_content_type',
          format: 'text',
        ),
        (
          label: 'unknown media type',
          contentType: 'application/private-format; details=private',
          body: 'private body',
          error: 'unexpected_response_content_type',
          format: 'other',
        ),
      ]) {
    test(
      'HTTP 200 ${responseCase.label} stays failed with safe format diagnostics',
      () async {
        var responses = 0;
        final controller = ProbeController(
          readState: () async => jsonEncode(_savedSession()),
          writeState: (_) async {},
          now: () => _now,
          clientFactory: () => MockClient((request) async {
            if (request.url.path == '/v1/models') return _models();
            expect(request.url.path, '/v1/responses');
            responses++;
            return http.Response.bytes(
              utf8.encode(responseCase.body),
              200,
              headers: {
                if (responseCase.contentType != null)
                  'content-type': responseCase.contentType!,
                'x-request-id': 'req_test',
              },
            );
          }),
        );
        addTearDown(controller.dispose);
        await controller.loadModels();
        controller.selectedModel = 'available-model';
        await controller.sendTest();
        expect(controller.phase, 'failed');
        expect(controller.failedPhase, 'testing');
        expect(controller.errorCode, responseCase.error);
        expect(controller.responseFormat, responseCase.format);
        expect(controller.errorHttpStatus, 200);
        expect(controller.errorRequestId, 'req_test');
        expect(controller.reply, isEmpty);
        expect(
          controller.steps
              .where((step) => step.code == 'response')
              .single
              .passed,
          isFalse,
        );
        expect(responses, 1);
        await _expectResponseDiagnosticsReset(controller);
        expect(responses, 1);
      },
    );
  }

  test('missing Content-Type accepts only a completed SSE stream across single-byte chunks', () async {
    final bytes = utf8.encode(
      '\uFEFF: 探测\r\n\r\n'
      'event: response.output_text.delta\r\n'
      'data: {"type":"response.output_text.delta","delta":"OK"}\r\n\r\n'
      ': heartbeat\r\n\r\n'
      'event: response.completed\r\n'
      'data: {"type":"response.completed","response":{"status":"completed"}}\r\n\r\n',
    );
    var responses = 0;
    final controller = ProbeController(
      readState: () async => jsonEncode(_savedSession()),
      writeState: (_) async {},
      now: () => _now,
      clientFactory: () => _missingContentTypeClient(
        Stream.fromIterable(bytes.map((byte) => [byte])),
        onResponse: () => responses++,
      ),
    );
    addTearDown(controller.dispose);
    await controller.loadModels();
    controller.selectedModel = 'available-model';
    await controller.sendTest();
    expect(controller.errorCode, isNull);
    expect(controller.phase, 'completed');
    expect(controller.reply, 'OK');
    expect(controller.responseFormat, 'missing');
    expect(controller.responseBodyFormat, 'event_stream');
    // The final CR dispatches completion; the parser need not read its LF.
    expect(controller.responseBytes, bytes.length - 1);
    expect(
      controller.steps.where((step) => step.code == 'response').single.passed,
      isTrue,
    );
    expect(responses, 1);
    await _expectResponseDiagnosticsReset(controller);
    expect(responses, 1);
  });

  test(
    'completed SSE cancels an open source without waiting for EOF or retrying',
    () async {
      var responses = 0;
      var cancellations = 0;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancellations++;
        },
      );
      addTearDown(body.close);
      body.add(_stream().bodyBytes);
      final controller = ProbeController(
        readState: () async => jsonEncode(_savedSession()),
        writeState: (_) async {},
        now: () => _now,
        responseTimeout: const Duration(seconds: 5),
        clientFactory: () => _missingContentTypeClient(
          body.stream,
          onResponse: () => responses++,
        ),
      );
      addTearDown(controller.dispose);
      await controller.loadModels();
      controller.selectedModel = 'available-model';
      await controller.sendTest().timeout(const Duration(seconds: 1));
      expect(controller.errorCode, isNull);
      expect(controller.phase, 'completed');
      expect(controller.busy, isFalse);
      expect(controller.reply, 'OK');
      expect(
        controller.steps.where((step) => step.code == 'response').single.passed,
        isTrue,
      );
      expect(body.isClosed, isFalse);
      expect(body.hasListener, isFalse);
      expect(cancellations, 1);
      expect(responses, 1);
    },
  );

  for (final responseCase in [
    (
      label: 'partial SSE',
      body: 'data: {"type":"response.output_text.delta","delta":"OK"}\n\n',
      error: 'response_stream_incomplete',
      bodyFormat: 'event_stream',
      reply: 'OK',
    ),
    (
      label: 'failed SSE',
      body: 'data: {"type":"response.failed","response":{"status":"failed","error":{"code":"server_error","message":"private details"}}}\n\n',
      error: 'server_error',
      bodyFormat: 'event_stream',
      reply: '',
    ),
    (
      label: 'DONE sentinel without completion',
      body: 'data: [DONE]\n\n',
      error: 'response_stream_incomplete',
      bodyFormat: 'event_stream',
      reply: '',
    ),
    (
      label: 'completed event with incomplete response status',
      body: 'data: {"type":"response.completed","response":{"status":"incomplete"}}\n\n',
      error: 'response_incomplete',
      bodyFormat: 'event_stream',
      reply: '',
    ),
    (
      label: 'empty body',
      body: '',
      error: 'empty_response_body',
      bodyFormat: 'empty',
      reply: '',
    ),
    (
      label: 'HTML body',
      body: '\uFEFF \r\n<!DOCTYPE html><html>private gateway page</html>',
      error: 'unexpected_html_response',
      bodyFormat: 'html',
      reply: '',
    ),
    (
      label: 'JSON body claiming completion',
      body:
          ' \r\n{"object":"response","status":"completed","output_text":"OK"}',
      error: 'unexpected_json_response',
      bodyFormat: 'json',
      reply: '',
    ),
    (
      label: 'JSON array',
      body: '[{"type":"response.completed","response":{"status":"completed"}}]',
      error: 'unexpected_json_response',
      bodyFormat: 'json',
      reply: '',
    ),
    (
      label: 'plain OK text',
      body: 'OK',
      error: 'response_stream_incomplete',
      bodyFormat: 'unknown',
      reply: '',
    ),
  ]) {
    test(
      'missing Content-Type ${responseCase.label} fails once with body diagnostics',
      () async {
        var responses = 0;
        final bytes = utf8.encode(responseCase.body);
        final controller = ProbeController(
          readState: () async => jsonEncode(_savedSession()),
          writeState: (_) async {},
          now: () => _now,
          clientFactory: () => _missingContentTypeClient(
            Stream.fromIterable(bytes.map((byte) => [byte])),
            onResponse: () => responses++,
          ),
        );
        addTearDown(controller.dispose);
        await controller.loadModels();
        controller.selectedModel = 'available-model';
        await controller.sendTest();
        expect(controller.phase, 'failed');
        expect(controller.failedPhase, 'testing');
        expect(controller.errorCode, responseCase.error);
        expect(controller.errorHttpStatus, 200);
        expect(controller.errorRequestId, 'req_test');
        expect(controller.responseFormat, 'missing');
        expect(controller.responseBodyFormat, responseCase.bodyFormat);
        if (responseCase.bodyFormat == 'html' ||
            responseCase.bodyFormat == 'json') {
          expect(controller.responseBytes, inInclusiveRange(1, bytes.length));
        } else {
          expect(controller.responseBytes, bytes.length);
        }
        expect(controller.reply, responseCase.reply);
        expect(
          controller.steps
              .where((step) => step.code == 'response')
              .single
              .passed,
          isFalse,
        );
        expect(responses, 1);
        await _expectResponseDiagnosticsReset(controller);
        expect(responses, 1);
      },
    );
  }

  for (final timeout in [false, true]) {
    test(
      'missing Content-Type stream ${timeout ? 'timeout' : 'error'} preserves HTTP 200 and never retries',
      () async {
        var responses = 0;
        var cancellations = 0;
        final bytes = utf8.encode(
          'data: {"type":"response.output_text.delta","delta":"OK"}\n\n',
        );
        final body = StreamController<List<int>>(
          onCancel: () {
            cancellations++;
          },
        );
        addTearDown(body.close);
        body.add(bytes);
        if (!timeout) {
          body.addError(const SocketException('private transport details'));
          unawaited(body.close());
        }
        final controller = ProbeController(
          readState: () async => jsonEncode(_savedSession()),
          writeState: (_) async {},
          now: () => _now,
          responseTimeout: const Duration(milliseconds: 50),
          clientFactory: () => _missingContentTypeClient(
            body.stream,
            onResponse: () => responses++,
          ),
        );
        addTearDown(controller.dispose);
        await controller.loadModels();
        controller.selectedModel = 'available-model';
        await controller.sendTest().timeout(const Duration(seconds: 1));
        expect(controller.phase, 'failed');
        expect(controller.busy, isFalse);
        expect(controller.failedPhase, 'testing');
        expect(
          controller.errorCode,
          timeout ? 'response_timeout' : 'response_stream_interrupted',
        );
        expect(controller.errorHttpStatus, 200);
        expect(controller.errorRequestId, 'req_test');
        expect(controller.responseFormat, 'missing');
        expect(controller.responseBodyFormat, 'event_stream');
        expect(controller.responseBytes, bytes.length);
        expect(controller.reply, 'OK');
        expect(
          controller.steps
              .where((step) => step.code == 'response')
              .single
              .passed,
          isFalse,
        );
        expect(responses, 1);
        expect(cancellations, 1);
        expect(body.hasListener, isFalse);
        await _expectResponseDiagnosticsReset(controller);
        expect(responses, 1);
      },
    );
  }

  test(
    'oversized unexpected JSON remains bounded and never becomes success',
    () async {
      final controller = ProbeController(
        readState: () async => jsonEncode(_savedSession()),
        writeState: (_) async {},
        now: () => _now,
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/v1/models') return _models();
          return http.Response.bytes(
            List<int>.filled(2 * 1024 * 1024 + 1, 32),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(controller.dispose);
      await controller.loadModels();
      controller.selectedModel = 'available-model';
      await controller.sendTest();
      expect(controller.errorCode, 'unexpected_json_response');
      expect(controller.responseFormat, 'json');
      expect(controller.errorHttpStatus, 200);
      expect(controller.reply, isEmpty);
      expect(controller.phase, 'failed');
    },
  );

  test('a partial text stream never passes the response step', () async {
    final controller = ProbeController(
      readState: () async => jsonEncode(_savedSession()),
      writeState: (_) async {},
      now: () => _now,
      clientFactory: () => MockClient(
        (request) async => request.url.path == '/v1/models'
            ? _models()
            : _stream(completed: false),
      ),
    );
    addTearDown(controller.dispose);
    await controller.loadModels();
    controller.selectedModel = 'available-model';
    await controller.sendTest();
    expect(controller.errorCode, isNotNull);
    expect(
      controller.steps.where((s) => s.code == 'response').single.passed,
      isFalse,
    );
    expect(controller.errorHttpStatus, 200);
    expect(controller.errorRequestId, 'req_test');
    expect(controller.responseFormat, 'event_stream');
  });

  for (final explicitRefresh in [false, true]) {
    test(
      '${explicitRefresh ? 'refreshAndTest' : 'sendTest'} clears the previous success before a failed refresh',
      () async {
        var now = _now;
        var responses = 0;
        final controller = ProbeController(
          readState: () async => jsonEncode(_savedSession()),
          writeState: (_) async {},
          now: () => now,
          clientFactory: () => MockClient((request) async {
            if (request.url.path == '/v1/models') return _models();
            if (request.url.path == '/v1/responses') {
              responses++;
              return _stream();
            }
            if (request.url.path == '/api/accounts/oauth/token') {
              return _json({
                'error': {'code': 'server_error'},
              }, 503);
            }
            fail('Unexpected endpoint');
          }),
        );
        addTearDown(controller.dispose);
        await controller.loadModels();
        controller.selectedModel = 'available-model';
        await controller.sendTest();
        expect(controller.phase, 'completed');
        expect(controller.reply, 'OK');
        expect(
          controller.steps
              .where((step) => step.code == 'response')
              .single
              .passed,
          isTrue,
        );
        if (explicitRefresh) {
          await controller.refreshAndTest();
        } else {
          now = now.add(const Duration(hours: 2));
          await controller.sendTest();
        }
        expect(controller.phase, 'failed');
        expect(controller.failedPhase, 'refreshing');
        expect(controller.errorCode, 'server_error');
        expect(controller.reply, isEmpty);
        expect(
          controller.steps
              .where((step) => step.code == 'response')
              .single
              .passed,
          isFalse,
        );
        expect(responses, 1);
      },
    );
  }

  test('returning login rejects a different verified identity without replacing tokens', () async {
    var saved = jsonEncode(_savedSession());
    Uri? authorization;
    final controller = ProbeController(
      readState: () async => saved,
      writeState: (value) async {
        saved = value;
      },
      now: () => _now,
      verifySignature: (_, _, _) async => true,
      launchBrowser: (uri) async {
        authorization = uri;
        await _returnCallback(uri);
        return true;
      },
      clientFactory: () => MockClient((request) async {
        if (request.url.path == '/api/accounts/oauth/token') {
          return _json({
            'id_token': _jwt(
              authorization!.queryParameters['nonce']!,
              subject: 'other-user',
            ),
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'scope': 'chatgpt.tokens.use.direct',
          });
        }
        if (request.url.path == '/.well-known/openid-configuration') {
          return _json({
            'issuer': 'https://auth.openai.com',
            'jwks_uri': 'https://auth.openai.com/jwks',
          });
        }
        return _json({
          'keys': [
            {'kid': 'test-key', 'kty': 'RSA', 'n': 'bm90LXJlYWw', 'e': 'AQAB'},
          ],
        });
      }),
    );
    addTearDown(controller.dispose);
    await controller.signIn();
    expect(controller.errorCode, 'identity_mismatch');
    expect(authorization!.queryParameters['client_id'], 'oaiapp_test');
    expect(authorization!.queryParameters['agent_name_hint'], isNull);
    expect(authorization!.queryParameters['id_token_hint'], 'test-id');
    expect(jsonDecode(saved)['access_token'], 'test-access');
    expect(jsonDecode(saved)['subject'], 'test-user');
  });

  test(
    'missing replacement refresh token is not recorded as a successful refresh',
    () async {
      var saved = jsonEncode(_savedSession());
      final controller = ProbeController(
        readState: () async => saved,
        writeState: (value) async {
          saved = value;
        },
        now: () => _now,
        clientFactory: () => MockClient(
          (_) async => _json({
            'access_token': 'new-access',
            'token_type': 'Bearer',
            'expires_in': 3600,
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refreshAndTest();
      expect(controller.errorCode, 'invalid_token_response');
      expect(
        controller.steps.where((s) => s.code == 'refresh').single.passed,
        isFalse,
      );
    },
  );

  test('oversized response body is rejected before decoding', () async {
    final controller = ProbeController(
      readState: () async => jsonEncode(_savedSession()),
      writeState: (_) async {},
      now: () => _now,
      clientFactory: () => MockClient(
        (_) async => http.Response(' ' * (2 * 1024 * 1024 + 1), 200),
      ),
    );
    addTearDown(controller.dispose);
    await controller.loadModels();
    expect(controller.errorCode, 'response_too_large');
  });

  test(
    'terminal refresh rejection clears credentials but retains registration',
    () async {
      String? saved = jsonEncode(_savedSession());
      final controller = ProbeController(
        readState: () async => saved,
        writeState: (value) async {
          saved = value;
        },
        now: () => _now,
        clientFactory: () =>
            MockClient((_) async => _json({'error': 'invalid_grant'}, 400)),
      );
      addTearDown(controller.dispose);
      await controller.refreshAndTest();
      expect(controller.errorCode, 'invalid_grant');
      expect(controller.signedIn, isFalse);
      final record = jsonDecode(saved!);
      expect(record['client_id'], 'oaiapp_test');
      expect(record['ext_agent_host_id'], 'urn:uuid:test-host');
      expect(record['access_token'], isNull);
      expect(record['refresh_token'], isNull);
      expect(record['id_token'], isNull);
    },
  );

  test(
    'temporary refresh failure preserves credentials and safe diagnostics',
    () async {
      var saved = jsonEncode(_savedSession());
      final controller = ProbeController(
        readState: () async => saved,
        writeState: (value) async {
          saved = value;
        },
        now: () => _now,
        clientFactory: () => MockClient(
          (_) async => _json({'detail': 'sensitive raw text'}, 503),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refreshAndTest();
      expect(controller.errorCode, 'http_unavailable');
      expect(controller.errorHttpStatus, 503);
      expect(controller.errorRequestId, 'req_test');
      expect(controller.signedIn, isTrue);
      expect(jsonDecode(saved)['refresh_token'], 'test-refresh');
    },
  );

  test(
    'sign-out revokes only at trusted discovery endpoint and preserves host',
    () async {
      var saved = jsonEncode(_savedSession());
      var revoked = false;
      final controller = ProbeController(
        readState: () async => saved,
        writeState: (value) async {
          saved = value;
        },
        now: () => _now,
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/.well-known/openid-configuration') {
            return _json({
              'issuer': 'https://auth.openai.com',
              'revocation_endpoint': 'https://auth.openai.com/revoke',
            });
          }
          expect(request.url.host, 'auth.openai.com');
          expect(request.url.path, '/revoke');
          expect(request.followRedirects, isFalse);
          expect(request.bodyFields, {
            'token': 'test-refresh',
            'token_type_hint': 'refresh_token',
            'client_id': 'oaiapp_test',
          });
          revoked = true;
          return http.Response('', 200);
        }),
      );
      addTearDown(controller.dispose);
      await controller.signOut();
      expect(revoked, isTrue);
      expect(controller.signedIn, isFalse);
      expect(controller.errorCode, isNull);
      expect(jsonDecode(saved)['client_id'], 'oaiapp_test');
      expect(jsonDecode(saved)['ext_agent_host_id'], 'urn:uuid:test-host');
    },
  );

  test('untrusted revocation URL never receives credentials and local sign-out finishes', () async {
    var saved = jsonEncode(_savedSession());
    final controller = ProbeController(
      readState: () async => saved,
      writeState: (value) async {
        saved = value;
      },
      now: () => _now,
      clientFactory: () => MockClient((request) async {
        expect(request.url.path, '/.well-known/openid-configuration');
        return _json({
          'issuer': 'https://auth.openai.com',
          'revocation_endpoint': 'https://example.invalid/revoke',
        });
      }),
    );
    addTearDown(controller.dispose);
    await controller.signOut();
    expect(controller.signedIn, isFalse);
    expect(controller.errorCode, 'remote_revocation_unconfirmed');
    expect(jsonDecode(saved)['refresh_token'], isNull);
  });
}
