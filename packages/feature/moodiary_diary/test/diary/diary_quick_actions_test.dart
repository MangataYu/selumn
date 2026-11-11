import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_components/moodiary_components.dart' show DiaryShare;
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/presentation/detail/diary_version_history_page.dart';
import 'package:moodiary_diary/src/presentation/widget/diary_quick_actions.dart';
import 'package:moodiary_diary/src/presentation/widget/diary_tile_frame.dart';
import 'package:moodiary_diary/src/presentation/widget/feed_tile.dart';
import 'package:moodiary_diary/src/presentation/widget/timeline_tile.dart';
import 'package:moodiary_editor/moodiary_editor.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
import 'package:moodiary_utils/moodiary_utils.dart' show TimeFormat;
import 'package:mui/mui.dart';

import '../support/pump.dart';

class _HistoryRepository extends Fake implements DiaryRepository {
  _HistoryRepository({this.versions = const [], this.onRestore});

  final List<DiaryVersion> versions;
  final Future<void> Function()? onRestore;
  final diaryIds = <String>[];
  final restores = <(String, DiaryVersion)>[];

  @override
  Future<List<DiaryVersion>> getDiaryVersions(
    String id, {
    int? limit,
    int? beforeId,
  }) async {
    diaryIds.add(id);
    return versions;
  }

  @override
  Future<bool> restoreDiaryVersion(String diaryId, DiaryVersion version) async {
    restores.add((diaryId, version));
    await onRestore?.call();
    return true;
  }
}

class _EditorServer extends Fake implements EditorLocalServer {
  @override
  MediaResolver? mediaResolver;

  @override
  Future<String?> Function(String name)? mediaNameResolver;

  @override
  Future<void> ensureStarted() async {
    throw StateError('native WebView disabled in this widget test');
  }
}

Diary _diary(String id) =>
    Diary.empty(type: .tiptap)
        .copyWith(id: id, title: 'Title of $id', contentText: 'Body of $id');

DiaryTimelineTile _timelineTile(Diary diary, {bool selecting = false}) =>
    DiaryTimelineTile(
      diary: diary,
      stamp: diary.time,
      dayStart: true,
      breakBefore: false,
      selecting: selecting,
    );

Future<void> _openMenu(WidgetTester tester, Finder anchor) async {
  await tester.tap(anchor);
  await tester.pumpAndSettle();
}

Finder _popupSurface(Finder item) => find.ancestor(
  of: item,
  matching: find.byWidgetPredicate(
    (widget) => widget is Material && widget.type == MaterialType.card,
  ),
);

void main() {
  testWidgets('feed menu opens below and dispatches actions for its diary', (
    tester,
  ) async {
    final first = _diary('first');
    final second = _diary('second');
    final history = _HistoryRepository();
    final sharedDiaryIds = <String>[];
    var openedDiary = false;
    getIt.pushNewScope(
      init: (getIt) => getIt.registerSingleton<DiaryRepository>(history),
    );
    addTearDown(getIt.popScope);
    DiaryShare.register((_, id) async => sharedDiaryIds.add(id));

    final router = GoRouter(
      routes: [
        GoRoute(
          path: DiaryHomeRoute.path,
          builder: (_, _) => Scaffold(
            body: ListView(
              children: [
                DiaryFeedTile(diary: first),
                DiaryFeedTile(
                  diary: second,
                  key: const ValueKey('second'),
                  onTap: () => openedDiary = true,
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: DiaryRoute.path,
          builder: (_, state) => Scaffold(
            body: Text(
              'Diary ${state.params['diary_id']} ${state.params['edit']}',
            ),
          ),
        ),
        GoRoute(
          path: AssistantConversationRoute.path,
          builder: (_, state) => Scaffold(
            body: Text('Assistant ${state.params['cited_diary_id']}'),
          ),
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

    final tile = find.byKey(const ValueKey('second'));
    final anchor = find.descendant(
      of: tile,
      matching: find.byTooltip(l10n.common.more),
    );
    final anchorRect = tester.getRect(anchor);
    expect(anchorRect.center.dx, greaterThan(tester.getCenter(tile).dx));
    await _openMenu(tester, anchor);
    expect(openedDiary, isFalse);

    final labels = [
      l10n.diary.edit,
      l10n.diary.askAssistant,
      l10n.diary.share,
      l10n.diary.versionHistory,
    ];
    final icon = find.descendant(
      of: tile,
      matching: find.byIcon(LucideIcons.ellipsis),
    );
    var previousBottom = tester.getRect(icon).bottom;
    for (final label in labels) {
      final item = find.text(label);
      expect(item, findsOneWidget);
      final rect = tester.getRect(item);
      expect(rect.top, greaterThan(previousBottom));
      previousBottom = rect.bottom;
    }

    await tester.tap(find.text(l10n.diary.edit));
    await tester.pumpAndSettle();
    expect(find.text('Diary second true'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await _openMenu(tester, anchor);
    await tester.tap(find.text(l10n.diary.askAssistant));
    await tester.pumpAndSettle();
    expect(find.text('Assistant second'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await _openMenu(tester, anchor);
    await tester.tap(find.text(l10n.diary.share));
    await tester.pumpAndSettle();
    expect(sharedDiaryIds, ['second']);

    await _openMenu(tester, anchor);
    await tester.tap(find.text(l10n.diary.versionHistory));
    await tester.pumpAndSettle();
    expect(find.byType(DiaryVersionHistoryPage), findsOneWidget);
    expect(history.diaryIds, ['second']);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tile, findsOneWidget);
    expect(find.text('Diary second false'), findsNothing);
  });

  for (final restoreFromPreview in [false, true]) {
    final origin = restoreFromPreview ? 'timeline preview' : 'feed history';
    testWidgets('restoring from $origin opens the same diary in read mode', (
      tester,
    ) async {
      final diary = _diary('origin');
      final snapshot = (id: 7, diary: diary.copyWith(title: 'Archived title'));
      final showTile = ValueNotifier(true);
      addTearDown(showTile.dispose);
      final restoreGate = Completer<void>();
      final history = _HistoryRepository(
        versions: [snapshot],
        onRestore: () {
          if (!restoreFromPreview) showTile.value = false;
          return restoreGate.future;
        },
      );
      getIt.pushNewScope(
        init: (getIt) {
          getIt.registerSingleton<DiaryRepository>(history);
          getIt.registerSingleton<IKVStorage>(MemoryKVStorage());
          getIt.registerSingleton<ThemeManager>(ThemeManager());
          getIt.registerSingleton<EditorLocalServer>(_EditorServer());
        },
      );
      addTearDown(getIt.popScope);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: DiaryHomeRoute.path,
            builder: (_, _) => Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: showTile,
                builder: (_, visible, _) => ListView(
                  children: [
                    if (visible)
                      if (restoreFromPreview)
                        _timelineTile(diary)
                      else
                        DiaryFeedTile(diary: diary),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: DiaryRoute.path,
            builder: (_, state) => Scaffold(
              body: Text(
                'Diary ${state.params['diary_id']} ${state.params['edit']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp.router(
            theme: buildMuiTheme(brightness: Brightness.light),
            builder: FlutterSmartDialog.init(),
            localizationsDelegates: const [
              ...GlobalMaterialLocalizations.delegates,
              GlobalMuiLocalizations.delegate,
            ],
            supportedLocales: AppLocaleUtils.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _openMenu(tester, find.byTooltip(l10n.common.more));
      await tester.tap(find.text(l10n.diary.versionHistory));
      await tester.pumpAndSettle();
      if (restoreFromPreview) {
        await tester.tap(find.text(snapshot.diary.title));
        await tester.pumpAndSettle();
        expect(find.byType(MoodiaryEditor), findsOneWidget);
      }

      await tester.tap(find.byTooltip(l10n.diary.versionHistoryRestore));
      await tester.pumpAndSettle();
      expect(history.restores, isEmpty);
      await tester.tap(find.text(l10n.diary.recycleRestore));
      await tester.pumpAndSettle();
      expect(history.restores, [(diary.id, snapshot)]);
      expect(find.text('Diary origin false'), findsNothing);
      if (!restoreFromPreview) {
        expect(find.byType(DiaryFeedTile, skipOffstage: false), findsNothing);
      }

      restoreGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Diary origin false'), findsOneWidget);
      expect(
        find.byType(DiaryVersionHistoryPage, skipOffstage: false),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  }

  for (final isTimeline in [false, true]) {
    final mode = isTimeline ? 'timeline' : 'feed';
    testWidgets('$mode menu opens close above an entry near the bottom', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 760);
      addTearDown(tester.view.reset);
      final diary = _diary('bottom').copyWith(type: DiaryType.richText.value);
      await tester.pumpWidget(
        muiTestApp(
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: 150,
              child: isTimeline
                  ? _timelineTile(diary)
                  : DiaryFeedTile(diary: diary),
            ),
          ),
        ),
      );

      final icon = find.byIcon(LucideIcons.ellipsis);
      final iconTop = tester.getRect(icon).top;
      await _openMenu(tester, find.byTooltip(l10n.common.more));
      final lastItem = find.text(l10n.diary.versionHistory);
      expect(lastItem, findsOneWidget);
      final menu = tester.getRect(_popupSurface(lastItem));
      expect(iconTop - menu.bottom, inInclusiveRange(1.0, 8.0));
      await tester.tap(find.text(l10n.diary.edit));
      await tester.pumpAndSettle();
      expect(lastItem, findsOneWidget);
    });
  }

  for (final (width, textScale) in [(390.0, 1.0), (320.0, 1.5)]) {
    testWidgets('both menus align and open close below at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 760);
      addTearDown(tester.view.reset);
      final diary = _diary('alignment')
          .copyWith(time: DateTime(DateTime.now().year, 1, 2, 9, 17));

      await tester.pumpWidget(
        muiTestApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: ListView(
                children: [
                  DiaryFeedTile(diary: diary),
                  _timelineTile(diary),
                ],
              ),
            ),
          ),
        ),
      );

      final rows = [
        (
          find.byType(DiaryFeedTile),
          find.textContaining(
            TimeFormat.compactDateTime(diary.time),
            findRichText: true,
          ),
        ),
        (
          find.byType(DiaryTimelineTile),
          find.text(TimeFormat.clock(diary.time)),
        ),
      ];
      for (final (tile, timestamp) in rows) {
        final anchor = find.descendant(
          of: tile,
          matching: find.byTooltip(l10n.common.more),
        );
        final icon = find.descendant(
          of: tile,
          matching: find.byIcon(LucideIcons.ellipsis),
        );
        final time = find.descendant(of: tile, matching: timestamp);
        final iconRect = tester.getRect(icon);
        final iconCenter = iconRect.center;
        final tapTarget = tester.getRect(anchor);
        expect(tapTarget.size, const Size(48, 48));
        expect(tapTarget.contains(iconCenter), isTrue);
        expect(iconCenter.dy, closeTo(tester.getCenter(time).dy, 0.5));
        expect(iconCenter.dx, greaterThan(tester.getRect(time).right));

        await tester.tapAt(iconCenter);
        await tester.pumpAndSettle();
        final edit = find.text(l10n.diary.edit);
        expect(edit, findsOneWidget);
        final menu = tester.getRect(_popupSurface(edit));
        expect(menu.top - iconRect.bottom, inInclusiveRange(1.0, 8.0));
        Navigator.of(tester.element(tile)).pop();
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('feed and timeline use selection marks during selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      muiTestApp(
        ListView(
          children: [
            DiaryFeedTile(diary: _diary('feed'), selecting: true),
            _timelineTile(_diary('timeline'), selecting: true),
          ],
        ),
      ),
    );
    expect(find.byType(DiaryQuickActions), findsNothing);
    expect(find.byType(DiarySelectMark), findsNWidgets(2));
  });
}
