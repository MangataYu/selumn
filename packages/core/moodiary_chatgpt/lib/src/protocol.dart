import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Contains only an application error code and safe HTTP diagnostic metadata.
class ChatGptException implements Exception {
  const ChatGptException(this.code, {this.httpStatus, this.requestId});

  final String code;
  final int? httpStatus;
  final String? requestId;

  @override
  String toString() =>
      RegExp(r'^[a-z][a-z0-9_]{0,95}$').hasMatch(code) ? code : 'chatgpt_error';
}

String randomUrlToken([int bytes = 32]) {
  if (bytes < 16 || bytes > 128) {
    throw ArgumentError.value(bytes, 'bytes', 'Must be between 16 and 128.');
  }
  final random = Random.secure();
  return _encode(List<int>.generate(bytes, (_) => random.nextInt(256)));
}

String newHostId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'urn:uuid:${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String pkceChallenge(String verifier) =>
    _encode(sha256.convert(ascii.encode(verifier)).bytes);

String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

bool _constantTimeEquals(String actual, String expected) {
  // Hashing to a fixed size avoids comparisons that return on the first mismatch.
  final left = sha256.convert(utf8.encode(actual)).bytes;
  final right = sha256.convert(utf8.encode(expected)).bytes;
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

class AuthorizationResult {
  const AuthorizationResult({required this.code, required this.clientId});

  final String code;
  final String clientId;
}

AuthorizationResult parseAuthorizationCallback(
  Uri uri, {
  required String expectedState,
  String? expectedClientId,
}) {
  if (uri.path != '/auth/callback' ||
      uri.hasFragment ||
      uri.query.length > 16384 ||
      (uri.hasAuthority &&
          (uri.scheme != 'http' ||
              uri.host != '127.0.0.1' ||
              uri.userInfo.isNotEmpty))) {
    throw const ChatGptException('invalid_callback');
  }
  final Map<String, List<String>> parameters;
  try {
    parameters = uri.queryParametersAll;
  } on FormatException {
    throw const ChatGptException('invalid_callback');
  }
  if (parameters.values.any((values) => values.length != 1)) {
    throw const ChatGptException('duplicate_callback_parameter');
  }
  final state = parameters['state']?.single;
  if (expectedState.isEmpty ||
      state == null ||
      state.isEmpty ||
      !_constantTimeEquals(state, expectedState)) {
    throw const ChatGptException('state_mismatch');
  }
  if (parameters.containsKey('error')) {
    throw ChatGptException(
      parameters['error']!.single == 'access_denied'
          ? 'oauth_access_denied'
          : 'oauth_error',
    );
  }
  final code = parameters['code']?.single;
  if (code == null || code.trim().isEmpty || code.length > 4096) {
    throw const ChatGptException('missing_authorization_code');
  }
  final suppliedClientId = parameters['client_id']?.single;
  final clientId = suppliedClientId ?? expectedClientId;
  if (clientId == null ||
      clientId.isEmpty ||
      clientId.length > 512 ||
      RegExp(r'\s').hasMatch(clientId) ||
      clientId == 'dynamic_agent_client' ||
      expectedClientId == 'dynamic_agent_client') {
    throw const ChatGptException('invalid_client_id');
  }
  if (expectedClientId != null && clientId != expectedClientId) {
    throw const ChatGptException('client_id_mismatch');
  }
  return AuthorizationResult(code: code, clientId: clientId);
}

/// Validates a JWT against trusted, separately fetched OpenAI public keys.
///
/// The signature callback must use RSASSA-PKCS1-v1_5 with SHA-256, decoding the
/// signature as base64url. Neither token-provided key URLs nor embedded keys are
/// used. Identity claims are decoded only after successful verification.
Future<Map<String, dynamic>> verifyIdToken(
  String token, {
  required String clientId,
  required String nonce,
  required Map<String, dynamic> jwks,
  required Future<bool> Function(
    Map<String, dynamic> jwk,
    String signingInput,
    String signature,
  )
  verifySignature,
  DateTime? now,
}) async {
  if (token.length > 32768 || clientId.isEmpty || nonce.isEmpty) {
    throw const ChatGptException('invalid_id_token');
  }
  final parts = token.split('.');
  if (parts.length != 3 || parts.any((part) => !_isBase64Url(part))) {
    throw const ChatGptException('invalid_id_token');
  }
  final header = _decodeObject(parts[0]);
  if (header['alg'] != 'RS256' ||
      header.containsKey('crit') ||
      header.containsKey('b64') ||
      header.containsKey('jku') ||
      header.containsKey('jwk') ||
      header.containsKey('x5u')) {
    throw const ChatGptException('unsupported_id_token_algorithm');
  }
  final kid = header['kid'];
  final keys = jwks['keys'];
  if (kid is! String || kid.isEmpty || kid.length > 256 || keys is! List) {
    throw const ChatGptException('invalid_signing_key');
  }
  final matching = keys
      .whereType<Map<String, dynamic>>()
      .where((key) => key['kid'] == kid)
      .toList();
  if (matching.length != 1) {
    throw const ChatGptException('invalid_signing_key');
  }
  final key = matching.single;
  final keyOperations = key['key_ops'];
  if (key['kty'] != 'RSA' ||
      (key.containsKey('alg') && key['alg'] != 'RS256') ||
      (key.containsKey('use') && key['use'] != 'sig') ||
      (keyOperations != null &&
          (keyOperations is! List || !keyOperations.contains('verify'))) ||
      !_isBase64Url(key['n']) ||
      !_isBase64Url(key['e'])) {
    throw const ChatGptException('invalid_signing_key');
  }
  final bool signatureValid;
  try {
    signatureValid = await verifySignature(
      Map<String, dynamic>.unmodifiable(key),
      '${parts[0]}.${parts[1]}',
      parts[2],
    );
  } catch (_) {
    // Native verifier errors must not expose a token or key material.
    throw const ChatGptException('invalid_id_token_signature');
  }
  if (!signatureValid) {
    throw const ChatGptException('invalid_id_token_signature');
  }

  final claims = _decodeObject(parts[1]);
  if (claims['iss'] != 'https://auth.openai.com') {
    throw const ChatGptException('id_token_issuer_mismatch');
  }
  final audience = claims['aud'];
  final audiences = audience is String
      ? <String>[audience]
      : audience is List && audience.every((value) => value is String)
      ? audience.cast<String>()
      : <String>[];
  if (!audiences.contains(clientId) ||
      (audiences.length > 1 && claims['azp'] != clientId) ||
      (claims.containsKey('azp') && claims['azp'] != clientId)) {
    throw const ChatGptException('id_token_audience_mismatch');
  }
  final seconds =
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000;
  const clockTolerance = 5;
  final expiry = claims['exp'];
  final issuedAt = claims['iat'];
  final notBefore = claims['nbf'];
  if (expiry is! int || expiry <= seconds - clockTolerance) {
    throw const ChatGptException('id_token_expired');
  }
  if (issuedAt is! int ||
      issuedAt > seconds + clockTolerance ||
      issuedAt >= expiry ||
      (notBefore != null &&
          (notBefore is! int || notBefore > seconds + clockTolerance))) {
    throw const ChatGptException('invalid_id_token_time');
  }
  final actualNonce = claims['nonce'];
  if (actualNonce is! String || !_constantTimeEquals(actualNonce, nonce)) {
    throw const ChatGptException('id_token_nonce_mismatch');
  }
  final subject = claims['sub'];
  if (subject is! String || subject.trim().isEmpty) {
    throw const ChatGptException('missing_id_token_subject');
  }
  return Map<String, dynamic>.unmodifiable(claims);
}

bool _isBase64Url(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length % 4 != 1 &&
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);

Map<String, dynamic> _decodeObject(String segment) {
  try {
    // JWT uses unpadded base64url; Dart's decoder expects a multiple of four.
    final value = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segment))),
    );
    if (value is Map<String, dynamic>) return value;
  } on FormatException {
    throw const ChatGptException('invalid_id_token');
  }
  throw const ChatGptException('invalid_id_token');
}

const _maxEventLength = 256 * 1024;
const _maxInputBytes = 4 * 1024 * 1024;
const _maxOutputLength = 256 * 1024;

/// Emits partial text, but succeeds only after a completed Responses event.
///
/// Callers must not treat a yielded delta as proof that the request succeeded:
/// subscription-limit errors can arrive after text has already been streamed.
Stream<String> readResponseText(Stream<List<int>> bytes) async* {
  var totalBytes = 0;
  var outputLength = 0;
  var eventLength = 0;
  var eventName = '';
  final data = <String>[];
  var line = StringBuffer();
  var skipLf = false;
  var firstCharacter = true;

  Stream<List<int>> boundedBytes() async* {
    await for (final chunk in bytes) {
      totalBytes += chunk.length;
      if (totalBytes > _maxInputBytes) {
        throw const ChatGptException('response_too_large');
      }
      yield chunk;
    }
  }

  try {
    await for (final chunk in utf8.decoder.bind(boundedBytes())) {
      for (final character in chunk.codeUnits) {
        if (firstCharacter) {
          firstCharacter = false;
          if (character == 0xfeff) continue;
        }
        if (skipLf) {
          skipLf = false;
          if (character == 10) continue;
        }
        if (character != 10 && character != 13) {
          line.writeCharCode(character);
          eventLength++;
          if (eventLength > _maxEventLength) {
            throw const ChatGptException('response_event_too_large');
          }
          continue;
        }
        skipLf = character == 13;
        final value = line.toString();
        line = StringBuffer();
        if (value.isEmpty) {
          if (data.isNotEmpty) {
            final event = _parseResponseEvent(data.join('\n'), eventName);
            final type = event['type'];
            if (type == 'response.output_text.delta') {
              final delta = event['delta'];
              if (delta is! String) {
                throw const ChatGptException('invalid_response_event');
              }
              outputLength += delta.length;
              if (outputLength > _maxOutputLength) {
                throw const ChatGptException('response_too_large');
              }
              if (delta.isNotEmpty) yield delta;
            } else if (type == 'response.completed') {
              final response = event['response'];
              if (response is! Map || response['status'] != 'completed') {
                throw const ChatGptException('response_incomplete');
              }
              return;
            } else if (type == 'response.failed' || type == 'error') {
              final response = event['response'];
              final error = response is Map
                  ? response['error']
                  : event['error'];
              final code = error is Map ? error['code'] : event['code'];
              throw ChatGptException(_safeResponseError(code));
            } else if (type == 'response.incomplete' ||
                type == 'response.cancelled') {
              throw const ChatGptException('response_incomplete');
            }
          }
          data.clear();
          eventName = '';
          eventLength = 0;
        } else if (!value.startsWith(':')) {
          final colon = value.indexOf(':');
          final field = colon < 0 ? value : value.substring(0, colon);
          var fieldValue = colon < 0 ? '' : value.substring(colon + 1);
          if (fieldValue.startsWith(' ')) fieldValue = fieldValue.substring(1);
          if (field == 'data') data.add(fieldValue);
          if (field == 'event') eventName = fieldValue;
        }
      }
    }
  } on ChatGptException {
    rethrow;
  } on FormatException {
    throw const ChatGptException('invalid_response_event');
  } catch (_) {
    throw const ChatGptException('response_stream_interrupted');
  }
  // SSE dispatches on a blank line. An unfinished final event is never success.
  throw const ChatGptException('response_stream_incomplete');
}

Map<String, dynamic> _parseResponseEvent(String data, String eventName) {
  if (data.trim() == '[DONE]') {
    throw const ChatGptException('response_stream_incomplete');
  }
  final value = jsonDecode(data);
  if (value is! Map<String, dynamic> ||
      value['type'] is! String ||
      (eventName.isNotEmpty && eventName != value['type'])) {
    throw const ChatGptException('invalid_response_event');
  }
  return value;
}

String _safeResponseError(Object? code) => switch (code) {
  'subscription_sharing_usage_limit_exceeded' ||
  'subscription_sharing_usage_unavailable' ||
  'subscription_sharing_not_enabled' ||
  'rate_limit_exceeded' ||
  'insufficient_quota' ||
  'model_not_found' ||
  'invalid_api_key' ||
  'server_error' => code as String,
  _ => 'response_failed',
};
