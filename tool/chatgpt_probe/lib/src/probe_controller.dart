import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moodiary_chatgpt/moodiary_chatgpt.dart';

export 'package:moodiary_chatgpt/moodiary_chatgpt.dart'
    show ChatGptModel, ChatGptStep;

typedef ProbeModel = ChatGptModel;
typedef ProbeStep = ChatGptStep;

/// Keeps the standalone verifier's registration separate from the diary app.
class ProbeController extends ChatGptSession {
  ProbeController({
    super.clientFactory,
    Future<String?> Function()? readState,
    Future<void> Function(String)? writeState,
    super.launchBrowser,
    Future<bool> Function(Map<String, dynamic>, String, String)?
    verifySignature,
    super.now,
    super.requestTimeout,
    super.signInTimeout,
    super.responseTimeout,
    super.callbackMessage = 'Sign-in callback received. Return to Selume ChatGPT Probe to see the result.',
  }) : super(
         readState: readState ?? _readSecureState,
         writeState: writeState ?? _writeSecureState,
         verifySignature: verifySignature ?? _verifyNative,
         agentName: 'Selume ChatGPT Probe',
       );

  static const _storageKey = 'selume_chatgpt_probe.registration.v1';
  static const _storage = FlutterSecureStorage();
  static const _channel = MethodChannel('selume.chatgpt_probe/crypto');

  static Future<String?> _readSecureState() => _storage.read(key: _storageKey);
  static Future<void> _writeSecureState(String value) =>
      _storage.write(key: _storageKey, value: value);
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
}
