import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/assistant_tools.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

const _imageName = 'image-diary-edit.jpg';
const _audioName = 'audio-diary-edit.m4a';
const _videoName = 'video-diary-edit.mp4';
const _media =
    '''
![照片]($_imageName)

![语音]($_audioName)

![视频]($_videoName)
''';
const _tail = '应保留的最后一段 🧡';

Future<String> _run(AssistantTool tool, Map<String, dynamic> input) =>
    AssistantToolRegistry.byId(tool.id)!.run(input);

Future<String> _edit(List<Map<String, dynamic>> items) =>
    _run(.updateDiary, {'items': items});

List<dynamic> _blocks(Diary diary) =>
    (jsonDecode(diary.content) as Map<String, dynamic>)['content'] as List;

void main() {
  late Directory mediaRoot;
  late MoodiaryDatabase db;
  late DiaryRepository repository;

  setUpAll(() async {
    mediaRoot = await Directory.systemTemp.createTemp('assistant-diary-edit-');
    PlatformService.get().applicationSupportPath = mediaRoot.path;
    await AppFiles.initCreateDir();
  });

  tearDownAll(() async => mediaRoot.delete(recursive: true));

  setUp(() {
    db = MoodiaryDatabase.forTesting(NativeDatabase.memory());
    repository = DiaryRepository(db);
    getIt.registerSingleton<DiaryRepository>(repository);
  });

  tearDown(() async {
    await getIt.reset();
    await repository.dispose();
    await db.close();
  });

  Future<Diary> create(String body) async {
    final content = MarkdownToTiptap.convert(body)!;
    final diary = withDerivedMedia(
      Diary.empty(type: .tiptap).copyWith(
        title: '初始标题',
        content: content,
        contentText: TiptapContent.parse(content).plainText,
        tags: ['生活/测试'],
      ),
    );
    await repository.insertADiary(diary);
    return (await repository.getDiaryByBusinessId(diary.id))!;
  }

  Future<Diary> saved(Diary diary) async =>
      (await repository.getDiaryByBusinessId(diary.id))!;

  test(
    'title-only rename preserves the long body and attachment files',
    () async {
      final original = await create(
        '${'日' * 4100} 📝\n\n---\n\n$_media\n$_tail',
      );
      expect(
        _blocks(original).any((block) => block['type'] == 'horizontalRule'),
        isTrue,
      );
      expect(original.imageName, [_imageName]);
      expect(original.audioName, [_audioName]);
      expect(original.videoName, [_videoName]);
      final attachments = [
        for (final (kind, name) in [
          ('image', _imageName),
          ('audio', _audioName),
          ('video', _videoName),
        ])
          await File(AppFiles.getRealPath(kind, name)).writeAsString(name),
      ];

      final read = await _run(.getDiary, {
        'ids': [original.id],
      });
      expect(read, contains('truncated'));
      expect(read, isNot(contains(_tail)));
      expect(
        await _edit([
          {'id': original.id, 'title': '误传标题', 'content': '日' * 4000},
        ]),
        startsWith('Failed:'),
      );
      expect(await saved(original), original);

      expect(
        await _run(.renameDiary, {
          'items': [
            {'id': original.id, 'title': '新标题 🎉'},
          ],
        }),
        startsWith('Updated '),
      );
      final renamed = await saved(original);
      expect(renamed.title, '新标题 🎉');
      expect(renamed.contentText, contains(_tail));
      expect(
        renamed.copyWith(
          title: original.title,
          lastModified: original.lastModified,
        ),
        original,
      );
      expect(
        await Future.wait(attachments.map((file) => file.readAsString())),
        [_imageName, _audioName, _videoName],
      );
    },
  );

  test(
    'a Unicode-safe truncated read cannot be saved as a full body',
    () async {
      final prefix = '中' * 3999;
      final original = await create('$prefix😄\n\n---\n\n$_tail');

      final read = await _run(.getDiary, {
        'ids': [original.id],
      });
      expect(read, contains(prefix));
      expect(read, contains('truncated'));
      expect(read, isNot(contains(_tail)));
      expect(utf8.decode(utf8.encode(read)), read);
      expect(
        await _edit([
          {'id': original.id, 'content': prefix, 'mood': 'angry'},
        ]),
        startsWith('Failed:'),
      );
      expect(await saved(original), original);
    },
  );

  test('a stale short text cache cannot bypass the saved body limit', () async {
    final body = '${'中' * 4100}\n\n---\n\n$_tail';
    final original = Diary.empty(type: .tiptap)
        .copyWith(content: MarkdownToTiptap.convert(body)!, contentText: '旧缓存');
    await repository.insertADiary(original);
    final before = await saved(original);
    expect(before.contentText, '旧缓存');

    expect(
      await _edit([
        {'id': original.id, 'content': '旧缓存'},
      ]),
      startsWith('Failed:'),
    );
    expect(await saved(original), before);
  });

  test('prepend and append splice around the existing TipTap blocks', () async {
    final original = await create('${'长' * 4100} 🌱\n\n---\n\n$_media\n$_tail');
    final originalBlocks = _blocks(original);

    expect(
      await _edit([
        {'id': original.id, 'prepend': '# 新开头 🐱', 'append': '**新结尾** ✨'},
      ]),
      startsWith('Updated '),
    );
    final updated = await saved(original);
    final blocks = _blocks(updated);
    expect(blocks.sublist(1, blocks.length - 1), originalBlocks);
    expect(updated.contentText, startsWith('新开头 🐱'));
    expect(updated.contentText, contains(_tail));
    expect(updated.contentText, endsWith('新结尾 ✨'));
    expect(updated.imageName, original.imageName);
    expect(updated.audioName, original.audioName);
    expect(updated.videoName, original.videoName);
    expect(
      (await repository.getDiaryVersions(original.id)).single.diary,
      original,
    );
  });

  test('adding to legacy Markdown keeps its raw source and media', () async {
    const source = '旧正文 🍃\n\n---\n\n![照片]($_imageName)\n\n原结尾';
    final original = Diary.empty(type: .markdown).copyWith(
      title: '旧格式',
      content: source,
      contentText: MarkdownConverter.convert(source),
      imageName: [_imageName],
    );
    await repository.insertADiary(original);

    expect(
      await _edit([
        {'id': original.id, 'prepend': '序言', 'append': '补记 👋'},
      ]),
      startsWith('Updated '),
    );
    final updated = await saved(original);
    expect(updated.type, DiaryType.markdown.value);
    expect(updated.content, '序言\n\n$source\n\n补记 👋');
    expect(updated.imageName, [_imageName]);
    expect(updated.contentText, contains('补记 👋'));
  });

  test(
    'legacy Markdown addition cannot change how the old body parses',
    () async {
      const source = '旧段落\n\n---\n\n旧结尾';
      final original = Diary.empty(type: .markdown).copyWith(
        content: source,
        contentText: MarkdownConverter.convert(source),
      );
      await repository.insertADiary(original);
      final before = await saved(original);
      expect(
        await _edit([
          {'id': original.id, 'prepend': '```\n不闭合的代码块'},
        ]),
        startsWith('Failed:'),
      );
      expect(await saved(original), before);
    },
  );

  test('complete replacement retains structurally referenced media', () async {
    final original = await create('旧正文\n\n$_media');
    expect(
      await _edit([
        {'id': original.id, 'content': '## 新正文 🌻\n\n---\n\n$_media\n新结尾'},
      ]),
      startsWith('Updated '),
    );
    final updated = await saved(original);
    expect(updated.contentText, contains('新正文 🌻'));
    expect(updated.contentText, isNot(contains('旧正文')));
    expect(
      _blocks(updated).any((block) => block['type'] == 'horizontalRule'),
      isTrue,
    );
    expect(updated.imageName, original.imageName);
    expect(updated.audioName, original.audioName);
    expect(updated.videoName, original.videoName);
  });

  test('body edits cannot add unowned local attachment references', () async {
    final tiptap = await create('原始正文');
    final markdown = Diary.empty(type: .markdown)
        .copyWith(content: '旧格式正文', contentText: '旧格式正文');
    await repository.insertADiary(markdown);
    final before = await saved(markdown);
    for (final item in [
      {'id': tiptap.id, 'append': '![照片](image-other-diary.jpg)'},
      {'id': tiptap.id, 'content': '![照片](image-other-diary.jpg)'},
      {'id': markdown.id, 'append': '![照片][photo]\n\n[photo]: relative.jpg'},
    ]) {
      expect(await _edit([item]), contains('already owned by this diary'));
    }
    expect(await saved(tiptap), tiptap);
    expect(await saved(markdown), before);
  });

  test(
    'full replacement must explicitly name each missing attachment',
    () async {
      final original = await create('旧正文\n\n$_media');
      const replacement = '新正文\n\n![照片]($_imageName)\n\n![视频]($_videoName)';

      for (final fields in <Map<String, dynamic>>[
        {'content': '$replacement\n\n正文提到 $_audioName'},
        {
          'content': replacement,
          'removeMedia': ['audio-unknown.m4a'],
        },
        {
          'content': replacement,
          'removeMedia': [' '],
        },
        {'content': replacement, 'removeMedia': _audioName},
        {
          'content': replacement,
          'removeMedia': [42],
        },
        {
          'append': '补记',
          'removeMedia': [_audioName],
        },
      ]) {
        expect(
          await _edit([
            {'id': original.id, ...fields},
          ]),
          startsWith('Failed:'),
        );
        expect(await saved(original), original);
      }

      expect(
        await _edit([
          {
            'id': original.id,
            'content': replacement,
            'removeMedia': [_audioName],
          },
        ]),
        startsWith('Updated '),
      );
      final updated = await saved(original);
      expect(updated.contentText, contains('新正文'));
      expect(updated.imageName, original.imageName);
      expect(updated.audioName, isEmpty);
      expect(updated.videoName, original.videoName);
    },
  );

  test(
    'batch isolates the item mixing replacement and block addition',
    () async {
      final original = await create('旧正文');
      final other = Diary.empty(type: .markdown)
          .copyWith(content: '另一篇', contentText: '另一篇');
      await repository.insertADiary(other);

      final result = await _edit([
        {
          'id': original.id,
          'content': '不应覆盖',
          'append': '不应追加',
          'mood': 'angry',
        },
        {'id': other.id, 'append': '允许追加'},
      ]);

      expect(result, contains('Failed:'));
      expect(result, contains('Updated '));
      expect(await saved(original), original);
      expect((await saved(other)).content, '另一篇\n\n允许追加');
    },
  );
}
