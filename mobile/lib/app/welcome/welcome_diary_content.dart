import 'dart:convert';

import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

Diary buildWelcomeDiary({required String imageName}) {
  final content = jsonEncode({
    'type': 'doc',
    'content': [
      _paragraph(l10n.app.welcomeDiary.intro),
      _heading(l10n.app.welcomeDiary.writingHeading),
      _paragraph(l10n.app.welcomeDiary.writingInstructions),
      {
        'type': 'paragraph',
        'content': [
          _text(l10n.app.welcomeDiary.boldExample, mark: 'bold'),
          _text(' '),
          _text(l10n.app.welcomeDiary.italicExample, mark: 'italic'),
        ],
      },
      {
        'type': 'blockquote',
        'content': [_paragraph(l10n.app.welcomeDiary.quoteExample)],
      },
      _paragraph(l10n.app.welcomeDiary.syntaxInstructions),
      {
        'type': 'codeBlock',
        'attrs': {'language': 'markdown'},
        'content': [_text(l10n.app.welcomeDiary.syntaxExample)],
      },
      _heading(l10n.app.welcomeDiary.tagsHeading),
      _paragraph(l10n.app.welcomeDiary.tagsInstructions),
      {
        'type': 'paragraph',
        'content': [
          {
            'type': 'text',
            'text': '#${l10n.app.welcomeDiary.exampleTag}',
            'marks': [
              {
                'type': 'tag',
                'attrs': {'tag': l10n.app.welcomeDiary.exampleTag},
              },
            ],
          },
        ],
      },
      _paragraph(l10n.app.welcomeDiary.tagsNavigation),
      _heading(l10n.app.welcomeDiary.imagesHeading),
      _paragraph(l10n.app.welcomeDiary.imagesInstructions),
      {
        'type': 'image',
        'attrs': {
          'src': imageName,
          'alt': l10n.app.welcomeDiary.imageAlt,
          'widthPercent': 100,
        },
      },
      _paragraph(l10n.app.welcomeDiary.imageCaption),
      _heading(l10n.app.welcomeDiary.linksHeading),
      {
        'type': 'orderedList',
        'attrs': {'start': 1},
        'content': [
          _listItem(l10n.app.welcomeDiary.linksCreate),
          _listItem(l10n.app.welcomeDiary.linksInsert),
          _listItem(l10n.app.welcomeDiary.linksExplore),
        ],
      },
      _heading(l10n.app.welcomeDiary.detailsHeading),
      {
        'type': 'bulletList',
        'content': [
          _listItem(l10n.app.welcomeDiary.detailsMood),
          _listItem(l10n.app.welcomeDiary.detailsTools),
        ],
      },
      _heading(l10n.app.welcomeDiary.tryHeading),
      {
        'type': 'taskList',
        'content': [
          _taskItem(l10n.app.welcomeDiary.taskRead, checked: true),
          _taskItem(l10n.app.welcomeDiary.taskWrite),
          _taskItem(l10n.app.welcomeDiary.taskPhoto),
        ],
      },
      _paragraph(l10n.app.welcomeDiary.saving),
      _paragraph(l10n.app.welcomeDiary.closing),
    ],
  });
  final parsed = TiptapContent.parse(content);
  final media = parsed.media;
  return Diary.create(
    title: l10n.app.welcomeDiary.title,
    content: content,
    contentText: parsed.plainText,
    mood: .neutral,
    imageName: media.images,
    audioName: media.audios,
    videoName: media.videos,
    tags: TiptapContent.tags(content),
    type: .tiptap,
  );
}

Map<String, Object> _text(String text, {String? mark}) => {
  'type': 'text',
  'text': text,
  if (mark != null)
    'marks': [
      {'type': mark},
    ],
};

Map<String, Object> _paragraph(String text) => {
  'type': 'paragraph',
  'content': [_text(text)],
};

Map<String, Object> _heading(String text) => {
  'type': 'heading',
  'attrs': {'level': 2},
  'content': [_text(text)],
};

Map<String, Object> _listItem(String text) => {
  'type': 'listItem',
  'content': [_paragraph(text)],
};

Map<String, Object> _taskItem(String text, {bool checked = false}) => {
  'type': 'taskItem',
  'attrs': {'checked': checked},
  'content': [_paragraph(text)],
};
