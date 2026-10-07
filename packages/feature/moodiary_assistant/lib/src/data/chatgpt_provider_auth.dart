import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:moodiary_chatgpt/moodiary_chatgpt.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_storage/moodiary_storage.dart';

/// Owns one encrypted registration and one refresh coordinator per provider.
@lazySingleton
class ChatGptProviderAuth {
  ChatGptProviderAuth(this._secure);

  final ISecureKVStorage _secure;
  final _records = <String, _SessionRecord>{};
  final _deleting = <String, Future<void>>{};
  final _events = StreamController<void>.broadcast();

  Stream<void> get changes => _events.stream;

  static String storageKey(String id) => 'chatgpt_subscription_v1_$id';

  ChatGptSession session(String id, {String? callbackMessage}) {
    if (_deleting.containsKey(id)) {
      throw const ChatGptException('cancelled');
    }
    return _records.putIfAbsent(id, () {
      final record = _SessionRecord();
      record.session = ChatGptSession(
        readState: () => _secure.get(storageKey(id)),
        writeState: (value) {
          final write = record.writes.then((_) async {
            if (record.closed) throw const ChatGptException('cancelled');
            await _secure.set(storageKey(id), value);
            if (!record.closed) _events.add(null);
          });
          record.writes = write.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          );
          return write;
        },
        callbackMessage:
            callbackMessage ?? l10n.assistant.chatGptCallbackReceived,
      );
      return record;
    }).session;
  }

  /// Readiness never refreshes or sends a network request.
  Future<bool> hasCredentials(String id) async {
    if (_deleting.containsKey(id)) return false;
    final raw = await _secure.get(storageKey(id));
    if (raw == null) return false;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return false;
      bool populated(String key) =>
          value[key] is String && (value[key] as String).isNotEmpty;
      final scopes = value['scopes'];
      final expiry = value['expires_at'];
      return populated('ext_agent_host_id') &&
          populated('client_id') &&
          value['client_id'] != 'dynamic_agent_client' &&
          populated('subject') &&
          populated('access_token') &&
          scopes is List &&
          scopes.every((scope) => scope is String) &&
          scopes.contains('chatgpt.tokens.use.direct') &&
          expiry is int &&
          ((expiry > DateTime.now().millisecondsSinceEpoch) ||
              populated('refresh_token'));
    } on FormatException {
      return false;
    }
  }

  Future<String> getAccessToken(String id) => session(id).validAccessToken();

  List<ChatGptModel> cachedModels(String id) =>
      _records[id]?.session.models ?? const [];

  /// Stop the writer first, drain any write already in progress, then delete.
  /// A delayed OAuth completion must not recreate credentials after deletion.
  Future<void> remove(String id) {
    final existing = _deleting[id];
    if (existing != null) return existing;
    final record = _records.remove(id);
    record?.closed = true;
    final operation = () async {
      if (record != null) {
        await record.session.close();
        await record.writes;
      }
      await _secure.remove(storageKey(id));
      _events.add(null);
    }();
    _deleting[id] = operation;
    return operation.whenComplete(() => _deleting.remove(id));
  }

  @disposeMethod
  void dispose() {
    for (final record in _records.values) {
      record.closed = true;
      record.session.dispose();
    }
    _records.clear();
    unawaited(_events.close());
  }
}

class _SessionRecord {
  late final ChatGptSession session;
  Future<void> writes = Future<void>.value();
  bool closed = false;
}
