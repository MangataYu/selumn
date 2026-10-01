import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_desktop/app/home/diary_navigation.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/moodiary_diary.dart';
import 'package:moodiary_diary/src/presentation/detail/diary_page.dart';
import 'package:moodiary_editor/moodiary_editor.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
import 'package:mui/mui.dart';

class _DiaryRepository extends Fake implements DiaryRepository {
  final diaries = <String, Diary>{};
  bool failWrites = false;
  bool failReads = false;
  String? delayedReadId;
  Completer<Diary?>? delayedRead;
  int writes = 0;

  @override
  Stream<DiaryEvent> get diaryEvents => const Stream.empty();

  @override
  Future<Diary?> getDiaryByBusinessId(String id) async {
    if (failReads) throw StateError('storage unavailable');
    if (id == delayedReadId) return delayedRead!.future;
    return diaries[id];
  }

  @override
  Future<List<Diary>> getForwardLinks(String id) async => [];

  @override
  Future<List<Diary>> getBacklinks(String id) async => [];

  @override
  Future<void> insertADiary(
    Diary diary, {
    bool fromSync = false,
    IndexMode index = .inline,
  }) async {
    writes++;
    if (failWrites) throw StateError('storage unavailable');
    diaries[diary.id] = diary;
  }

  @override
  Future<void> updateADiary({
    required Diary newDiary,
    IndexMode index = .inline,
    bool fromSync = false,
  }) => insertADiary(newDiary, fromSync: fromSync, index: index);

  @override
  Future<bool> hardDeleteDiary(String id) async => diaries.remove(id) != null;
}

// Drive real editor callbacks while keeping native WebView startup out of tests.
class _EditorServer extends Fake implements EditorLocalServer {
  @override
  MediaResolver? mediaResolver;

  @override
  EditorFont? Function()? fontResolver;

  @override
  Future<String?> Function(String name)? mediaNameResolver;

  @override
  Future<void> ensureStarted() async {
    throw StateError('native WebView disabled in this widget test');
  }
}

class _GeoRepository extends Fake implements GeoRepository {
  final result = Completer<CoordinatesResult>();
  int requests = 0;

  @override
  Future<CoordinatesResult> currentCoordinates() {
    requests++;
    return result.future;
  }

  void complete() {
    const CoordinatesResult located = (
      coords: .new(31.2, 121.5),
      failure: null,
    );
    result.complete(located);
  }
}

final _place = Place(
  id: 'known-place',
  name: '测试地点',
  latitude: 31.2,
  longitude: 121.5,
  lastModified: DateTime(2026),
);

void _testDiary(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      final dismissed = SmartDialog.dismiss(status: SmartStatus.allCustom);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await dismissed;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

Future<GoRouter> _pumpNewDiary(
  WidgetTester tester, {
  List<Place> places = const [],
}) async {
  final router = GoRouter(
    observers: [moodiaryRouteObserver],
    routes: [
      GoRoute(
        path: DiaryHomeRoute.path,
        builder: (_, _) => const Scaffold(body: Text('home page')),
      ),
      ...diaryRoutes(),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [orderedPlacesProvider.overrideWithValue(AsyncData(places))],
      child: TranslationProvider(
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
    ),
  );
  router.pushRoute<void>(const NewDiaryRoute(tag: '生活'));
  await tester.pumpAndSettle();
  return router;
}

void _changeTitle(WidgetTester tester, String title) {
  tester.widget<MoodiaryEditor>(find.byType(MoodiaryEditor)).onTitleChanged!(
    title,
  );
}

void main() {
  late _DiaryRepository repository;

  setUp(() {
    repository = _DiaryRepository();
    getIt.pushNewScope(
      init: (scope) {
        scope.registerSingleton<DiaryRepository>(repository);
        scope.registerSingleton<IKVStorage>(MemoryKVStorage());
        scope.registerSingleton<ISecureKVStorage>(MemorySecureKVStorage());
        scope.registerSingleton<OpenDiaryRegistry>(OpenDiaryRegistry());
        scope.registerSingleton<ThemeManager>(ThemeManager());
        scope.registerSingleton<EditorLocalServer>(_EditorServer());
      },
    );
  });
  tearDown(getIt.popScope);

  _testDiary('saving a new diary releases its draft for the next new diary', (
    tester,
  ) async {
    final router = await _pumpNewDiary(tester);
    _changeTitle(tester, '第一篇');
    await tester.tap(find.byTooltip(l10n.common.save));
    await tester.pumpAndSettle();
    final firstId = repository.diaries.keys.single;

    expect(router.state.uri.path, DiaryRoute.path);
    expect(tester.widget<DiaryPage>(find.byType(DiaryPage)).diaryId, firstId);
    expect(repository.diaries[firstId]!.title, '第一篇');
    expect(find.byTooltip(l10n.diary.edit), findsOneWidget);

    openNewDiary(tester.element(find.byType(DiaryPage)), tag: '生活');
    await tester.pumpAndSettle();
    expect(router.state.uri.path, NewDiaryRoute.path);
    expect(
      tester.widget<MoodiaryEditor>(find.byType(MoodiaryEditor)).initialTitle,
      isEmpty,
    );
    _changeTitle(tester, '第二篇');
    await tester.tap(find.byTooltip(l10n.common.save));
    await tester.pumpAndSettle();

    expect(repository.diaries, hasLength(2));
    expect(repository.diaries[firstId]!.title, '第一篇');
    expect(
      repository.diaries.values.map((diary) => diary.title),
      containsAll(['第一篇', '第二篇']),
    );
    expect(tester.takeException(), isNull);
  });

  _testDiary('empty new diary returns home and permits another new diary', (
    tester,
  ) async {
    final router = await _pumpNewDiary(tester);
    await tester.tap(find.byTooltip(l10n.common.save));
    await tester.pumpAndSettle();
    expect(repository.diaries, isEmpty);
    expect(router.state.uri.path, DiaryHomeRoute.path);
    expect(find.byType(DiaryPage), findsNothing);
    openNewDiary(tester.element(find.text('home page')), tag: '生活');
    await tester.pumpAndSettle();
    expect(router.state.uri.path, NewDiaryRoute.path);
    expect(tester.widget<DiaryPage>(find.byType(DiaryPage)).diaryId, isNull);
    expect(tester.takeException(), isNull);
  });

  _testDiary('failed save keeps the new diary in edit mode for retry', (
    tester,
  ) async {
    final router = await _pumpNewDiary(tester);
    _changeTitle(tester, '还没保存');
    repository.failWrites = true;
    await tester.tap(find.byTooltip(l10n.common.save));
    await tester.pumpAndSettle();
    expect(repository.diaries, isEmpty);
    expect(router.state.uri.path, NewDiaryRoute.path);
    expect(find.byTooltip(l10n.common.save), findsOneWidget);

    repository.failWrites = false;
    await tester.tap(find.byTooltip(l10n.common.save));
    await tester.pumpAndSettle();
    expect(repository.diaries.values.single.title, '还没保存');
    expect(router.state.uri.path, DiaryRoute.path);
    expect(tester.takeException(), isNull);
  });

  _testDiary(
    'failed persisted lookup keeps the saved draft available for retry',
    (tester) async {
      final router = await _pumpNewDiary(tester);
      _changeTitle(tester, '已经落库');
      repository.failReads = true;
      await tester.tap(find.byTooltip(l10n.common.save));
      await tester.pumpAndSettle();
      expect(repository.diaries.values.single.title, '已经落库');
      expect(router.state.uri.path, NewDiaryRoute.path);
      expect(find.byTooltip(l10n.common.save), findsOneWidget);

      repository.failReads = false;
      await tester.tap(find.byTooltip(l10n.common.save));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, DiaryRoute.path);
      expect(tester.takeException(), isNull);
    },
  );

  _testDiary('late location result does not modify the normalized diary', (
    tester,
  ) async {
    final geo = _GeoRepository();
    getIt.registerSingleton<GeoRepository>(geo);
    MoodiaryKVs.autoNearestPlace.set(true);
    final router = await _pumpNewDiary(tester, places: [_place]);
    _changeTitle(tester, '手动保存');
    await tester.tap(find.byTooltip(l10n.common.save));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, DiaryRoute.path);
    expect(geo.requests, 1);
    final writesBeforeLocation = repository.writes;

    geo.complete();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(repository.diaries.values.single.placeId, isNull);
    expect(repository.writes, writesBeforeLocation);
    expect(tester.takeException(), isNull);
  });

  _testDiary('late saved lookup does not replace another opened diary', (
    tester,
  ) async {
    final router = await _pumpNewDiary(tester);
    _changeTitle(tester, '待查询的草稿');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    final draft = repository.diaries.values.single;
    final other = draft.copyWith(id: 'other-diary', title: '另一篇');
    repository.diaries[other.id] = other;
    repository.delayedReadId = draft.id;
    repository.delayedRead = Completer<Diary?>();
    await tester.tap(find.byTooltip(l10n.common.save));
    await tester.pumpAndSettle();

    DiaryRoute(diaryId: other.id)
        .replace(tester.element(find.byType(DiaryPage)));
    await tester.pumpAndSettle();
    expect(tester.widget<DiaryPage>(find.byType(DiaryPage)).diaryId, other.id);
    repository.delayedRead!.complete(draft);
    await tester.pumpAndSettle();

    expect(router.state.uri.path, DiaryRoute.path);
    expect(tester.widget<DiaryPage>(find.byType(DiaryPage)).diaryId, other.id);
    expect(tester.takeException(), isNull);
  });

  _testDiary('location result still fills and saves the current new draft', (
    tester,
  ) async {
    final geo = _GeoRepository();
    getIt.registerSingleton<GeoRepository>(geo);
    MoodiaryKVs.autoNearestPlace.set(true);
    final router = await _pumpNewDiary(tester, places: [_place]);
    _changeTitle(tester, '继续编辑');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(geo.requests, 1);
    expect(repository.diaries.values.single.placeId, isNull);

    geo.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(router.state.uri.path, NewDiaryRoute.path);
    expect(repository.diaries.values.single.placeId, _place.id);
    expect(tester.takeException(), isNull);
  });
}
