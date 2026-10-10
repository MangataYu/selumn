import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_storage/moodiary_storage.dart';

import 'account_config.dart';
import 'account_models.dart';

export 'account_config.dart';
export 'account_models.dart';

/// Optional account credentials only. No diary, attachment or sync dependency.
@lazySingleton
class AccountRepository {
  AccountRepository(
    this._http,
    this._secure, {
    this.config = const AccountConfig.fromEnvironment(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  @factoryMethod
  AccountRepository.production(
    @Named('selumnAccount') IHttpClient http,
    ISecureKVStorage secure,
  ) : this(http, secure);

  final IHttpClient _http;
  final ISecureKVStorage _secure;
  final DateTime Function() _now;
  final AccountConfig config;
  final _events = StreamController<void>.broadcast();
  Future<void> _operations = Future.value();
  Future<AccountSession>? _refreshing;
  AccountSession? _session;
  bool _loaded = false;
  bool _disposed = false;

  AccountSession? get session => _session;
  Stream<void> get changes => _events.stream;
  String get _sessionKey => '${config.storagePrefix}_session';
  String get _deviceKey => '${config.storagePrefix}_device';

  /// Reads cached credentials only; opening settings never contacts the server.
  Future<AccountSession?> load() => _serial(_load);

  Future<AccountSession?> _load() async {
    if (_loaded || !config.isEnabled) return _session;
    final String? raw;
    try {
      raw = await _secure.get(_sessionKey);
    } catch (_) {
      throw const AccountException('storage_error');
    }
    AccountSession? loaded;
    if (raw != null) {
      try {
        loaded = AccountSession.fromJson(_decode(raw));
      } on FormatException {
        throw const AccountException('invalid_session');
      }
    }
    if (loaded != null && !loaded.refreshExpiresAt.isAfter(_now())) {
      await _clear();
      return null;
    }
    _session = loaded;
    _loaded = true;
    return loaded;
  }

  Future<void> register({required String email, required String password}) =>
      _command('register', {'email': email, 'password': password}, 202);

  Future<void> resendVerification({required String email}) =>
      _command('resend-verification', {'email': email}, 202);

  Future<void> verifyEmail({required String token, required String password}) =>
      _command('verify-email', {'token': token, 'password': password}, 204);

  Future<void> forgotPassword({required String email}) =>
      _command('forgot-password', {'email': email}, 202);

  Future<void> resetPassword({
    required String token,
    required String password,
  }) => _serial(() async {
    await _command('reset-password', {
      'token': token,
      'password': password,
    }, 204);
    // A reset revokes server sessions. Require a fresh login afterwards.
    await _clear();
  });

  Future<AccountSession> login({
    required String email,
    required String password,
  }) => _serial(() async {
    _requireEnabled();
    final device = await _deviceId();
    final response = await _request(
      HttpMethod.post,
      '/v1/auth/login',
      body: {'email': email, 'password': password, 'device_id': device},
    );
    final next = _readSession(response);
    await _save(next);
    return next;
  });

  /// Refresh-token rotation is coalesced and serialized with login and logout.
  Future<AccountSession> refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    late final Future<AccountSession> operation;
    operation = _serial(_refreshCurrent).whenComplete(() {
      if (identical(_refreshing, operation)) _refreshing = null;
    });
    _refreshing = operation;
    return operation;
  }

  Future<AccountSession> _refreshCurrent() async {
    _requireEnabled();
    final current = await _load();
    if (current == null) throw const AccountException('session_expired');
    if (!current.refreshExpiresAt.isAfter(_now())) {
      await _clear();
      throw const AccountException('session_expired');
    }
    try {
      final response = await _request(
        HttpMethod.post,
        '/v1/auth/refresh',
        body: {'refresh_token': current.refreshToken},
      );
      final next = _readSession(response);
      if (next.user.id != current.user.id) {
        throw const AccountException('invalid_response');
      }
      await _save(next);
      return next;
    } on AccountException catch (error) {
      if (error.code == 'unauthorized' || error.code == 'invalid_response') {
        await _clear();
        if (error.code == 'unauthorized') {
          throw const AccountException('session_expired');
        }
      }
      rethrow;
    }
  }

  Future<AccountSession> _validSession() async {
    _requireEnabled();
    final current = await _load();
    if (current == null) throw const AccountException('session_expired');
    if (!current.accessExpiresAt.isAfter(
      _now().add(const Duration(seconds: 30)),
    )) {
      return _refreshCurrent();
    }
    return current;
  }

  Future<AccountUser> refreshUser() => _serial(() async {
    var current = await _validSession();
    Map<String, dynamic> response;
    try {
      response = await _request(
        HttpMethod.get,
        '/v1/me',
        token: current.accessToken,
      );
    } on AccountException catch (error) {
      if (error.code != 'unauthorized') rethrow;
      current = await _refreshCurrent();
      try {
        response = await _request(
          HttpMethod.get,
          '/v1/me',
          token: current.accessToken,
        );
      } on AccountException catch (retryError) {
        if (retryError.code == 'unauthorized') {
          await _clear();
          throw const AccountException('session_expired');
        }
        rethrow;
      }
    }
    final AccountUser user;
    try {
      user = AccountUser.fromJson(response);
    } on FormatException {
      throw const AccountException('invalid_response');
    }
    if (user.id != current.user.id) {
      throw const AccountException('invalid_response');
    }
    await _save(current.withUser(user));
    return user;
  });

  /// Clear only this server's account credentials, even when offline.
  /// Network errors still propagate so the UI can explain remote revocation.
  Future<void> logout() => _serial(() async {
    AccountException? failure;
    try {
      final current = await _load();
      if (current != null) {
        final valid = await _validSession();
        await _request(
          HttpMethod.post,
          '/v1/auth/logout',
          token: valid.accessToken,
          status: 204,
        );
      }
    } on AccountException catch (error) {
      if (!{
        'unauthorized',
        'session_expired',
        'invalid_session',
      }.contains(error.code)) {
        failure = error;
      }
    } finally {
      await _clear();
    }
    if (failure != null) throw failure;
  });

  Future<void> _command(
    String path,
    Map<String, dynamic> body,
    int status,
  ) async {
    await _request(
      HttpMethod.post,
      '/v1/auth/$path',
      body: body,
      status: status,
    );
  }

  Future<Map<String, dynamic>> _request(
    HttpMethod method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
    int status = 200,
  }) async {
    _requireEnabled();
    final HttpResponse<Uint8List> response;
    try {
      response = await _http.requestBytes(
        method,
        '${config.baseUrl}$path',
        body: body == null ? null : HttpBody.json(body),
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        timeout: const Duration(seconds: 20),
        throwOnStatus: false,
        silent: true,
      );
    } catch (_) {
      throw const AccountException('network_error');
    }
    if (response.statusCode != status) {
      var code = response.statusCode == 401 ? 'unauthorized' : 'internal_error';
      try {
        final error = _decodeBytes(response.data)['error'];
        if (error is Map<String, dynamic> &&
            _serverErrors.contains(error['code'])) {
          code = error['code'] as String;
        }
      } on FormatException {
        // HTML proxy errors and unknown server messages never reach the UI.
      }
      throw AccountException(code);
    }
    if (status == 204 || status == 202) return const {};
    try {
      return _decodeBytes(response.data);
    } on FormatException {
      throw const AccountException('invalid_response');
    }
  }

  AccountSession _readSession(Map<String, dynamic> response) {
    try {
      final value = AccountSession.fromJson(response);
      if (!value.accessExpiresAt.isAfter(_now()) ||
          !value.refreshExpiresAt.isAfter(value.accessExpiresAt)) {
        throw const FormatException('Invalid session expiration');
      }
      return value;
    } on FormatException {
      throw const AccountException('invalid_response');
    }
  }

  Future<String> _deviceId() async {
    try {
      final stored = await _secure.get(_deviceKey);
      if (stored != null &&
          RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(stored)) {
        return stored;
      }
      final random = Random.secure();
      final value = List.generate(
        24,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await _secure.set(_deviceKey, value);
      return value;
    } catch (_) {
      throw const AccountException('storage_error');
    }
  }

  Future<void> _save(AccountSession value) async {
    try {
      // One secure-storage value makes the rotated token pair indivisible.
      await _secure.set(_sessionKey, jsonEncode(value.toJson()));
    } catch (_) {
      _session = null;
      _loaded = true;
      _notify();
      // Discard an unusable old refresh token and release the new server session
      // where possible. The original storage failure remains the reported error.
      try {
        await _secure.remove(_sessionKey);
      } catch (_) {
        // The storage_error also covers failure to remove this credential.
      }
      try {
        await _request(
          HttpMethod.post,
          '/v1/auth/logout',
          token: value.accessToken,
          status: 204,
        );
      } on AccountException {
        // A failed best-effort revocation cannot repair unavailable storage.
      }
      throw const AccountException('storage_error');
    }
    _session = value;
    _loaded = true;
    _notify();
  }

  Future<void> _clear() async {
    _session = null;
    _loaded = true;
    _notify();
    try {
      await _secure.remove(_sessionKey);
    } catch (_) {
      throw const AccountException('storage_error');
    }
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final future = _operations.then((_) {
      if (_disposed) throw const AccountException('cancelled');
      return operation();
    });
    _operations = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return future;
  }

  void _requireEnabled() {
    if (_disposed) throw const AccountException('cancelled');
    if (!config.isConfigured) throw const AccountException('disabled');
    if (!config.isValid) throw const AccountException('configuration_invalid');
  }

  void _notify() {
    if (!_disposed) _events.add(null);
  }

  @disposeMethod
  Future<void> dispose() async {
    _disposed = true;
    await _operations;
    await _events.close();
  }

  static Map<String, dynamic> _decodeBytes(Uint8List? bytes) {
    if (bytes == null || bytes.length > 64 * 1024) {
      throw const FormatException('Invalid account response');
    }
    return _decode(utf8.decode(bytes));
  }

  static Map<String, dynamic> _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid account response');
    }
    return decoded;
  }

  static const _serverErrors = {
    'invalid_request',
    'invalid_input',
    'invalid_token',
    'invalid_credentials',
    'unauthorized',
    'email_unverified',
    'registration_closed',
    'device_limit',
    'request_too_large',
    'unsupported_media_type',
    'rate_limited',
    'internal_error',
  };
}
