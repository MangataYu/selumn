import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'protocol.dart';

class ChatGptModel {
  const ChatGptModel(this.id, this.label);
  final String id;
  final String label;
}

class ChatGptStep {
  const ChatGptStep(this.code, this.passed);
  final String code;
  final bool passed;
}

class _PendingSignIn {
  const _PendingSignIn({
    required this.state,
    required this.nonce,
    required this.verifier,
    required this.redirect,
    required this.expectedClientId,
    required this.createdAt,
    required this.expiresAt,
  });

  final String state;
  final String nonce;
  final String verifier;
  final Uri redirect;
  final String? expectedClientId;
  final int createdAt;
  final int expiresAt;

  bool isValidAt(DateTime now) =>
      now.millisecondsSinceEpoch >= createdAt &&
      now.millisecondsSinceEpoch < expiresAt;

  Map<String, dynamic> toJson() => {
    'state': state,
    'nonce': nonce,
    'verifier': verifier,
    'redirect_uri': redirect.toString(),
    'expected_client_id': expectedClientId,
    'created_at': createdAt,
    'expires_at': expiresAt,
  };

  static _PendingSignIn parse(Object? value) {
    try {
      if (value is! Map<String, dynamic>) {
        throw const ChatGptException('pending_authorization_invalid');
      }
      bool validToken(Object? token, int minimum) =>
          token is String &&
          token.length >= minimum &&
          token.length <= 128 &&
          RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token);
      final redirectValue = value['redirect_uri'];
      final redirect = redirectValue is String && redirectValue.length <= 128
          ? Uri.tryParse(redirectValue)
          : null;
      final clientId = value['expected_client_id'];
      final created = value['created_at'];
      final expires = value['expires_at'];
      if (!validToken(value['state'], 32) ||
          !validToken(value['nonce'], 32) ||
          !validToken(value['verifier'], 43) ||
          redirect == null ||
          redirect.scheme != 'http' ||
          redirect.host != '127.0.0.1' ||
          redirect.port < 1 ||
          redirect.port > 65535 ||
          redirect.authority != '127.0.0.1:${redirect.port}' ||
          redirect.path != '/auth/callback' ||
          redirect.hasQuery ||
          redirect.hasFragment ||
          (clientId != null &&
              (clientId is! String ||
                  clientId.isEmpty ||
                  clientId.length > 512 ||
                  clientId == 'dynamic_agent_client' ||
                  RegExp(r'\s').hasMatch(clientId))) ||
          created is! int ||
          expires is! int ||
          expires <= created ||
          expires - created > const Duration(minutes: 15).inMilliseconds) {
        throw const ChatGptException('pending_authorization_invalid');
      }
      return _PendingSignIn(
        state: value['state'] as String,
        nonce: value['nonce'] as String,
        verifier: value['verifier'] as String,
        redirect: redirect,
        expectedClientId: clientId as String?,
        createdAt: created,
        expiresAt: expires,
      );
    } on ChatGptException {
      rethrow;
    } catch (_) {
      throw const ChatGptException('pending_authorization_invalid');
    }
  }
}

/// One independently stored ChatGPT OAuth registration and its account session.
class ChatGptSession extends ChangeNotifier {
  ChatGptSession({
    http.Client Function()? clientFactory,
    required Future<String?> Function() readState,
    required Future<void> Function(String) writeState,
    Future<bool> Function(Uri)? launchBrowser,
    Future<bool> Function(Map<String, dynamic>, String, String)?
    verifySignature,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 30),
    this.signInTimeout = const Duration(minutes: 15),
    this.responseTimeout = const Duration(minutes: 2),
    this.callbackMessage =
        'Sign-in callback received. Return to Selume to see the result.',
    this.agentName = 'Selume',
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _readState = readState,
       _writeState = writeState,
       _launchBrowser = launchBrowser ?? _openBrowser,
       _verifySignature = verifySignature ?? _verifyNative,
       _now = now ?? DateTime.now;

  static const _channel = MethodChannel('selume.chatgpt/crypto');
  static final _tokenUri = Uri.https(
    'auth.openai.com',
    '/api/accounts/oauth/token',
  );
  static final _discoveryUri = Uri.https(
    'auth.openai.com',
    '/.well-known/openid-configuration',
  );
  static const _resource = 'https://api.openai.com/v1';
  static const _scope =
      'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';

  final http.Client Function() _clientFactory;
  final Future<String?> Function() _readState;
  final Future<void> Function(String) _writeState;
  final Future<bool> Function(Uri) _launchBrowser;
  final Future<bool> Function(Map<String, dynamic>, String, String)
  _verifySignature;
  final DateTime Function() _now;
  final Duration requestTimeout;
  final Duration signInTimeout;
  final Duration responseTimeout;
  final String callbackMessage;
  final String agentName;
  Map<String, dynamic> _record = {};
  Map<String, dynamic>? _discovery;
  http.Client? _client;
  HttpServer? _server;
  Completer<AuthorizationResult>? _callback;
  _PendingSignIn? _pendingSignIn;
  Timer? _pendingExpiryTimer;
  Future<void>? _signInOperation;
  Future<void> _stateWriteTail = Future<void>.value();
  Future<void>? _pendingRemoval;
  Future<String>? _accessTokenOperation;
  Completer<void>? _activeOperation;
  bool _initialized = false;
  bool _needsPersistence = false;
  bool _disposed = false;
  bool _cancelled = false;
  bool _cancelling = false;
  bool _busy = false;
  String _phase = 'idle';
  String? _selectedModel;
  List<ChatGptModel> _models = [];
  final Map<String, bool> _steps = {};
  String _reply = '';
  String? _errorCode;
  int? _errorHttpStatus;
  String? _errorRequestId;
  String? _responseFormat;
  String? _responseBodyFormat;
  int? _responseBytes;
  String? _failedPhase;
  int? _failedElapsedSeconds;

  bool get busy => _busy || _cancelling;
  bool get signedIn =>
      _record['subject'] is String && _record['access_token'] is String;
  bool get planEnabled =>
      signedIn &&
      (_record['scopes'] as List? ?? []).contains('chatgpt.tokens.use.direct');
  String? get email => _record['email'] as String?;
  String? get selectedModel => _selectedModel;
  set selectedModel(String? value) {
    if (_busy || (value != null && !_models.any((model) => model.id == value)))
      return;
    _selectedModel = value;
    _notify();
  }

  List<ChatGptModel> get models => List.unmodifiable(_models);
  List<ChatGptStep> get steps =>
      List.unmodifiable(_steps.entries.map((e) => ChatGptStep(e.key, e.value)));
  String get reply => _reply;
  String get phase => _phase;
  String? get errorCode => _errorCode;
  int? get errorHttpStatus => _errorHttpStatus;
  String? get errorRequestId => _errorRequestId;
  String? get responseFormat => _responseFormat;
  String? get responseBodyFormat => _responseBodyFormat;
  int? get responseBytes => _responseBytes;
  String? get failedPhase => _failedPhase;
  int? get failedElapsedSeconds => _failedElapsedSeconds;
  bool get hasPendingSignIn => !_disposed && _pendingSignIn != null;
  bool get canPasteCallback =>
      !_disposed &&
      !_cancelled &&
      _pendingSignIn?.isValidAt(_now()) == true &&
      (_callback == null || !_callback!.isCompleted) &&
      {'waiting_browser', 'pending_authorization', 'idle'}.contains(_phase);

  static Future<bool> _openBrowser(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
  static Future<bool> _verifyNative(
    Map<String, dynamic> jwk,
    String input,
    String signature,
  ) async =>
      await _channel.invokeMethod<bool>('verifyRs256', {
        'n': jwk['n'],
        'e': jwk['e'],
        'input': input,
        'signature': signature,
      }) ??
      false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setPhase(String value) {
    _phase = value;
    _notify();
  }

  void _step(String code, bool passed) {
    _steps[code] = passed;
    _notify();
  }

  void _checkActive() {
    if (_disposed || _cancelled) throw const ChatGptException('cancelled');
  }

  Future<void> _run(String phase, Future<void> Function() action) async {
    if (_busy || _cancelling || _disposed) return;
    final operation = Completer<void>();
    _activeOperation = operation;
    _busy = true;
    _cancelled = false;
    _errorCode = null;
    _errorHttpStatus = null;
    _errorRequestId = null;
    _responseFormat = null;
    _responseBodyFormat = null;
    _responseBytes = null;
    _failedPhase = null;
    _failedElapsedSeconds = null;
    final elapsed = Stopwatch()..start();
    void fail(String code) {
      _failedPhase = _phase;
      _failedElapsedSeconds = elapsed.elapsed.inSeconds;
      _errorCode = code;
      _phase = code == 'cancelled' ? 'cancelled' : 'failed';
    }

    _setPhase(phase);
    try {
      _client = _clientFactory();
      await action();
    } on ChatGptException catch (error) {
      _errorHttpStatus = error.httpStatus;
      _errorRequestId = error.requestId;
      fail(error.code);
    } on TimeoutException {
      fail('timeout');
    } on SocketException {
      fail('network_error');
    } on http.ClientException {
      fail(_cancelled ? 'cancelled' : 'network_error');
    } on PlatformException {
      fail('platform_error');
    } catch (_) {
      // Raw exception messages can contain authorization URLs or response bodies.
      fail('unexpected_error');
    } finally {
      elapsed.stop();
      try {
        await _closeListener();
      } finally {
        _client?.close();
        _client = null;
        _busy = false;
        operation.complete();
        if (identical(_activeOperation, operation)) _activeOperation = null;
        _notify();
      }
    }
  }

  /// Resolves a fresh bearer for inference. Concurrent callers share one refresh
  /// so a rotating refresh token is never exchanged twice.
  Future<String> validAccessToken() {
    final existing = _accessTokenOperation;
    if (existing != null) return existing;
    if (_disposed) return Future.error(const ChatGptException('cancelled'));
    if (busy) return Future.error(const ChatGptException('authorization_busy'));
    final operation = _resolveAccessToken();
    _accessTokenOperation = operation;
    return operation;
  }

  Future<String> _resolveAccessToken() async {
    try {
      String? token;
      await _run('authorizing', () async {
        await _ensureSession();
        _checkActive();
        token = _record['access_token'] as String;
        _setPhase('signed_in');
      });
      if (_disposed || token == null || _errorCode != null) {
        throw ChatGptException(
          _disposed ? 'cancelled' : _errorCode ?? 'not_signed_in',
          httpStatus: _errorHttpStatus,
          requestId: _errorRequestId,
        );
      }
      return token!;
    } finally {
      _accessTokenOperation = null;
    }
  }

  /// Stops in-flight work and drains secure writes before the owner deletes
  /// its record. Normal widget disposal should keep the pending login instead.
  Future<void> close() async {
    final operation = _activeOperation?.future;
    if (!_disposed) dispose();
    await operation;
    await _stateWriteTail;
  }

  Future<void> initialize() => _run('initializing', () async {
    await _initialize();
    if (_pendingSignIn != null) {
      _setPhase('pending_authorization');
    } else if (signedIn) {
      _step('restored', true);
      _step('identity', true);
      _step('permission', planEnabled);
      _setPhase('restored');
    } else {
      _setPhase('idle');
    }
  });

  Future<void> _initialize() async {
    if (_initialized) return;
    String? saved;
    try {
      saved = await _readState();
    } catch (_) {
      throw const ChatGptException('storage_error');
    }
    _checkActive();
    if (saved != null) {
      try {
        final value = jsonDecode(saved);
        if (value is! Map<String, dynamic> ||
            value['ext_agent_host_id'] is! String) {
          throw const FormatException();
        }
        for (final key in [
          'client_id',
          'subject',
          'email',
          'access_token',
          'refresh_token',
          'id_token',
          'nonce',
        ]) {
          if (value[key] != null && value[key] is! String)
            throw const FormatException();
        }
        if (value['expires_at'] != null && value['expires_at'] is! int)
          throw const FormatException();
        if (value['scopes'] != null &&
            (value['scopes'] is! List ||
                !(value['scopes'] as List).every((s) => s is String))) {
          throw const FormatException();
        }
        if (value['client_id'] == 'dynamic_agent_client' ||
            (value['access_token'] != null &&
                (value['client_id'] == null ||
                    value['subject'] == null ||
                    value['expires_at'] == null))) {
          throw const FormatException();
        }
        _record = value;
      } catch (_) {
        throw const ChatGptException('storage_invalid');
      }
    } else {
      await _save({'ext_agent_host_id': newHostId()});
    }
    _initialized = true;
    if (_record.containsKey('pending_sign_in')) {
      try {
        final pending = _PendingSignIn.parse(_record['pending_sign_in']);
        if (pending.expectedClientId != _record['client_id']) {
          throw const ChatGptException('pending_authorization_invalid');
        }
        if (!pending.isValidAt(_now())) {
          throw const ChatGptException('authorization_timeout');
        }
        _pendingSignIn = pending;
        _armPendingExpiry(pending);
      } on ChatGptException {
        await _clearPendingSignIn();
        rethrow;
      }
    }
  }

  Future<void> _persistRecord(Map<String, dynamic> value) {
    final encoded = jsonEncode(value);
    final write = _stateWriteTail.then((_) async {
      try {
        await _writeState(encoded);
      } catch (_) {
        throw const ChatGptException('storage_error');
      }
    });
    // A failed write must not prevent a later cancel/cleanup from reaching storage.
    _stateWriteTail = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return write;
  }

  Future<void> _save(Map<String, dynamic> value) async {
    _checkActive();
    await _persistRecord(value);
    _checkActive();
    _record = value;
  }

  Future<void> _clearPendingSignIn() async {
    _pendingSignIn = null;
    _pendingExpiryTimer?.cancel();
    _pendingExpiryTimer = null;
    final pendingRemoval = _pendingRemoval;
    if (pendingRemoval != null) {
      await pendingRemoval;
      return;
    }
    if (!_record.containsKey('pending_sign_in')) return;
    final next = Map<String, dynamic>.from(_record)..remove('pending_sign_in');
    _record = next;
    final removal = _persistRecord(next);
    _pendingRemoval = removal;
    try {
      await removal;
    } finally {
      if (identical(_pendingRemoval, removal)) _pendingRemoval = null;
    }
  }

  void _armPendingExpiry(_PendingSignIn pending) {
    _pendingExpiryTimer?.cancel();
    _pendingExpiryTimer = Timer(
      Duration(milliseconds: pending.expiresAt - _now().millisecondsSinceEpoch),
      () => unawaited(_expirePending(pending)),
    );
  }

  Future<void> _expirePending(_PendingSignIn pending) async {
    if (_disposed || !identical(_pendingSignIn, pending)) return;
    final callback = _callback;
    if (callback != null && !callback.isCompleted) {
      callback.completeError(const ChatGptException('authorization_timeout'));
      return;
    }
    if (_busy) {
      _pendingExpiryTimer = Timer(
        const Duration(seconds: 1),
        () => unawaited(_expirePending(pending)),
      );
      return;
    }
    await _run('pending_authorization', () async {
      await _clearPendingSignIn();
      throw const ChatGptException('authorization_timeout');
    });
  }

  Future<void> signIn() {
    if (_busy || _cancelling || _disposed) return Future<void>.value();
    final operation = _run('registering', _startSignIn);
    _signInOperation = operation;
    return operation;
  }

  Future<void> _startSignIn() async {
    await _initialize();
    await _clearPendingSignIn();
    _steps.clear();
    _reply = '';
    final expectedClientId = _record['client_id'] as String?;
    final state = randomUrlToken();
    final nonce = randomUrlToken();
    final verifier = randomUrlToken(48);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _checkActive();
    final redirect = Uri.parse('http://127.0.0.1:${server.port}/auth/callback');
    final createdAt = _now().millisecondsSinceEpoch;
    final ttl = signInTimeout < const Duration(minutes: 15)
        ? signInTimeout
        : const Duration(minutes: 15);
    final pending = _PendingSignIn(
      state: state,
      nonce: nonce,
      verifier: verifier,
      redirect: redirect,
      expectedClientId: expectedClientId,
      createdAt: createdAt,
      expiresAt: createdAt + ttl.inMilliseconds,
    );
    _pendingSignIn = pending;
    try {
      // Publish the pending record before awaiting its queued write so cancellation
      // can queue a removal after it, even while secure storage is still writing.
      _record = {..._record, 'pending_sign_in': pending.toJson()};
      await _save(_record);
      final callback = Completer<AuthorizationResult>();
      _callback = callback;
      // Attach the error handler before launching, including synchronous test launchers.
      final callbackFuture = callback.future.timeout(
        ttl,
        onTimeout: () => throw const ChatGptException('authorization_timeout'),
      );
      _armPendingExpiry(pending);
      unawaited(
        callbackFuture.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        ),
      );
      server.listen(
        (request) async {
          try {
            request.response.headers.set(
              HttpHeaders.cacheControlHeader,
              'no-store',
            );
            request.response.headers.set('Referrer-Policy', 'no-referrer');
            request.response.headers.set(
              'Content-Security-Policy',
              "default-src 'none'",
            );
            request.response.headers.contentType = ContentType.html;
            if (request.method != 'GET' ||
                request.uri.path != '/auth/callback' ||
                request.headers.value(HttpHeaders.hostHeader) !=
                    '127.0.0.1:${server.port}' ||
                callback.isCompleted) {
              request.response.statusCode = HttpStatus.notFound;
            } else {
              AuthorizationResult? result;
              ChatGptException? failure;
              try {
                result = parseAuthorizationCallback(
                  redirect.replace(query: request.uri.query),
                  expectedState: state,
                  expectedClientId: expectedClientId,
                );
              } on ChatGptException catch (error) {
                failure = error;
              }
              request.response.write(
                '<!doctype html><html><meta charset="utf-8"><title>Selume</title>'
                '<p>${const HtmlEscape().convert(callbackMessage)}</p></html>',
              );
              await request.response.close();
              if (!callback.isCompleted) {
                if (failure != null) {
                  callback.completeError(failure);
                } else {
                  callback.complete(result!);
                }
              }
              return;
            }
            await request.response.close();
          } catch (_) {
            if (!callback.isCompleted)
              callback.completeError(const ChatGptException('callback_failed'));
          }
        },
        onError: (Object _) {
          if (!callback.isCompleted)
            callback.completeError(const ChatGptException('callback_failed'));
        },
      );
      final authorization = Uri.https(
        'auth.openai.com',
        '/api/accounts/authorize',
        {
          'client_id': expectedClientId ?? 'dynamic_agent_client',
          if (expectedClientId == null) 'agent_name_hint': agentName,
          'ext_agent_host_id': _record['ext_agent_host_id'] as String,
          if (expectedClientId != null && _record['id_token'] is String)
            'id_token_hint': _record['id_token'] as String,
          if (expectedClientId != null && email != null) 'login_hint': email!,
          if (signedIn && !planEnabled) 'prompt': 'consent',
          'response_type': 'code',
          'redirect_uri': redirect.toString(),
          'scope': _scope,
          'resource': _resource,
          'state': state,
          'nonce': nonce,
          'code_challenge_method': 'S256',
          'code_challenge': pkceChallenge(verifier),
        },
      );
      _setPhase('waiting_browser');
      if (!await _launchBrowser(authorization).timeout(
        requestTimeout,
        onTimeout: () => throw const ChatGptException('browser_launch_timeout'),
      ))
        throw const ChatGptException('browser_unavailable');
      final result = await callbackFuture;
      _checkActive();
      await _completeSignIn(result, pending);
    } finally {
      // A process exit keeps the encrypted pending request available for manual
      // recovery. Explicit cancellation, failure and timeout remove it instead.
      if (!_disposed && identical(_pendingSignIn, pending)) {
        await _clearPendingSignIn();
      }
    }
  }

  Future<void> _completeSignIn(
    AuthorizationResult result,
    _PendingSignIn pending,
  ) async {
    _checkActive();
    if (!identical(_pendingSignIn, pending)) {
      throw const ChatGptException('no_pending_authorization');
    }
    if (!pending.isValidAt(_now())) {
      await _clearPendingSignIn();
      throw const ChatGptException('authorization_timeout');
    }
    // This synchronously claims the single request before the storage await.
    // Never redeem a code unless removal from secure storage succeeds.
    await _clearPendingSignIn();
    _checkActive();
    _step('callback', true);
    await _closeListener();
    // Preserve the new issued client even if a code must be retried after invalid_grant.
    if (pending.expectedClientId == null)
      await _save({..._record, 'client_id': result.clientId});
    _setPhase('exchanging');
    final tokens = await _postForm(_tokenUri, {
      'grant_type': 'authorization_code',
      'client_id': result.clientId,
      'code': result.code,
      'code_verifier': pending.verifier,
      'redirect_uri': pending.redirect.toString(),
      'resource': _resource,
    });
    _setPhase('validating');
    final idToken = _requiredString(tokens, 'id_token');
    final identity = await _verifyIdentity(
      idToken,
      result.clientId,
      pending.nonce,
    );
    if (_record['subject'] != null && _record['subject'] != identity['sub']) {
      throw const ChatGptException('identity_mismatch');
    }
    final next = _tokenRecord(
      tokens,
      base: {
        ..._record,
        'subject': identity['sub'],
        'email': identity['email'] is String ? identity['email'] : null,
        'issuer': identity['iss'],
        'nonce': pending.nonce,
        'id_token': idToken,
      },
    );
    await _save(next);
    _models = [];
    _selectedModel = null;
    _step('identity', true);
    _step('permission', planEnabled);
    _setPhase('signed_in');
    if (!planEnabled) throw const ChatGptException('permission_missing');
  }

  Future<void> submitCallbackUrl(String raw) async {
    final pending = _pendingSignIn;
    if (_disposed || pending == null) {
      throw const ChatGptException('no_pending_authorization');
    }
    if (!pending.isValidAt(_now())) {
      await _expirePending(pending);
      if (_busy) await _signInOperation;
      throw const ChatGptException('authorization_timeout');
    }
    if (!canPasteCallback) {
      throw const ChatGptException('no_pending_authorization');
    }
    if (raw.length > 20 * 1024 || utf8.encode(raw).length > 20 * 1024) {
      throw const ChatGptException('invalid_callback');
    }
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.authority != pending.redirect.authority ||
        uri.path != pending.redirect.path ||
        uri.userInfo.isNotEmpty ||
        !uri.hasQuery ||
        uri.hasFragment) {
      throw const ChatGptException('invalid_callback');
    }
    AuthorizationResult? result;
    ChatGptException? denial;
    try {
      result = parseAuthorizationCallback(
        uri,
        expectedState: pending.state,
        expectedClientId: pending.expectedClientId,
      );
    } on ChatGptException catch (error) {
      if (error.code != 'oauth_access_denied' && error.code != 'oauth_error') {
        rethrow;
      }
      denial = error;
    }
    final callback = _callback;
    if (callback != null) {
      if (callback.isCompleted) {
        throw const ChatGptException('no_pending_authorization');
      }
      if (denial != null) {
        callback.completeError(denial);
      } else {
        callback.complete(result!);
      }
      await _signInOperation;
      return;
    }
    if (_busy) throw const ChatGptException('no_pending_authorization');
    final operation = _run('pending_authorization', () async {
      if (denial != null) {
        await _clearPendingSignIn();
        throw denial!;
      }
      await _completeSignIn(result!, pending);
    });
    _signInOperation = operation;
    await operation;
  }

  Future<void> cancelSignIn() async {
    if (_disposed ||
        _cancelling ||
        (!_busy && _pendingSignIn == null) ||
        ![
          'registering',
          'waiting_browser',
          'pending_authorization',
          'idle',
          'exchanging',
          'validating',
        ].contains(_phase))
      return;
    _cancelling = true;
    final operation = _signInOperation;
    try {
      _cancelled = true;
      ChatGptException? cleanupError;
      try {
        await _clearPendingSignIn();
      } on ChatGptException catch (error) {
        cleanupError = error;
      }
      final callback = _callback;
      if (callback != null && !callback.isCompleted)
        callback.completeError(const ChatGptException('cancelled'));
      _client?.close();
      await _closeListener();
      await operation;
      if (cleanupError != null) {
        _failedPhase = _phase;
        _errorCode = cleanupError.code;
        _phase = 'failed';
      } else if (!_busy) {
        _phase = 'cancelled';
        _errorCode = 'cancelled';
      }
    } finally {
      _cancelling = false;
    }
    _notify();
  }

  Future<void> _closeListener() async {
    final server = _server;
    _server = null;
    final callback = _callback;
    if (callback != null && !callback.isCompleted) {
      callback.completeError(const ChatGptException('cancelled'));
    }
    _callback = null;
    if (server != null) await server.close(force: true);
  }

  Future<Map<String, dynamic>> _getDiscovery() async {
    final result = _discovery ?? await _getJson(_discoveryUri);
    if (result['issuer'] != 'https://auth.openai.com')
      throw const ChatGptException('invalid_discovery');
    _discovery = result;
    return result;
  }

  Uri _authEndpoint(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'auth.openai.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const ChatGptException('invalid_discovery');
    }
    return uri;
  }

  Future<Map<String, dynamic>> _verifyIdentity(
    String token,
    String clientId,
    String nonce,
  ) async {
    final discovery = await _getDiscovery();
    final keys = await _getJson(_authEndpoint(discovery['jwks_uri']));
    final claims = await verifyIdToken(
      token,
      clientId: clientId,
      nonce: nonce,
      jwks: keys,
      verifySignature: _verifySignature,
      now: _now(),
    );
    _checkActive();
    return claims;
  }

  Future<void> loadModels() => _run('loading_models', () async {
    await _ensureSession();
    final body = await _getJson(
      Uri.https('api.openai.com', '/v1/models'),
      bearer: true,
    );
    if (body['models'] is! List)
      throw const ChatGptException('invalid_response');
    final seen = <String>{};
    final models = <ChatGptModel>[];
    for (final entry in body['models'] as List) {
      if (entry is Map &&
          entry['visibility'] == 'list' &&
          entry['slug'] is String &&
          (entry['slug'] as String).isNotEmpty &&
          seen.add(entry['slug'] as String)) {
        models.add(
          ChatGptModel(
            entry['slug'] as String,
            entry['display_name'] is String
                ? entry['display_name'] as String
                : entry['slug'] as String,
          ),
        );
      }
    }
    _models = models;
    if (!_models.any((m) => m.id == _selectedModel)) _selectedModel = null;
    _step('models', models.isNotEmpty);
    if (models.isEmpty) throw const ChatGptException('no_models');
    _setPhase('signed_in');
  });

  Future<void> _ensureSession() async {
    await _initialize();
    if (_needsPersistence) {
      await _save(_record);
      _needsPersistence = false;
    }
    if (!signedIn) throw const ChatGptException('not_signed_in');
    if (!planEnabled) throw const ChatGptException('permission_missing');
    final expiry = _record['expires_at'] as int? ?? 0;
    if (_now().millisecondsSinceEpoch + 60000 >= expiry) await _refresh();
    if (!planEnabled) throw const ChatGptException('permission_missing');
  }

  Future<void> sendTest() => _run('testing', () async {
    _resetTestResult();
    await _ensureSession();
    await _sendTest();
  });

  Future<void> refreshAndTest() => _run('refreshing', () async {
    _resetTestResult();
    await _initialize();
    if (!signedIn) throw const ChatGptException('not_signed_in');
    if (!planEnabled) throw const ChatGptException('permission_missing');
    await _refresh();
    if (!planEnabled) throw const ChatGptException('permission_missing');
    await _sendTest();
  });

  void _resetTestResult() {
    _reply = '';
    _step('response', false);
  }

  Future<void> _refresh() async {
    _step('refresh', false);
    _setPhase('refreshing');
    final refreshToken = _record['refresh_token'];
    if (refreshToken is! String || refreshToken.isEmpty)
      throw const ChatGptException('refresh_token_missing');
    Map<String, dynamic> tokens;
    try {
      tokens = await _postForm(_tokenUri, {
        'grant_type': 'refresh_token',
        'client_id': _record['client_id'] as String,
        'refresh_token': refreshToken,
        'resource': _resource,
      });
    } on ChatGptException catch (error) {
      if ({
        'invalid_grant',
        'invalid_refresh_token',
        'token_expired',
        'refresh_token_expired',
        'refresh_token_invalidated',
        'refresh_token_reused',
      }.contains(error.code))
        await _clearTokens();
      rethrow;
    }
    // Renew the existing session and retain the original verified identity/hint.
    // Persist rotating credentials without depending on another discovery/JWKS
    // request. A new ID token is not required to refresh the existing session.
    final next = _tokenRecord(tokens, base: _record, refresh: true);
    // If persistence fails, keep the latest rotating credential in memory;
    // retrying the already-consumed old refresh token could revoke the session.
    _record = next;
    _needsPersistence = true;
    await _save(next);
    _needsPersistence = false;
    _step('refresh', true);
    _step('permission', planEnabled);
  }

  Map<String, dynamic> _tokenRecord(
    Map<String, dynamic> tokens, {
    required Map<String, dynamic> base,
    bool refresh = false,
  }) {
    final accessToken = _requiredString(tokens, 'access_token');
    final type = tokens['token_type'];
    final expires = tokens['expires_in'];
    if (type is! String ||
        type.toLowerCase() != 'bearer' ||
        expires is! num ||
        !expires.isFinite ||
        expires <= 0) {
      throw const ChatGptException('invalid_token_response');
    }
    final scope = tokens['scope'];
    if (scope != null && scope is! String)
      throw const ChatGptException('invalid_token_response');
    final refreshToken = tokens['refresh_token'];
    if (refresh && refreshToken == null) {
      throw const ChatGptException('invalid_token_response');
    }
    if (refreshToken != null &&
        (refreshToken is! String || refreshToken.isEmpty))
      throw const ChatGptException('invalid_token_response');
    return {
      ...base,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_type': 'Bearer',
      // Keep this opaque until the public protocol specifies its type/units.
      if (tokens['earliest_refresh_at'] is num ||
          tokens['earliest_refresh_at'] is String)
        'earliest_refresh_at': tokens['earliest_refresh_at'],
      'expires_at': _now().millisecondsSinceEpoch + (expires * 1000).toInt(),
      'scopes': scope is String
          ? scope.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList()
          : (refresh ? base['scopes'] : <String>[]),
    };
  }

  Future<void> _sendTest() async {
    final model = _selectedModel;
    if (model == null || !_models.any((m) => m.id == model))
      throw const ChatGptException('model_required');
    _setPhase('testing');
    final request =
        http.Request('POST', Uri.https('api.openai.com', '/v1/responses'))
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer ${_record['access_token']}',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode({
            'model': model,
            'input': [
              {'role': 'user', 'content': 'Reply with exactly OK.'},
            ],
            'store': false,
            'stream': true,
          });
    final response = await _client!.send(request).timeout(requestTimeout);
    _checkActive();
    _responseFormat = _classifyResponseFormat(response.headers['content-type']);
    if (response.statusCode != 200) throw await _httpError(response);
    // A missing media type is not proof of an invalid body. Validate the same
    // stream below; only a completed Responses event can make this test pass.
    if (_responseFormat != 'event_stream' && _responseFormat != 'missing') {
      if (_responseFormat == 'json') throw await _httpError(response);
      throw ChatGptException(
        _responseFormat == 'html'
            ? 'unexpected_html_response'
            : 'unexpected_response_content_type',
        httpStatus: response.statusCode,
        requestId: _requestId(response),
      );
    }
    // Deliver the total deadline as an input error so the async* parser wakes
    // even when the server stops sending bytes. Cancelling it while it awaits
    // another chunk can otherwise wait indefinitely and mask the timeout.
    late final StreamSubscription<List<int>> source;
    final body = StreamController<List<int>>(
      onPause: () => source.pause(),
      onResume: () => source.resume(),
    );
    source = response.stream.listen(
      (chunk) {
        if (!body.isClosed) body.add(chunk);
      },
      onError: (Object error, StackTrace trace) {
        if (!body.isClosed) body.addError(error, trace);
      },
      onDone: () => unawaited(body.close()),
    );
    final done = Completer<void>();
    final subscription = readResponseText(_observeResponseBody(body.stream))
        .listen(
          (text) {
            if (_disposed || _cancelled) return;
            _reply += text;
            _notify();
          },
          onError: (Object error, StackTrace trace) {
            if (!done.isCompleted) done.completeError(error, trace);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    final deadline = Timer(responseTimeout, () {
      if (done.isCompleted || body.isClosed) return;
      body.addError(const ChatGptException('response_timeout'));
      unawaited(body.close());
    });
    try {
      await done.future;
      _checkActive();
    } on ChatGptException catch (error) {
      throw ChatGptException(
        error.code,
        httpStatus: response.statusCode,
        requestId: _requestId(response),
      );
    } finally {
      deadline.cancel();
      await source.cancel();
      await body.close();
      await subscription.cancel();
    }
    _step('response', true);
    _setPhase('completed');
  }

  Stream<List<int>> _observeResponseBody(Stream<List<int>> bytes) async* {
    // Retain at most a small prefix locally, never in persisted state or logs.
    // A prefix can reject a non-stream body; only the SSE parser verifies success.
    const maxPrefixBytes = 1024;
    final prefix = <int>[];
    _responseBytes = 0;
    _responseBodyFormat = 'unknown';
    await for (final chunk in bytes) {
      _responseBytes = _responseBytes! + chunk.length;
      if (_responseBodyFormat == 'unknown' && prefix.length < maxPrefixBytes) {
        prefix.addAll(chunk.take(maxPrefixBytes - prefix.length));
        final start = utf8.decode(prefix, allowMalformed: true).trimLeft();
        if (RegExp(
          r'^(?:<!doctype\s+html\b|<html\b|<head\b|<body\b)',
          caseSensitive: false,
        ).hasMatch(start)) {
          _responseBodyFormat = 'html';
          throw const ChatGptException('unexpected_html_response');
        }
        if (start.startsWith('{') || start.startsWith('[')) {
          _responseBodyFormat = 'json';
          throw const ChatGptException('unexpected_json_response');
        }
        if (RegExp(r'^(?::|(?:data|event|id|retry)(?::|\r|\n))')
            .hasMatch(start)) {
          _responseBodyFormat = 'event_stream';
        }
      }
      yield chunk;
    }
    if (_responseBytes == 0) {
      _responseBodyFormat = 'empty';
      throw const ChatGptException('empty_response_body');
    }
  }

  String _classifyResponseFormat(String? contentType) {
    final mediaType = contentType?.split(';').first.trim().toLowerCase() ?? '';
    if (mediaType.isEmpty) return 'missing';
    if (mediaType == 'text/event-stream') return 'event_stream';
    if (mediaType == 'application/json' ||
        (mediaType.startsWith('application/') && mediaType.endsWith('+json'))) {
      return 'json';
    }
    if (mediaType == 'text/html' || mediaType == 'application/xhtml+xml') {
      return 'html';
    }
    if (mediaType.startsWith('text/')) return 'text';
    return 'other';
  }

  Future<void> signOut() => _run('signing_out', () async {
    await _initialize();
    await _clearPendingSignIn();
    bool confirmed = true;
    final token = _record['refresh_token'];
    if (token is String && token.isNotEmpty) {
      confirmed = false;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final discovery = await _getDiscovery();
          final response = await _sendForm(
            _authEndpoint(discovery['revocation_endpoint']),
            {
              'token': token,
              'token_type_hint': 'refresh_token',
              'client_id': _record['client_id'] as String,
            },
          );
          if (response.statusCode == 200) {
            await response.stream.drain<void>().timeout(requestTimeout);
            confirmed = true;
            break;
          }
          await response.stream.drain<void>().timeout(requestTimeout);
          if (response.statusCode < 500) break;
        } catch (_) {
          // Revocation failure is reported after local sign-out; tokens never enter diagnostics.
        }
        if (attempt == 0)
          await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    await _clearTokens();
    _setPhase('signed_out');
    if (!confirmed)
      throw const ChatGptException('remote_revocation_unconfirmed');
  });

  Future<void> _clearTokens() async {
    final next = Map<String, dynamic>.from(_record);
    for (final key in [
      'access_token',
      'refresh_token',
      'id_token',
      'nonce',
      'token_type',
      'expires_at',
      'scopes',
      'earliest_refresh_at',
    ]) {
      next.remove(key);
    }
    // Immediately stop using credentials even if secure storage refuses the write.
    _record = next;
    _models = [];
    _selectedModel = null;
    _reply = '';
    _steps.clear();
    await _save(next);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri, {bool bearer = false}) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (bearer)
      request.headers['Authorization'] = 'Bearer ${_record['access_token']}';
    return _readJson(await _client!.send(request).timeout(requestTimeout));
  }

  Future<http.StreamedResponse> _sendForm(Uri uri, Map<String, String> fields) {
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json'
      ..bodyFields = fields;
    return _client!.send(request).timeout(requestTimeout);
  }

  Future<Map<String, dynamic>> _postForm(
    Uri uri,
    Map<String, String> fields,
  ) async => _readJson(await _sendForm(uri, fields));

  Future<Map<String, dynamic>> _readJson(http.StreamedResponse response) async {
    _checkActive();
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw await _httpError(response);
    final raw = await _readBody(response);
    _checkActive();
    try {
      final body = jsonDecode(raw);
      if (body is Map<String, dynamic>) return body;
    } catch (_) {
      /* Invalid bodies are never included in diagnostics. */
    }
    throw ChatGptException(
      'invalid_response',
      httpStatus: response.statusCode,
      requestId: _requestId(response),
    );
  }

  String _requiredString(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result is! String || result.isEmpty)
      throw const ChatGptException('invalid_token_response');
    return result;
  }

  Future<String> _readBody(http.StreamedResponse response) => response.stream
      .fold<List<int>>(<int>[], (bytes, chunk) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          throw const ChatGptException('response_too_large');
        }
        bytes.addAll(chunk);
        return bytes;
      })
      .then(utf8.decode)
      .timeout(requestTimeout);

  static const _knownErrors = {
    'access_denied',
    'invalid_grant',
    'invalid_client',
    'invalid_request',
    'invalid_scope',
    'invalid_refresh_token',
    'token_expired',
    'refresh_token_expired',
    'refresh_token_invalidated',
    'refresh_token_reused',
    'subscription_sharing_user_not_eligible',
    'subscription_sharing_usage_limit_exceeded',
    'subscription_sharing_usage_unavailable',
    'subscription_sharing_unsupported_capability',
    'subscription_sharing_route_not_supported',
    'subscription_sharing_invalid_user',
    'chatpass_v2_scope_not_authorized',
    'chatpass_v2_invalid_authorization_context',
    'subscription_sharing_user_unavailable',
    'model_not_found',
    'rate_limit_exceeded',
    'server_error',
  };
  Future<ChatGptException> _httpError(http.StreamedResponse response) async {
    var code = switch (response.statusCode) {
      200 => 'unexpected_json_response',
      401 => 'http_unauthorized',
      403 => 'http_forbidden',
      429 => 'http_rate_limited',
      503 => 'http_unavailable',
      >= 300 && < 400 => 'redirect_rejected',
      _ => 'http_error',
    };
    try {
      final raw = await _readBody(response);
      final body = jsonDecode(raw);
      final error = body is Map ? body['error'] : null;
      final candidate = error is Map
          ? error['code']
          : response.statusCode == 200
          ? null
          : error;
      if (_knownErrors.contains(candidate)) code = candidate as String;
    } catch (_) {
      /* Preserve HTTP metadata when an error body is absent or malformed. */
    }
    return ChatGptException(
      code,
      httpStatus: response.statusCode,
      requestId: _requestId(response),
    );
  }

  String? _requestId(http.StreamedResponse response) {
    final value =
        response.headers['x-request-id'] ??
        response.headers['openai-request-id'];
    return value != null && RegExp(r'^[A-Za-z0-9_-]{1,150}$').hasMatch(value)
        ? value
        : null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    _pendingExpiryTimer?.cancel();
    final callback = _callback;
    if (callback != null && !callback.isCompleted)
      callback.completeError(const ChatGptException('cancelled'));
    unawaited(_closeListener());
    _client?.close();
    super.dispose();
  }
}
