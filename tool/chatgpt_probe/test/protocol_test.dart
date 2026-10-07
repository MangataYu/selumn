import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../lib/src/protocol.dart';

Matcher failsWith(String code) =>
    throwsA(isA<ProbeException>().having((error) => error.code, 'code', code));

String encode(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

String idToken(
  Map<String, dynamic> claims, {
  Map<String, dynamic> header = const {'alg': 'RS256', 'kid': 'key-1'},
}) => '${encode(header)}.${encode(claims)}.c2lnbmF0dXJl';

Map<String, dynamic> get validClaims => {
  'iss': 'https://auth.openai.com',
  'aud': 'oaiapp_test',
  'sub': 'subject-1',
  'nonce': 'nonce-1',
  'iat': 1790000000,
  'exp': 1790003600,
};

Map<String, dynamic> get validKey => {
  'kid': 'key-1',
  'kty': 'RSA',
  'alg': 'RS256',
  'use': 'sig',
  'key_ops': ['verify'],
  'n': 'cHVibGljLW1vZHVsdXM',
  'e': 'AQAB',
};

Future<Map<String, dynamic>> verify(
  String token, {
  Map<String, dynamic>? jwks,
  Future<bool> Function(Map<String, dynamic>, String, String)? signature,
}) => verifyIdToken(
  token,
  clientId: 'oaiapp_test',
  nonce: 'nonce-1',
  jwks:
      jwks ??
      {
        'keys': [validKey],
      },
  verifySignature: signature ?? (_, _, _) async => true,
  now: DateTime.fromMillisecondsSinceEpoch(1790000300 * 1000, isUtc: true),
);

String event(Map<String, dynamic> value) => 'data: ${jsonEncode(value)}\n\n';

const completed = {
  'type': 'response.completed',
  'response': {'status': 'completed'},
};

Stream<List<int>> chunked(String value, [int chunkSize = 1]) async* {
  final bytes = utf8.encode(value);
  for (var start = 0; start < bytes.length; start += chunkSize) {
    final end = start + chunkSize;
    yield bytes.sublist(start, end > bytes.length ? bytes.length : end);
  }
}

void main() {
  group('OAuth transaction', () {
    test('PKCE matches the RFC 7636 S256 example', () {
      expect(
        pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('generated secrets and UUID use supported formats', () {
      final first = randomUrlToken();
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(randomUrlToken(), isNot(first));
      expect(
        newHostId(),
        matches(
          RegExp(
            r'^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
            r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    AuthorizationResult callback(String query, {String? clientId}) =>
        parseAuthorizationCallback(
          Uri.parse('http://127.0.0.1:1455/auth/callback?$query'),
          expectedState: 'state-1',
          expectedClientId: clientId,
        );

    test('registration uses the issued client ID', () {
      final result = callback(
        'state=state-1&code=code-1&client_id=oaiapp_test',
      );
      expect(result.code, 'code-1');
      expect(result.clientId, 'oaiapp_test');
    });

    test('returning callback can omit but cannot change the client ID', () {
      expect(
        callback('state=state-1&code=code-1', clientId: 'oaiapp_test').clientId,
        'oaiapp_test',
      );
      expect(
        () => callback(
          'state=state-1&code=code-1&client_id=oaiapp_other',
          clientId: 'oaiapp_test',
        ),
        failsWith('client_id_mismatch'),
      );
    });

    test('registration rejects missing or bootstrap client IDs', () {
      for (final query in [
        'state=state-1&code=code-1',
        'state=state-1&code=code-1&client_id=',
        'state=state-1&code=code-1&client_id=dynamic_agent_client',
      ]) {
        expect(() => callback(query), failsWith('invalid_client_id'));
      }
    });

    test('CSRF state is checked even on an OAuth failure', () {
      for (final query in [
        'code=code-1&client_id=oaiapp_test',
        'state=wrong&code=code-1&client_id=oaiapp_test',
        'state=wrong&error=access_denied',
      ]) {
        expect(() => callback(query), failsWith('state_mismatch'));
      }
      expect(
        () => callback(
          'state=state-1&error=access_denied&error_description=secret',
        ),
        failsWith('oauth_access_denied'),
      );
      expect(
        () => callback('state=state-1&error=secret'),
        failsWith('oauth_error'),
      );
    });

    test('duplicate callback values are never silently selected', () {
      for (final duplicate in [
        'state=state-1',
        'code=code-2',
        'client_id=oaiapp_other',
      ]) {
        expect(
          () => callback(
            'state=state-1&code=code-1&client_id=oaiapp_test&$duplicate',
          ),
          failsWith('duplicate_callback_parameter'),
        );
      }
    });

    test('callback rejects an unexpected path or host', () {
      for (final url in [
        'http://127.0.0.1:1455/callback?state=state-1',
        'http://localhost:1455/auth/callback?state=state-1',
        'https://example.com/auth/callback?state=state-1',
        '/auth/callback?state=state-1#secret',
      ]) {
        expect(
          () => parseAuthorizationCallback(
            Uri.parse(url),
            expectedState: 'state-1',
          ),
          failsWith('invalid_callback'),
        );
      }
    });
  });

  group('ID token verification', () {
    test(
      'decodes JWT segments with zero, one and two omitted padding bytes',
      () async {
        final encounteredLengths = <int>{};
        for (var length = 0; length < 3; length++) {
          final claims = {...validClaims, 'padding_test': 'x' * length};
          final header = {
            'alg': 'RS256',
            'kid': 'key-1',
            'padding_test': 'x' * length,
          };
          final token = idToken(claims, header: header);
          expect(token, isNot(contains('=')));
          encounteredLengths.add(encode(claims).length % 4);
          final identity = await verify(
            token,
            signature: (_, input, _) async {
              expect(input, '${encode(header)}.${encode(claims)}');
              return true;
            },
          );
          expect(identity['sub'], 'subject-1');
        }
        expect(encounteredLengths, {0, 2, 3});
      },
    );

    test(
      'verifies the exact signing input against the matched trusted key',
      () async {
        final token = idToken(validClaims);
        final identity = await verify(
          token,
          signature: (key, input, signature) async {
            expect(key, validKey);
            expect(input, token.substring(0, token.lastIndexOf('.')));
            expect(signature, 'c2lnbmF0dXJl');
            return true;
          },
        );
        expect(identity['sub'], 'subject-1');
      },
    );

    test(
      'checks signature before decoding or trusting identity claims',
      () async {
        var attempted = false;
        final token =
            '${encode({'alg': 'RS256', 'kid': 'key-1'})}.bm90LWpzb24.c2ln';
        await expectLater(
          verify(
            token,
            signature: (_, _, _) async {
              attempted = true;
              return false;
            },
          ),
          failsWith('invalid_id_token_signature'),
        );
        expect(attempted, isTrue);
      },
    );

    test(
      'signature failure and verifier exceptions do not expose secrets',
      () async {
        await expectLater(
          verify(idToken(validClaims), signature: (_, _, _) async => false),
          failsWith('invalid_id_token_signature'),
        );
        await expectLater(
          verify(
            idToken(validClaims),
            signature: (_, _, _) async {
              throw StateError('secret token');
            },
          ),
          failsWith('invalid_id_token_signature'),
        );
      },
    );

    test(
      'rejects none, HMAC and token-provided signing keys before verification',
      () async {
        for (final header in [
          {'alg': 'none', 'kid': 'key-1'},
          {'alg': 'HS256', 'kid': 'key-1'},
          {'alg': 'RS256', 'kid': 'key-1', 'jku': 'https://example.com'},
          {
            'alg': 'RS256',
            'kid': 'key-1',
            'crit': ['custom'],
          },
        ]) {
          await expectLater(
            verify(
              idToken(validClaims, header: header),
              signature: (_, _, _) async {
                fail(
                  'Unsafe JWT headers must not reach the signature verifier.',
                );
              },
            ),
            failsWith('unsupported_id_token_algorithm'),
          );
        }
      },
    );

    test(
      'rejects missing, duplicate, wrong-type and non-signing JWKs',
      () async {
        for (final keys in [
          <Map<String, dynamic>>[],
          [validKey, validKey],
          [
            {...validKey, 'kty': 'oct'},
          ],
          [
            {...validKey, 'use': 'enc'},
          ],
          [
            {...validKey, 'alg': 'RS512'},
          ],
          [
            {
              ...validKey,
              'key_ops': ['encrypt'],
            },
          ],
        ]) {
          await expectLater(
            verify(idToken(validClaims), jwks: {'keys': keys}),
            failsWith('invalid_signing_key'),
          );
        }
      },
    );

    test('validates issuer, audience, expiration, nonce and subject', () async {
      final cases = <(Map<String, dynamic>, String)>[
        ({'iss': 'https://example.com'}, 'id_token_issuer_mismatch'),
        ({'aud': 'other-client'}, 'id_token_audience_mismatch'),
        (
          {
            'aud': ['oaiapp_test', 1],
          },
          'id_token_audience_mismatch',
        ),
        ({'exp': 1790000200}, 'id_token_expired'),
        ({'exp': '1790003600'}, 'id_token_expired'),
        ({'iat': null}, 'invalid_id_token_time'),
        ({'iat': 1790000400}, 'invalid_id_token_time'),
        ({'nbf': 1790000400}, 'invalid_id_token_time'),
        ({'nonce': 'different'}, 'id_token_nonce_mismatch'),
        ({'nonce': null}, 'id_token_nonce_mismatch'),
        ({'sub': '  '}, 'missing_id_token_subject'),
      ];
      for (final (overrides, code) in cases) {
        await expectLater(
          verify(idToken({...validClaims, ...overrides})),
          failsWith(code),
        );
      }
    });

    test('multiple audiences require the expected authorized party', () async {
      final claims = {
        ...validClaims,
        'aud': ['oaiapp_test', 'other'],
      };
      await expectLater(
        verify(idToken(claims)),
        failsWith('id_token_audience_mismatch'),
      );
      await expectLater(
        verify(idToken({...claims, 'azp': 'other'})),
        failsWith('id_token_audience_mismatch'),
      );
      expect(
        (await verify(idToken({...claims, 'azp': 'oaiapp_test'})))['sub'],
        'subject-1',
      );
      await expectLater(
        verify(idToken({...validClaims, 'azp': 'other'})),
        failsWith('id_token_audience_mismatch'),
      );
    });
  });

  group('Responses event stream', () {
    test('decodes UTF-8 and CRLF across individual byte chunks', () async {
      final input =
          ': keepalive\r\n\r\n'
          'event: response.output_text.delta\r\n'
          'data: {"type":"response.output_text.delta","delta":"你好🌙"}\r\n\r\n'
          '${event(completed)}';
      expect(await readResponseText(chunked(input)).join(), '你好🌙');
    });

    test('joins multiline SSE data and ignores non-text events', () async {
      final input =
          'data: {"type":"response.output_text.delta",\n'
          'data: "delta":"OK"}\n\n'
          '${event({'type': 'response.output_text.done', 'text': 'OK'})}'
          '${event(completed)}';
      expect(await readResponseText(chunked(input, 7)).toList(), ['OK']);
    });

    test(
      'a subscription failure after text is still a failed request',
      () async {
        for (final code in [
          'subscription_sharing_usage_limit_exceeded',
          'subscription_sharing_usage_unavailable',
        ]) {
          final input =
              event({'type': 'response.output_text.delta', 'delta': 'OK'}) +
              event({
                'type': 'response.failed',
                'response': {
                  'error': {'code': code, 'message': 'secret account info'},
                },
              });
          await expectLater(
            readResponseText(chunked(input, 13)),
            emitsInOrder([
              'OK',
              emitsError(
                isA<ProbeException>().having((e) => e.code, 'code', code),
              ),
            ]),
          );
        }
      },
    );

    test('unknown error details become a fixed safe error code', () async {
      for (final failure in [
        {'type': 'error', 'code': 'secret', 'message': 'secret account info'},
        {
          'type': 'response.failed',
          'response': {
            'error': {'code': 'secret'},
          },
        },
      ]) {
        await expectLater(
          readResponseText(chunked(event(failure))).toList(),
          failsWith('response_failed'),
        );
      }
    });

    test(
      'partial text, DONE or an unfinished event cannot indicate success',
      () async {
        for (final input in [
          '',
          event({'type': 'response.output_text.delta', 'delta': 'OK'}),
          'data: [DONE]\n\n',
          'data: ${jsonEncode(completed)}\n',
        ]) {
          await expectLater(
            readResponseText(chunked(input)).toList(),
            failsWith('response_stream_incomplete'),
          );
        }
      },
    );

    test('completion requires completed response status', () async {
      for (final terminal in [
        {'type': 'response.incomplete'},
        {'type': 'response.completed'},
        {
          'type': 'response.completed',
          'response': {'status': 'incomplete'},
        },
      ]) {
        await expectLater(
          readResponseText(chunked(event(terminal))).toList(),
          failsWith('response_incomplete'),
        );
      }
    });

    test(
      'malformed JSON, malformed UTF-8 and conflicting types are rejected',
      () async {
        for (final input in [
          'data: nope\n\n',
          'event: response.completed\ndata: {"type":"response.failed"}\n\n',
          event({'type': 'response.output_text.delta', 'delta': 1}),
        ]) {
          await expectLater(
            readResponseText(chunked(input)).toList(),
            failsWith('invalid_response_event'),
          );
        }
        await expectLater(
          readResponseText(Stream.value([0xff])).toList(),
          failsWith('invalid_response_event'),
        );
      },
    );

    test('bounds an unterminated event and cumulative response text', () async {
      await expectLater(
        readResponseText(
          Stream.value(utf8.encode('data: ${'a' * (256 * 1024)}')),
        ).toList(),
        failsWith('response_event_too_large'),
      );
      final largeDelta = event({
        'type': 'response.output_text.delta',
        'delta': 'a' * 150000,
      });
      await expectLater(
        readResponseText(Stream.value(utf8.encode('$largeDelta$largeDelta')))
            .toList(),
        failsWith('response_too_large'),
      );
    });

    test('bounds total stream bytes even if events produce no text', () async {
      final padding = ': ${'a' * 100000}\n\n';
      await expectLater(
        readResponseText(
          Stream.fromIterable(List.generate(43, (_) => utf8.encode(padding))),
        ).toList(),
        failsWith('response_too_large'),
      );
    });

    test(
      'network stream errors do not expose their original message',
      () async {
        await expectLater(
          readResponseText(Stream.error(StateError('secret request data')))
              .toList(),
          failsWith('response_stream_interrupted'),
        );
      },
    );
  });
}
