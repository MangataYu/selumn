import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:moodiary_assistant/src/application/diary_citation.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';

final RegExp _hiddenCharacters = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F'
  r'\u200B\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u206F\uFEFF]',
);

final RegExp _sentenceEnd = RegExp(r'[\r\n。！？!?]+|\.(?:\s|$)');

/// A display-only fallback: the empty persisted title remains eligible for AI.
String localSessionTitle(String text) {
  final body = splitDiaryCitation(text).text
      .replaceAll(_hiddenCharacters, '')
      .trim();
  if (body == continueTurnMarker) return '';
  final sentence = body
      .split(_sentenceEnd)
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  return sentence.characters.take(24).toString().trimRight();
}
