import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_diary/src/presentation/widget/diary_tile_frame.dart';
import 'package:moodiary_diary/src/presentation/widget/feed_tile.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:mui/mui.dart';

final _mui = buildMuiTheme(brightness: Brightness.light);

Diary diary({
  String title = 'T',
  String text = 'body',
  DiaryMood mood = .neutral,
  List<String> images = const [],
  List<String> videos = const [],
  List<String> audios = const [],
  List<String> tags = const [],
  DiaryWeather? weather,
}) => Diary(
  id: 'test',
  title: title,
  content: '',
  contentText: text,
  time: DateTime(2026, 7, 20, 9, 15),
  lastModified: DateTime(2026, 7, 20, 9, 15),
  show: true,
  mood: mood,
  weather: weather,
  imageName: images,
  audioName: audios,
  videoName: videos,
  tags: tags,
  type: DiaryType.tiptap.value,
);

Place place() => Place(
  id: 'p',
  name: '厦门 环岛路',
  latitude: 1,
  longitude: 2,
  lastModified: DateTime(2026),
);

Widget wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) =>
    MuiTheme(
      data: _mui,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Scaffold(body: ListView(children: [child])),
      ),
    );

void main() {
  setUpAll(() {
    try {
      PlatformService.get().applicationSupportPath = '/tmp/moodiary-test';
    } catch (_) {}
  });

  testWidgets('renders text-only entry inside a ListView without error', (
    t,
  ) async {
    await t.pumpWidget(wrap(DiaryFeedTile(diary: diary(title: '标题在这'))));
    expect(t.takeException(), isNull);
    expect(find.textContaining('标题在这', findRichText: true), findsOneWidget);
  });

  testWidgets('untitled entry keeps paragraphs as a multiline note', (t) async {
    const body = '第一段记录当时的感受。\n\n第二段想一想发生了什么。';
    await t.pumpWidget(
      wrap(
        DiaryFeedTile(
          diary: diary(title: '', text: body),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    final text = find.text(body);
    expect(text, findsOneWidget);
    final note = t.widget<Text>(text);
    expect(note.maxLines, greaterThan(1));
    expect(
      t.getSize(text).height,
      greaterThan(note.style!.fontSize! * note.style!.height! * 2),
    );
  });

  testWidgets('date, weather and place precede the note body', (t) async {
    await t.pumpWidget(
      wrap(
        DiaryFeedTile(
          diary: diary(
            weather: const DiaryWeather(icon: '100', temp: '26', text: '晴'),
          ),
          place: place(),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    final meta = t.widgetList<Text>(find.byType(Text)).firstWhere((w) {
      final s = w.textSpan?.toPlainText() ?? '';
      return s.contains('26°');
    });
    final plain = meta.textSpan!.toPlainText();
    expect(plain, isNot(contains('work')));
    expect(plain, contains('厦门 环岛路'));
    expect(
      t.getBottomLeft(find.textContaining('26°', findRichText: true)).dy,
      lessThan(t.getTopLeft(find.text('body')).dy),
    );
  });

  testWidgets('tag tap filters without opening the diary', (t) async {
    final tags = <String>[];
    var opened = false;
    await t.pumpWidget(
      wrap(
        DiaryFeedTile(
          diary: diary(tags: const ['生活/旅行']),
          onTap: () => opened = true,
          onTagTap: tags.add,
        ),
      ),
    );
    await t.tap(find.text('#生活/旅行'));
    expect(tags, ['生活/旅行']);
    expect(opened, isFalse);
  });

  testWidgets('all tags remain visible below the note body', (t) async {
    await t.pumpWidget(
      wrap(DiaryFeedTile(diary: diary(tags: const ['a', 'b', 'c']))),
    );
    expect(find.text('#a'), findsOneWidget);
    expect(find.text('#b'), findsOneWidget);
    expect(find.text('#c'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('#a')).dy,
      greaterThan(t.getBottomLeft(find.text('body')).dy),
    );
  });

  testWidgets('selecting adds a corner mark without hiding the tags', (
    t,
  ) async {
    await t.pumpWidget(
      wrap(
        DiaryFeedTile(
          diary: diary(tags: const ['a']),
          selecting: true,
          selected: true,
        ),
      ),
    );
    expect(find.byType(DiarySelectMark), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.text('#a'), findsOneWidget);
  });

  testWidgets('audio-only entry shows the waveform bar', (t) async {
    await t.pumpWidget(
      wrap(DiaryFeedTile(diary: diary(audios: const ['a.m4a']))),
    );
    expect(t.takeException(), isNull);
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
  });

  testWidgets('body stays above media for titled and untitled notes', (
    t,
  ) async {
    for (final title in ['标题', '']) {
      for (final images in [
        const ['1.jpg'],
        const ['1.jpg', '2.jpg'],
      ]) {
        const body = '第一段正文\n\n第二段也需要展示';
        await t.pumpWidget(
          wrap(
            DiaryFeedTile(
              diary: diary(title: title, text: body, images: images),
            ),
          ),
        );
        expect(t.takeException(), isNull);
        expect(find.text(body), findsOneWidget);
        expect(find.byType(Image), findsNWidgets(images.length));
        expect(
          t.getTopLeft(find.byType(Image).first).dy,
          greaterThan(t.getBottomLeft(find.text(body)).dy),
        );
      }
    }
  });

  testWidgets('more than three media cells collapse into a +N overlay', (
    t,
  ) async {
    await t.pumpWidget(
      wrap(
        DiaryFeedTile(
          diary: diary(
            images: const ['1.jpg', '2.jpg', '3.jpg', '4.jpg', '5.jpg'],
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('+2'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(3));
  });

  testWidgets('long tags wrap without overflowing on a narrow screen', (
    t,
  ) async {
    t.view.physicalSize = const Size(360 * 3, 800 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);

    const long = '夏天的第一杯冰美式与午后的碎碎念';
    for (final images in [
      const <String>[],
      const ['1.jpg'],
      const ['1.jpg', '2.jpg', '3.jpg'],
    ]) {
      await t.pumpWidget(
        wrap(
          DiaryFeedTile(
            diary: diary(
              images: images,
              tags: const [long, long],
              weather: const DiaryWeather(icon: '100', temp: '26', text: '晴'),
            ),
            place: place(),
          ),
        ),
      );
      expect(t.takeException(), isNull, reason: '图片数=${images.length}');
    }
  });

  testWidgets('long tags and selection remain usable at larger text scale', (
    t,
  ) async {
    t.view.physicalSize = const Size(360 * 3, 800 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);

    await t.pumpWidget(
      wrap(
        DiaryFeedTile(
          diary: diary(
            images: const ['1.jpg'],
            tags: const ['一个相当长的标签名字', '另一个也不短的标签', '认识自己'],
          ),
          selecting: true,
          selected: true,
          syncState: .dirty,
        ),
        textScaler: const .linear(1.5),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('#认识自己'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(find.byIcon(LucideIcons.cloudUpload), findsOneWidget);
    expect(
      t
          .getRect(find.byType(DiarySyncBadge))
          .overlaps(t.getRect(find.byType(DiarySelectMark))),
      isFalse,
    );
  });

  testWidgets('audio stays visible when the entry also has images', (t) async {
    await t.pumpWidget(
      wrap(
        DiaryFeedTile(
          diary: diary(images: const ['1.jpg'], audios: const ['a.m4a']),
        ),
      ),
    );
    expect(find.byIcon(LucideIcons.mic), findsOneWidget);
  });

  testWidgets('the shown timestamp follows the sort key', (t) async {
    final d = Diary(
      id: 'x',
      title: 'T',
      content: '',
      contentText: 'body',
      time: DateTime(2026, 7, 1, 9, 15),
      lastModified: DateTime(2026, 8, 20, 21, 30),
      show: true,
      mood: .neutral,
      imageName: const [],
      audioName: const [],
      videoName: const [],
      tags: const [],
      type: DiaryType.tiptap.value,
    );

    await t.pumpWidget(wrap(DiaryFeedTile(diary: d, sort: .timeDesc)));
    expect(find.textContaining('7/1', findRichText: true), findsOneWidget);

    await t.pumpWidget(wrap(DiaryFeedTile(diary: d, sort: .lastModifiedDesc)));
    expect(find.textContaining('8/20', findRichText: true), findsOneWidget);
  });

  testWidgets('video takes the first cell and is marked as playable', (
    t,
  ) async {
    await t.pumpWidget(
      wrap(
        DiaryFeedTile(
          diary: diary(videos: const ['video-1.mp4'], images: const ['1.jpg']),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.byIcon(LucideIcons.circlePlay), findsOneWidget);
  });
}
