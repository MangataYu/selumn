import 'dart:async';
import 'dart:convert';

import 'package:moodiary_assistant/src/data/assistant.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/chat_repository.dart';
import 'package:moodiary_assistant/src/data/model_resolver.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_models/moodiary_models.dart';

class SessionTitleController {
  final Set<String> _inFlight = <String>{};
  final Set<String> _saving = <String>{};

  Future<ChatSession?> maybeTitleAndSave({
    required ChatSession session,
    required String firstUserText,
    required LlmProvider provider,
    required String model,
    required String apiKey,
    Duration timeout = assistantTitleTimeout,
  }) async {
    if (!_saving.add(session.id)) return null;
    try {
      final repo = getIt<ChatRepository>();
      final current = await repo.getSession(session.id);
      if (current == null || current.title.trim().isNotEmpty) return current;
      final updated = await maybeTitle(
        session: current,
        firstUserText: firstUserText,
        provider: provider,
        model: model,
        apiKey: apiKey,
        timeout: timeout,
      );
      if (updated == null) return null;
      await repo.setSessionTitleIfEmpty(session.id, updated.title);
      return await repo.getSession(session.id);
    } catch (error, stack) {
      logger.e(
        'Assistant session title persistence failed',
        error: error.runtimeType,
        stackTrace: stack,
      );
      return null;
    } finally {
      _saving.remove(session.id);
    }
  }

  Future<ChatSession?> maybeTitle({
    required ChatSession session,
    required String firstUserText,
    required LlmProvider provider,
    required String model,
    required String apiKey,
    Duration timeout = assistantTitleTimeout,
  }) async {
    if (session.title.trim().isNotEmpty) return null;
    if (_inFlight.contains(session.id)) return null;
    final seed = firstUserText.trim();
    if (seed.isEmpty) return null;

    final framed = _frameTitleInput(seed);

    _inFlight.add(session.id);
    try {
      for (var attempt = 0; attempt <= assistantTitleRetries; attempt++) {
        try {
          final raw = await _generate(
            provider: provider,
            model: model,
            apiKey: apiKey,
            framed: framed,
            timeout: timeout,
          );
          final title = normalizeSessionTitle(
            raw,
            maxBytes: assistantTitleMaxBytes,
          );
          if (title.isNotEmpty) {
            return session.copyWith(title: title);
          }
        } catch (error, stack) {
          logger.e(
            'Assistant session title generation failed',
            error: error.runtimeType,
            stackTrace: stack,
          );
        }
      }
      return null;
    } finally {
      _inFlight.remove(session.id);
    }
  }

  Future<String> _generate({
    required LlmProvider provider,
    required String model,
    required String apiKey,
    required String framed,
    required Duration timeout,
  }) async {
    final route = ModelResolver.resolve(provider, model);
    final request = AssistantChatRequest(
      type: route.protocol,
      baseUrl: route.baseUrl,
      apiKey: apiKey,
      model: route.modelId,
      systemPrompt: buildTitleSystemPrompt(),
      maxTokens: assistantTitleMaxOutputTokens,
      history: [.user(framed)],
      tools: false,
    );

    final buffer = StringBuffer();
    final done = Completer<void>();
    final sub = getIt<AssistantService>()
        .chat(request)
        .listen(
          (event) {
            if (event.kind == .text) buffer.write(event.text);
          },
          onError: (Object error, StackTrace stack) {
            if (!done.isCompleted) done.completeError(error, stack);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    try {
      await done.future.timeout(timeout);
      return buffer.toString();
    } finally {
      await sub.cancel();
    }
  }
}

String _frameTitleInput(String seed) {
  const prefix =
      'Generate the session title from this JSON array of user messages:\n';
  final available =
      assistantTitleMaxInputBytes -
      utf8.encode('$prefix${jsonEncode([''])}').length;
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in seed.runes) {
    final char = String.fromCharCode(rune);
    // Count JSON escaping as well as UTF-8 bytes, excluding the string quotes.
    final bytes = utf8.encode(jsonEncode(char)).length - 2;
    if (used + bytes > available) break;
    buffer.write(char);
    used += bytes;
  }
  return '$prefix${jsonEncode([buffer.toString()])}';
}

final RegExp _controlCharacter = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]',
);

final RegExp _directionalControl = RegExp(
  r'[\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF]',
);

final RegExp _thinkBlock = RegExp(
  r'<think>[\s\S]*?</think>',
  caseSensitive: false,
);

String normalizeSessionTitle(String input, {required int maxBytes}) {
  final body = input.replaceAll(_thinkBlock, '');
  final line = body
      .split('\n')
      .map(
        (e) => e
            .replaceAll(_controlCharacter, '')
            .replaceAll(_directionalControl, '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
      )
      .firstWhere((e) => e.isNotEmpty, orElse: () => '');
  return _truncateUtf8(line, maxBytes).trimRight();
}

String _truncateUtf8(String input, int maxBytes) {
  if (utf8.encode(input).length <= maxBytes) return input;
  final buffer = StringBuffer();
  var used = 0;
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final bytes = utf8.encode(char).length;
    if (used + bytes > maxBytes) break;
    buffer.write(char);
    used += bytes;
  }
  return buffer.toString();
}
