import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_diary/src/presentation/widget/diary_entry_tile.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

Diary _diary({List<String> tags = const []}) => Diary(
  id: 'entry-id',
  categoryId: 'legacy-category',
  title: 'Entry title',
  content: '',
  contentText: 'Entry text',
  time: DateTime(2026, 7, 20, 9, 15),
  lastModified: DateTime(2026, 7, 20, 9, 15),
  show: true,
  mood: .neutral,
  imageName: const [],
  audioName: const [],
  videoName: const [],
  tags: tags,
  type: DiaryType.tiptap.value,
);

void main() {
  testWidgets('shared calendar and map entries show the first saved tag', (
    tester,
  ) async {
    for (final showDate in [false, true]) {
      final diary = _diary(tags: ['生活/旅行', '工作']);
      await tester.pumpWidget(
        muiTestApp(DiaryEntryTile(diary: diary, showDate: showDate)),
      );
      await tester.pumpAndSettle();

      expect(find.text('#生活/旅行'), findsOneWidget);
      expect(find.text('#工作'), findsNothing);
      expect(
        find.text(
          showDate
              ? TimeFormat.compactDateTime(diary.time)
              : TimeFormat.clock(diary.time),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('long first tag leaves room for the map entry date', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      muiTestApp(
        DiaryEntryTile(
          diary: _diary(tags: ['生活/旅行/很长的地点标签名称']),
          showDate: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('#生活/旅行/很长的地点标签名称'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a shared entry routes with the diary ID', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: DiaryEntryTile(diary: _diary(tags: ['生活/旅行'])),
          ),
        ),
        GoRoute(
          path: DiaryRoute.path,
          builder: (_, state) =>
              Scaffold(body: Text('opened:${state.params['diary_id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MuiTheme(
          data: buildMuiTheme(brightness: Brightness.light),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entry title'));
    await tester.pumpAndSettle();
    expect(find.text('opened:entry-id'), findsOneWidget);
  });
}
