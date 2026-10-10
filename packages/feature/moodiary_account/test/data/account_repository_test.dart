import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_account/src/data/account_repository.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

final _now = DateTime.utc(2030, 1, 1);
const _config = AccountConfig(apiUrl: 'https://api.example.com');

void main() {
  late _FakeHttp http;
  late MemorySecureKVStorage storage;
  late AccountRepository repository;

  setUp(() {
    http = _FakeHttp();
    storage = MemorySecureKVStorage();
    repository = AccountRepository(
      http,
      storage,
      config: _config,
      now: () => _now,
    );
  });

  tearDown(() async => repository.dispose());

  group('configuration', () {
    test(
      'default configuration leaves local startup independent of accounts',
      () async {
        final disabled = AccountRepository(http, storage);
        addTearDown(disabled.dispose);
        expect(disabled.config.isConfigured, isFalse);
        expect(await disabled.load(), isNull);
        await expectLater(
          disabled.login(email: 'a@b.co', password: 'secret'),
          _error('disabled'),
        );
        expect(http.calls, isEmpty);
        expect(storage.data, isEmpty);
      },
    );

    test('production and staging require an HTTPS origin', () {
      for (final environment in ['production', 'staging']) {
        for (final url in [
          'http://127.0.0.1:8080',
          'http://api.example.com',
          'https://user:password@api.example.com',
          'https://api.example.com/v1',
          'https://api.example.com?secret=1',
          'https://api.example.com#fragment',
          'https://api.example.com:70000',
          'not a url',
        ]) {
          expect(
            AccountConfig(apiUrl: url, environment: environment).isEnabled,
            isFalse,
            reason: url,
          );
        }
        expect(
          AccountConfig(
            apiUrl: 'https://api.example.com/',
            environment: environment,
          ).isEnabled,
          isTrue,
        );
      }
    });

    test('development HTTP is limited to loopback and private networks', () {
      for (final host in [
        'localhost',
        '127.0.0.1',
        '10.1.2.3',
        '172.16.1.1',
        '192.168.2.1',
        '[::1]',
        '[fd00::1]',
      ]) {
        expect(
          AccountConfig(
            apiUrl: 'http://$host:8080',
            environment: 'development',
          ).isEnabled,
          isTrue,
          reason: host,
        );
      }
      for (final host in [
        'example.com',
        '192.169.1.1',
        '172.32.1.1',
        '10.1.2.300',
        'localhost.example.com',
      ]) {
        expect(
          AccountConfig(
            apiUrl: 'http://$host:8080',
            environment: 'development',
          ).isEnabled,
          isFalse,
          reason: host,
        );
      }
      expect(
        const AccountConfig(
          apiUrl: 'https://api.example.com',
          environment: 'test',
        ).isEnabled,
        isFalse,
      );
    });

    test('invalid configuration is inert during load and fails only account actions', () async {
      final invalid = AccountRepository(
        http,
        storage,
        config: const AccountConfig(apiUrl: 'http://example.com'),
      );
      addTearDown(invalid.dispose);
      expect(await invalid.load(), isNull);
      await expectLater(
        invalid.register(email: 'a@b.co', password: 'secret'),
        _error('configuration_invalid'),
      );
      expect(http.calls, isEmpty);
      expect(storage.data, isEmpty);
    });
  });

  test('register, email verification and password recovery match the server contract', () async {
    http.handler = (call) => _response(
      null,
      status: switch (call.path) {
        '/v1/auth/verify-email' || '/v1/auth/reset-password' => 204,
        _ => 202,
      },
    );
    const password = ' original long password ';
    await repository.register(email: ' Owner@example.com ', password: password);
    await repository.resendVerification(email: 'Owner@example.com');
    await repository.verifyEmail(token: 'verify-token', password: password);
    await repository.forgotPassword(email: 'Owner@example.com');
    await repository.resetPassword(
      token: 'reset-token',
      password: ' a new long password ',
    );
    expect(http.calls.map((call) => call.path), [
      '/v1/auth/register',
      '/v1/auth/resend-verification',
      '/v1/auth/verify-email',
      '/v1/auth/forgot-password',
      '/v1/auth/reset-password',
    ]);
    expect(http.calls[0].body, {
      'email': ' Owner@example.com ',
      'password': password,
    });
    expect(http.calls[1].body, {'email': 'Owner@example.com'});
    expect(http.calls[2].body, {'token': 'verify-token', 'password': password});
    expect(http.calls[3].body, {'email': 'Owner@example.com'});
    expect(http.calls[4].body, {
      'token': 'reset-token',
      'password': ' a new long password ',
    });
    for (final call in http.calls) {
      expect(call.method, HttpMethod.post);
      expect(call.silent, isTrue);
      expect(call.throwOnStatus, isFalse);
      expect(call.contentType, 'application/json; charset=utf-8');
      expect(call.headers.containsKey('Authorization'), isFalse);
    }
    expect(
      storage.data.values.any((value) => value.contains(password)),
      isFalse,
    );
  });

  test(
    'login keeps a stable device ID through logout and process recreation',
    () async {
      storage.data['webdav_password'] = 'keep-private';
      http.handler = (call) => call.path == '/v1/auth/logout'
          ? _response(null, status: 204)
          : _response(_session());
      final first = await repository.login(
        email: 'owner@example.com',
        password: 'never-store-this-password',
      );
      expect(first.user.email, 'owner@example.com');
      final deviceId = http.calls.first.body!['device_id'];
      expect(deviceId, matches(RegExp(r'^[A-Za-z0-9._-]{1,128}$')));
      await repository.logout();
      expect(repository.session, isNull);
      expect(storage.data['webdav_password'], 'keep-private');
      expect(
        storage.data.containsKey('${_config.storagePrefix}_session'),
        isFalse,
      );
      final reopened = AccountRepository(
        http,
        storage,
        config: _config,
        now: () => _now,
      );
      addTearDown(reopened.dispose);
      await reopened.login(
        email: 'owner@example.com',
        password: 'another-unpersisted-password',
      );
      expect(http.calls.last.body!['device_id'], deviceId);
      expect(
        storage.data.values.any((value) => value.contains('password')),
        isFalse,
      );
      expect(http.calls[1].body, isNull);
      expect(http.calls[1].headers['Authorization'], 'Bearer access-one');
    },
  );

  test('load restores only the configured namespace and performs no network request', () async {
    _seed(storage, _config, _session());
    final loaded = await repository.load();
    expect(loaded!.user.id, 'user-one');
    expect(http.calls, isEmpty);
    for (final config in [
      const AccountConfig(
        apiUrl: 'https://api.example.com',
        environment: 'staging',
      ),
      const AccountConfig(apiUrl: 'https://other.example.com'),
    ]) {
      final isolated = AccountRepository(
        http,
        storage,
        config: config,
        now: () => _now,
      );
      addTearDown(isolated.dispose);
      expect(await isolated.load(), isNull);
    }
    expect(
      const AccountConfig(apiUrl: 'https://API.example.com:443/').storagePrefix,
      _config.storagePrefix,
    );
  });

  test('expired cached credentials are removed without networking', () async {
    _seed(
      storage,
      _config,
      _session(refreshExpiry: _now.subtract(const Duration(seconds: 1))),
    );
    storage.data['local_sync_key'] = 'untouched';
    expect(await repository.load(), isNull);
    expect(storage.data, {'local_sync_key': 'untouched'});
    expect(http.calls, isEmpty);
  });

  test(
    'storage read and corrupt-session failures remain explicit and recoverable',
    () async {
      final key = '${_config.storagePrefix}_session';
      storage.failingReads.add(key);
      await expectLater(repository.load(), _error('storage_error'));
      storage.failingReads.clear();
      storage.data[key] = '{broken';
      await expectLater(repository.load(), _error('invalid_session'));
      await repository.logout();
      expect(await repository.load(), isNull);
      expect(http.calls, isEmpty);
    },
  );

  test(
    'server error messages and unknown codes never escape the repository',
    () async {
      http.handler = (_) => _response({
        'error': {'code': 'invalid_credentials', 'message': 'secret-password'},
      }, status: 401);
      await expectLater(
        repository.login(email: 'owner@example.com', password: 'bad'),
        _error('invalid_credentials'),
      );
      http.handler = (_) => _response({
        'error': {'code': 'secret-token', 'message': 'secret-password'},
      }, status: 500);
      await expectLater(
        repository.register(email: 'owner@example.com', password: 'bad'),
        _error('internal_error'),
      );
      http.handler = (_) => throw const HttpException(
        HttpErrorType.connection,
        'request contains password=secret',
      );
      await expectLater(
        repository.forgotPassword(email: 'owner@example.com'),
        _error('network_error'),
      );
      http.handler = (_) => HttpResponse(
        statusCode: 502,
        data: Uint8List.fromList(utf8.encode('<html>secret</html>')),
      );
      await expectLater(
        repository.resendVerification(email: 'owner@example.com'),
        _error('internal_error'),
      );
    },
  );

  test('all documented application error codes are preserved', () async {
    for (final code in [
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
    ]) {
      http.handler = (_) => _response({
        'error': {'code': code, 'message': 'ignored'},
      }, status: 400);
      await expectLater(
        repository.register(email: 'owner@example.com', password: 'bad'),
        _error(code),
      );
    }
  });

  test('redirect responses never establish an account session', () async {
    for (final status in [301, 302, 303, 307, 308]) {
      http.handler = (_) => _response(_session(), status: status);
      await expectLater(
        repository.login(email: 'owner@example.com', password: 'secret'),
        _error('internal_error'),
      );
      expect(repository.session, isNull);
      expect(
        storage.data.containsKey('${_config.storagePrefix}_session'),
        isFalse,
      );
    }
  });

  test(
    'malformed or unsafe successful login responses do not create a session',
    () async {
      for (final body in [
        <String, dynamic>{},
        {..._session(), 'token_type': 'Basic'},
        {..._session(), 'access_token': 'secret\r\nInjected: true'},
        {..._session(), 'refresh_token': ''},
        {..._session(), 'access_expires_at': 'yesterday'},
        {
          ..._session(),
          'user': {'email': 'owner@example.com'},
        },
      ]) {
        http.handler = (_) => _response(body);
        await expectLater(
          repository.login(email: 'owner@example.com', password: 'secret'),
          _error('invalid_response'),
        );
        expect(repository.session, isNull);
        expect(
          storage.data.containsKey('${_config.storagePrefix}_session'),
          isFalse,
        );
      }
    },
  );

  test('concurrent refreshes consume a refresh token once and atomically replace both tokens', () async {
    _seed(storage, _config, _session());
    final started = Completer<void>();
    final response = Completer<HttpResponse<Uint8List>>();
    http.handler = (_) {
      started.complete();
      return response.future;
    };
    final first = repository.refresh();
    final second = repository.refresh();
    expect(identical(first, second), isTrue);
    await started.future;
    expect(http.calls.single.body, {'refresh_token': 'refresh-one'});
    expect(http.calls.single.headers.containsKey('Authorization'), isFalse);
    response.complete(_response(_session(suffix: 'two')));
    expect((await first).accessToken, 'access-two');
    expect((await second).refreshToken, 'refresh-two');
    final stored =
        jsonDecode(storage.data['${_config.storagePrefix}_session']!) as Map;
    expect(stored['access_token'], 'access-two');
    expect(stored['refresh_token'], 'refresh-two');
    expect(http.calls, hasLength(1));
  });

  test('logout waits for rotation and revokes the new access token before clearing', () async {
    _seed(storage, _config, _session());
    storage.data['other_credentials'] = 'keep';
    final started = Completer<void>();
    final rotation = Completer<HttpResponse<Uint8List>>();
    http.handler = (call) {
      if (call.path == '/v1/auth/refresh') {
        started.complete();
        return rotation.future;
      }
      return _response(null, status: 204);
    };
    final refresh = repository.refresh();
    await started.future;
    final logout = repository.logout();
    await Future<void>.delayed(Duration.zero);
    expect(http.calls, hasLength(1));
    rotation.complete(_response(_session(suffix: 'two')));
    await refresh;
    await logout;
    expect(http.calls.last.path, '/v1/auth/logout');
    expect(http.calls.last.headers['Authorization'], 'Bearer access-two');
    expect(repository.session, isNull);
    expect(storage.data, {'other_credentials': 'keep'});
  });

  test(
    'a login queued behind refresh remains the final account session',
    () async {
      _seed(storage, _config, _session());
      final started = Completer<void>();
      final rotation = Completer<HttpResponse<Uint8List>>();
      http.handler = (call) {
        if (call.path == '/v1/auth/refresh') {
          started.complete();
          return rotation.future;
        }
        return _response(_session(suffix: 'new', userId: 'new-user'));
      };
      final refresh = repository.refresh();
      await started.future;
      final login = repository.login(
        email: 'new@example.com',
        password: 'another password',
      );
      rotation.complete(_response(_session(suffix: 'two')));
      await refresh;
      await login;
      expect(repository.session!.user.id, 'new-user');
      expect(
        AccountSession.fromJson(
          jsonDecode(storage.data['${_config.storagePrefix}_session']!)
              as Map<String, dynamic>,
        ).user.id,
        'new-user',
      );
    },
  );

  test(
    'logout queued during login cannot be undone by the delayed login response',
    () async {
      final started = Completer<void>();
      final loginResponse = Completer<HttpResponse<Uint8List>>();
      http.handler = (call) {
        if (call.path == '/v1/auth/login') {
          started.complete();
          return loginResponse.future;
        }
        return _response(null, status: 204);
      };
      final login = repository.login(
        email: 'owner@example.com',
        password: 'secret',
      );
      await started.future;
      final logout = repository.logout();
      loginResponse.complete(_response(_session()));
      await login;
      await logout;
      expect(repository.session, isNull);
      expect(
        storage.data.containsKey('${_config.storagePrefix}_session'),
        isFalse,
      );
      expect(http.calls.last.path, '/v1/auth/logout');
    },
  );

  test(
    'me refreshes an expired access token and checks account identity',
    () async {
      _seed(
        storage,
        _config,
        _session(accessExpiry: _now.subtract(const Duration(seconds: 1))),
      );
      http.handler = (call) => call.path == '/v1/auth/refresh'
          ? _response(_session(suffix: 'two'))
          : _response(_user(email: 'updated@example.com'));
      expect((await repository.refreshUser()).email, 'updated@example.com');
      expect(http.calls.map((call) => call.path), [
        '/v1/auth/refresh',
        '/v1/me',
      ]);
      expect(http.calls.last.method, HttpMethod.get);
      expect(http.calls.last.headers['Authorization'], 'Bearer access-two');
      expect(http.calls.last.body, isNull);
      http.handler = (_) => _response(_user(id: 'someone-else'));
      await expectLater(repository.refreshUser(), _error('invalid_response'));
      expect(repository.session!.user.id, 'user-one');
    },
  );

  test('me retries a rejected access token only once, then clears a revoked session', () async {
    _seed(storage, _config, _session());
    http.handler = (call) => call.path == '/v1/auth/refresh'
        ? _response(_session(suffix: 'two'))
        : _response({
            'error': {'code': 'unauthorized'},
          }, status: 401);
    await expectLater(repository.refreshUser(), _error('session_expired'));
    expect(http.calls.map((call) => call.path), [
      '/v1/me',
      '/v1/auth/refresh',
      '/v1/me',
    ]);
    expect(repository.session, isNull);
    expect(storage.data, isEmpty);
  });

  test('invalid refresh credentials clear only account credentials', () async {
    _seed(storage, _config, _session());
    storage.data['encryption_key'] = 'local-only';
    http.handler = (_) => _response({
      'error': {'code': 'unauthorized'},
    }, status: 401);
    await expectLater(repository.refresh(), _error('session_expired'));
    expect(repository.session, isNull);
    expect(storage.data, {'encryption_key': 'local-only'});
  });

  test('refresh may not change the account identity', () async {
    _seed(storage, _config, _session());
    http.handler = (_) => _response(_session(userId: 'other-user'));
    await expectLater(repository.refresh(), _error('invalid_response'));
    expect(repository.session, isNull);
    expect(storage.data, isEmpty);
  });

  test('offline logout clears local credentials and reports remote revocation failure', () async {
    _seed(storage, _config, _session());
    storage.data['s3_credentials'] = 'preserved';
    http.handler = (_) =>
        throw const HttpException(HttpErrorType.connection, 'private-details');
    await expectLater(repository.logout(), _error('network_error'));
    expect(repository.session, isNull);
    expect(storage.data, {'s3_credentials': 'preserved'});
  });

  test('logout refreshes an expired access token before revocation', () async {
    _seed(
      storage,
      _config,
      _session(accessExpiry: _now.subtract(const Duration(minutes: 1))),
    );
    http.handler = (call) => call.path == '/v1/auth/refresh'
        ? _response(_session(suffix: 'two'))
        : _response(null, status: 204);
    await repository.logout();
    expect(http.calls.map((call) => call.path), [
      '/v1/auth/refresh',
      '/v1/auth/logout',
    ]);
    expect(http.calls.last.headers['Authorization'], 'Bearer access-two');
    expect(repository.session, isNull);
  });

  test(
    'a failed rotated-token write cannot report a usable or stale session',
    () async {
      _seed(storage, _config, _session());
      storage.failingKeys.add('${_config.storagePrefix}_session');
      http.handler = (call) => call.path == '/v1/auth/refresh'
          ? _response(_session(suffix: 'two'))
          : _response(null, status: 204);
      await expectLater(repository.refresh(), _error('storage_error'));
      expect(repository.session, isNull);
      expect(storage.data, isEmpty);
      expect(http.calls.last.path, '/v1/auth/logout');
      expect(http.calls.last.headers['Authorization'], 'Bearer access-two');
    },
  );

  test('device identity storage failure prevents login requests', () async {
    storage.failingKeys.add('${_config.storagePrefix}_device');
    await expectLater(
      repository.login(email: 'owner@example.com', password: 'secret'),
      _error('storage_error'),
    );
    expect(http.calls, isEmpty);
    expect(repository.session, isNull);
  });

  test(
    'logout reports unavailable storage and can retry removing credentials',
    () async {
      _seed(storage, _config, _session());
      final unreliable = _ControlledStorage(storage)..failRemoval = true;
      final account = AccountRepository(
        http,
        unreliable,
        config: _config,
        now: () => _now,
      );
      addTearDown(account.dispose);
      http.handler = (_) => _response(null, status: 204);
      await account.load();
      await expectLater(account.logout(), _error('storage_error'));
      expect(account.session, isNull);
      expect(
        storage.data.containsKey('${_config.storagePrefix}_session'),
        isTrue,
      );
      unreliable.failRemoval = false;
      await account.logout();
      expect(storage.data, isEmpty);
      expect(http.calls, hasLength(1));
    },
  );

  test('logout drains a credential write before removal', () async {
    final writing = Completer<void>();
    final allowWrite = Completer<void>();
    final delayed = _ControlledStorage(storage)
      ..beforeWrite = (key) async {
        if (key.endsWith('_session')) {
          writing.complete();
          await allowWrite.future;
        }
      };
    final account = AccountRepository(
      http,
      delayed,
      config: _config,
      now: () => _now,
    );
    addTearDown(account.dispose);
    http.handler = (call) => call.path == '/v1/auth/login'
        ? _response(_session())
        : _response(null, status: 204);
    final login = account.login(email: 'owner@example.com', password: 'secret');
    await writing.future;
    final logout = account.logout();
    expect(account.session, isNull);
    allowWrite.complete();
    await login;
    await logout;
    expect(account.session, isNull);
    expect(
      storage.data.containsKey('${_config.storagePrefix}_session'),
      isFalse,
    );
  });

  test(
    'successful password reset removes cached account credentials only',
    () async {
      _seed(storage, _config, _session());
      storage.data['webdav_credentials'] = 'retained';
      http.handler = (_) => _response(null, status: 204);
      await repository.load();
      await repository.resetPassword(
        token: 'reset-token',
        password: 'long new password',
      );
      expect(repository.session, isNull);
      expect(storage.data, {'webdav_credentials': 'retained'});
    },
  );
}

Matcher _error(String code) => throwsA(
  isA<AccountException>().having((error) => error.code, 'code', code),
);

Map<String, dynamic> _user({
  String id = 'user-one',
  String email = 'owner@example.com',
}) => {
  'id': id,
  'email': email,
  'email_verified': true,
  'created_at': _now.subtract(const Duration(days: 1)).toIso8601String(),
};

Map<String, dynamic> _session({
  String suffix = 'one',
  String userId = 'user-one',
  DateTime? accessExpiry,
  DateTime? refreshExpiry,
}) => {
  'access_token': 'access-$suffix',
  'refresh_token': 'refresh-$suffix',
  'token_type': 'Bearer',
  'access_expires_at': (accessExpiry ?? _now.add(const Duration(minutes: 15)))
      .toIso8601String(),
  'refresh_expires_at': (refreshExpiry ?? _now.add(const Duration(days: 30)))
      .toIso8601String(),
  'user': _user(id: userId),
};

void _seed(
  MemorySecureKVStorage storage,
  AccountConfig config,
  Map<String, dynamic> session,
) {
  storage.data['${config.storagePrefix}_session'] = jsonEncode(session);
}

HttpResponse<Uint8List> _response(Object? body, {int status = 200}) =>
    HttpResponse(
      statusCode: status,
      data: body == null
          ? null
          : Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );

class _Call {
  _Call(
    this.method,
    this.url, {
    HttpBody? body,
    required this.headers,
    required this.silent,
    required this.throwOnStatus,
  }) : body = body == null
           ? null
           : jsonDecode(utf8.decode(body.bytes)) as Map<String, dynamic>,
       contentType = body?.contentType;

  final HttpMethod method;
  final String url;
  final Map<String, dynamic>? body;
  final String? contentType;
  final Map<String, dynamic> headers;
  final bool silent;
  final bool? throwOnStatus;
  String get path => Uri.parse(url).path;
}

class _FakeHttp implements IHttpClient {
  final calls = <_Call>[];
  FutureOr<HttpResponse<Uint8List>> Function(_Call call)? handler;

  @override
  Future<HttpResponse<Uint8List>> requestBytes(
    HttpMethod method,
    String url, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    HttpBody? body,
    Duration? timeout,
    bool silent = false,
    bool? throwOnStatus,
  }) async {
    final call = _Call(
      method,
      url,
      body: body,
      headers: headers ?? {},
      silent: silent,
      throwOnStatus: throwOnStatus,
    );
    calls.add(call);
    if (handler == null) throw StateError('Unexpected HTTP request');
    return handler!(call);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledStorage implements ISecureKVStorage {
  _ControlledStorage(this.delegate);

  final MemorySecureKVStorage delegate;
  bool failRemoval = false;
  Future<void> Function(String key)? beforeWrite;

  @override
  Future<void> init() => delegate.init();

  @override
  Future<String?> get(String key) => delegate.get(key);

  @override
  Future<void> set(String key, String value) async {
    await beforeWrite?.call(key);
    await delegate.set(key, value);
  }

  @override
  Future<void> remove(String key) async {
    if (failRemoval) throw StateError('secure storage unavailable');
    await delegate.remove(key);
  }

  @override
  Future<void> clear() =>
      throw StateError('account must never clear all storage');
}
