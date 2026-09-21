import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

Diary _diary(
  String id, {
  String text = '正文',
  List<String> images = const [],
  List<String> audio = const [],
  bool show = true,
  DateTime? time,
}) => Diary.empty(type: .markdown).copyWith(
  id: id,
  content: text,
  contentText: text,
  imageName: images,
  audioName: audio,
  show: show,
  time: time ?? DateTime(2026, 1, 1),
  lastModified: time ?? DateTime(2026, 1, 1),
);

class _LinkScanInterceptor extends QueryInterceptor {
  int scans = 0;
  Completer<void>? scanned;
  Completer<void>? resume;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('"diaries"."content"') &&
        statement.contains('"diaries"."type"') &&
        !statement.contains('"diaries"."title"')) {
      scans++;
      final gate = resume;
      if (gate != null) {
        resume = null;
        scanned!.complete();
        await gate.future;
      }
    }
    return rows;
  }
}

void main() {
  late MoodiaryDatabase db;
  late DiaryRepository repository;
  late _LinkScanInterceptor interceptor;

  setUp(() {
    interceptor = _LinkScanInterceptor();
    db = MoodiaryDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
      ).interceptWith(interceptor),
    );
    repository = DiaryRepository(db);
    getIt.registerSingleton<DiaryRepository>(repository);
    getIt.registerSingleton<IKVStorage>(MemoryKVStorage());
  });

  tearDown(() async {
    await db.close();
    await getIt.reset();
  });

  test(
    'media filters deduplicate attachments and apply before pagination',
    () async {
      await repository.insertDiaries([
        _diary('a', images: ['image-1.webp', 'image-2.webp']),
        _diary('b', audio: ['audio-1.m4a']),
        _diary('c', images: ['image-3.webp'], audio: ['audio-2.m4a']),
        _diary('d'),
        _diary('hidden', images: ['image-4.webp'], show: false),
      ]);
      expect(
        (await repository.getDiaryByTag(content: .images)).map((d) => d.id),
        ['c', 'a'],
      );
      expect(
        (await repository.getDiaryByTag(content: .audio)).map((d) => d.id),
        ['c', 'b'],
      );
      expect(
        (await repository.getDiaryByTag(
          content: .images,
          offset: 1,
          limit: 1,
        )).single.id,
        'a',
      );
      expect(
        (await repository.diaryCountByMonth(content: .images)).values.single,
        2,
      );
      expect(
        (await repository.diaryCountByMonth(content: .audio)).values.single,
        2,
      );
    },
  );

  test('link SQL pages and month counts reuse the parsed ID cache', () async {
    await repository.insertDiaries([
      _diary(
        'a',
        text: '[链接](https://example.com)',
        time: DateTime(2026, 1, 1),
      ),
      _diary('b', text: '无链接', time: DateTime(2026, 2, 1)),
      _diary('c', text: 'https://example.org', time: DateTime(2026, 3, 1)),
      _diary('hidden', text: 'https://example.net', show: false),
    ]);
    expect(
      (await repository.getDiaryByTag(content: .links, limit: 1)).single.id,
      'c',
    );
    expect(
      (await repository.getDiaryByTag(
        content: .links,
        offset: 1,
        limit: 1,
      )).single.id,
      'a',
    );
    expect(await repository.diaryCountByMonth(content: .links), {
      DateTime(2026, 1): 1,
      DateTime(2026, 3): 1,
    });
    expect(interceptor.scans, 1);
  });

  test(
    'link cache follows sync, edits, recycle restore and permanent deletion',
    () async {
      Future<List<String>> ids() async => [
        for (final diary in await repository.getDiaryByTag(content: .links))
          diary.id,
      ];
      expect(await ids(), isEmpty);
      final diary = _diary('a', text: 'https://example.com');
      await repository.insertADiary(diary, fromSync: true);
      expect(await ids(), ['a']);
      await repository.updateADiary(
        newDiary: diary.copyWith(content: '已移除链接'),
        fromSync: true,
      );
      expect(await ids(), isEmpty);
      await repository.updateADiary(newDiary: diary);
      expect(await ids(), ['a']);
      await repository.setVisibility(diary, show: false);
      expect(await ids(), isEmpty);
      await repository.setVisibility(diary, show: true);
      expect(await ids(), ['a']);
      await repository.deleteDiariesByIds(['a']);
      expect(await ids(), isEmpty);
    },
  );

  test(
    'a write during the first link scan cannot publish stale cached IDs',
    () async {
      await repository.insertADiary(_diary('old'));
      interceptor.scanned = Completer<void>();
      final resume = interceptor.resume = Completer<void>();
      final initial = repository.getDiaryByTag(content: .links);
      await interceptor.scanned!.future;
      await repository.insertADiary(
        _diary('new', text: 'https://example.com'),
        fromSync: true,
      );
      resume.complete();
      expect((await initial).single.id, 'new');
      expect(
        (await repository.getDiaryByTag(content: .links)).single.id,
        'new',
      );
      expect(interceptor.scans, 2);
    },
  );

  test(
    'content-filtered controllers apply matching and removed content events',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = diaryControllerProvider(content: .links);
      container.listen(provider, (_, _) {});
      expect(await container.read(provider.future), isEmpty);
      final diary = _diary('link', text: 'https://example.com');
      await repository.insertADiary(diary);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).requireValue.single.id, 'link');
      await repository.insertADiary(_diary('no-link'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).requireValue.single.id, 'link');
      await repository.updateADiary(newDiary: diary.copyWith(content: '移除链接'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).requireValue, isEmpty);
    },
  );

  test('mixed content recognizes hyperlinks and excludes media and code', () {
    bool tiptap(List<Map<String, dynamic>> content) =>
        DiaryContent.containsLinks(
          jsonEncode({'type': 'doc', 'content': content}),
          .tiptap,
        );
    expect(
      tiptap([
        {
          'type': 'diaryLink',
          'attrs': {'id': 'target'},
        },
      ]),
      isTrue,
    );
    expect(
      tiptap([
        {
          'type': 'text',
          'text': '网址',
          'marks': [
            {
              'type': 'link',
              'attrs': {'href': 'https://example.com'},
            },
          ],
        },
      ]),
      isTrue,
    );
    expect(
      tiptap([
        {
          'type': 'image',
          'attrs': {'src': 'https://example.com/photo.png'},
        },
      ]),
      isFalse,
    );
    expect(
      tiptap([
        {
          'type': 'codeBlock',
          'content': [
            {'type': 'text', 'text': 'https://example.com'},
          ],
        },
      ]),
      isFalse,
    );
    expect(
      tiptap([
        {
          'type': 'text',
          'text': 'https://example.com',
          'marks': [
            {'type': 'code'},
          ],
        },
      ]),
      isFalse,
    );
    expect(
      DiaryContent.containsLinks(
        jsonEncode([
          {
            'insert': '网址',
            'attributes': {'link': 'https://example.com'},
          },
        ]),
        .richText,
      ),
      isTrue,
    );
    expect(
      DiaryContent.containsLinks(
        jsonEncode({
          'ops': [
            {
              'insert': {'image': 'https://example.com/a.png'},
            },
          ],
        }),
        .richText,
      ),
      isFalse,
    );
    expect(
      DiaryContent.containsLinks(
        '![图片](https://example.com/photo.png)',
        .markdown,
      ),
      isFalse,
    );
    expect(
      DiaryContent.containsLinks('`https://example.com`', .markdown),
      isFalse,
    );
    expect(
      DiaryContent.containsLinks('[网址](https://example.com)', .markdown),
      isTrue,
    );
    expect(
      DiaryContent.containsLinks('旧格式 www.example.com', .markdown),
      isTrue,
    );
  });

  test(
    'legacy code lines and reference images do not match link queries',
    () async {
      final quillCode = jsonEncode([
        {'insert': 'https://example.com'},
        {
          'insert': '\n',
          'attributes': {'code-block': true},
        },
      ]);
      final quillMixed = jsonEncode({
        'ops': [
          {'insert': 'https://example.com'},
          {
            'insert': '\n',
            'attributes': {'code-block': 'dart'},
          },
          {'insert': '外部正文 https://example.org\n'},
        ],
      });
      const referenceImage = '![图片][p]\n\n[p]: https://example.com/photo.png';
      const referenceLink = '[网页][p]\n\n[p]: https://example.com';
      await repository.insertDiaries([
        _diary(
          'code',
          text: quillCode,
        ).copyWith(type: DiaryType.richText.value),
        _diary(
          'mixed',
          text: quillMixed,
        ).copyWith(type: DiaryType.richText.value),
        _diary('image', text: referenceImage),
        _diary('link', text: referenceLink),
      ]);
      expect(
        (await repository.getDiaryByTag(content: .links))
            .map((diary) => diary.id)
            .toSet(),
        {'mixed', 'link'},
      );
      expect(
        (await repository.diaryCountByMonth(content: .links)).values.single,
        2,
      );
    },
  );

  test('tag text and URL metadata remain excluded from link detection', () {
    final content = jsonEncode({
      'type': 'doc',
      'content': [
        {
          'type': 'text',
          'text': '#https://example.com',
          'marks': [
            {
              'type': 'tag',
              'attrs': {'tag': 'https://example.com'},
            },
          ],
        },
        {
          'type': 'audio',
          'attrs': {'src': 'https://example.org/voice.m4a'},
        },
      ],
    });
    expect(DiaryContent.containsLinks(content, .tiptap), isFalse);
    expect(
      DiaryContent.containsLinks('https://example.com', .markdown),
      isTrue,
    );
    expect(DiaryContent.containsLinks('www.example.com', .markdown), isTrue);
  });
}
