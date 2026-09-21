import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/welcome/welcome_diary_content.dart';
import 'package:moodiary_mobile/app/welcome/welcome_diary_seeder.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

Iterable<Map<String, dynamic>> _nodes(Map<String, dynamic> node) sync* {
  yield node;
  final children = node['content'];
  if (children is List) {
    for (final child in children) {
      if (child is Map<String, dynamic>) yield* _nodes(child);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => LocaleSettings.setLocale(AppLocale.zh));

  for (final (locale, title, tag) in [
    (AppLocale.zh, '欢迎来到 Selume · 你的第一篇日记', '入门/样例'),
    (
      AppLocale.en,
      'Welcome to Selume · Your first entry',
      'Getting-started/Example',
    ),
  ]) {
    test('${locale.languageCode} 欢迎正文保留可编辑样例与正确的派生数据', () async {
      await LocaleSettings.setLocale(locale);
      const imageName = 'image-welcome-test.jpg';

      final diary = buildWelcomeDiary(imageName: imageName);
      final parsed = TiptapContent.parse(diary.content);
      final document = jsonDecode(diary.content) as Map<String, dynamic>;
      final nodes = _nodes(document).toList();

      expect(diary.title, title);
      expect(diary.type, DiaryType.tiptap.value);
      expect(diary.show, isTrue);
      expect(parsed.isDoc, isTrue);
      expect(document['type'], 'doc');
      expect(parsed.headings, hasLength(6));
      expect(parsed.headings.every((heading) => heading.level == 2), isTrue);
      expect(
        nodes.map((node) => node['type']).toSet(),
        containsAll([
          'heading',
          'blockquote',
          'codeBlock',
          'orderedList',
          'bulletList',
          'taskList',
        ]),
      );

      final marks = nodes.expand(
        (node) => (node['marks'] as List<dynamic>?) ?? const [],
      );
      expect(
        marks.map((mark) => (mark as Map<String, dynamic>)['type']).toSet(),
        containsAll(['bold', 'italic', 'tag']),
      );
      final tasks = nodes.where((node) => node['type'] == 'taskItem');
      expect(
        tasks.map((node) => (node['attrs'] as Map<String, dynamic>)['checked']),
        containsAll([true, false]),
      );

      final image = nodes.singleWhere((node) => node['type'] == 'image');
      final imageAttrs = image['attrs'] as Map<String, dynamic>;
      expect(imageAttrs['src'], imageName);
      expect(imageAttrs['alt'], l10n.app.welcomeDiary.imageAlt);
      expect(parsed.media.images, [imageName]);
      expect(diary.imageName, parsed.media.images);
      expect(diary.audioName, isEmpty);
      expect(diary.videoName, isEmpty);
      expect(TiptapContent.tags(diary.content), [tag]);
      expect(diary.tags, TiptapContent.tags(diary.content));

      expect(parsed.links, isEmpty);
      expect(nodes.where((node) => node['type'] == 'diaryLink'), isEmpty);
      expect(diary.contentText, parsed.plainText);
      expect(diary.contentText, contains(l10n.app.welcomeDiary.intro));
      expect(diary.contentText, contains(l10n.app.welcomeDiary.linksInsert));
      expect(diary.contentText, contains('#$tag'));
    });
  }

  test('欢迎配图作为 JPEG 资产打包且可由 Flutter 解码', () async {
    final data = await rootBundle.load(WelcomeDiarySeeder.imageAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    expect(bytes.take(3), [0xff, 0xd8, 0xff]);

    final codec = await ui.instantiateImageCodec(bytes);
    addTearDown(codec.dispose);
    final frame = await codec.getNextFrame();
    addTearDown(frame.image.dispose);
    expect(frame.image.width, greaterThan(0));
    expect(frame.image.height, greaterThan(0));
  });
}
