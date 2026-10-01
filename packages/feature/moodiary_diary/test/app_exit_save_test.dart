import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/presentation/detail/diary_page.dart';
import 'package:moodiary_editor/moodiary_editor.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
import 'package:mui/mui.dart';

class _DiaryRepository extends Fake implements DiaryRepository {
  Diary diary = Diary.empty(type: .tiptap).copyWith(id: 'entry');
  Completer<void>? writeGate;
  bool failWrites = false;
  int writes = 0;
  int activeWrites = 0;
  int maxActiveWrites = 0;

  @override
  Stream<DiaryEvent> get diaryEvents => const Stream.empty();

  @override
  Future<Diary?> getDiaryByBusinessId(String id) async => diary;

  @override
  Future<List<Diary>> getForwardLinks(String id) async => [];

  @override
  Future<List<Diary>> getBacklinks(String id) async => [];

  @override
  Future<void> updateADiary({
    required Diary newDiary,
    IndexMode index = .inline,
    bool fromSync = false,
  }) async {
    writes++;
    activeWrites++;
    if (activeWrites > maxActiveWrites) maxActiveWrites = activeWrites;
    try {
      await writeGate?.future;
      if (failWrites) throw StateError('storage unavailable');
      diary = newDiary;
    } finally {
      activeWrites--;
    }
  }
}

// The save test exercises the page's editor callbacks without a native WebView.
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

class _ThrowOnceEditController extends EditController {
  bool _thrown = false;

  @override
  Future<DraftSaveResult> autoSave() {
    if (!_thrown) {
      _thrown = true;
      throw StateError('save callback failed');
    }
    return super.autoSave();
  }
}

Future<void> _dismissDialogs(WidgetTester tester) async {
  await tester.pump();
  final dialogs = SmartDialog.dismiss(status: SmartStatus.allDialog);
  final toasts = SmartDialog.dismiss(status: SmartStatus.allToast);
  // Dismissal also awaits a timer when its animation has not advanced yet.
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
  await dialogs;
  await toasts;
}

Future<void> _pumpDiary(WidgetTester tester, {bool throwOnSave = false}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderedPlacesProvider.overrideWithValue(const AsyncData(<Place>[])),
        if (throwOnSave)
          editControllerProvider(
            'entry',
            defaultType: .tiptap,
          ).overrideWith(_ThrowOnceEditController.new),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          theme: buildMuiTheme(brightness: Brightness.light),
          builder: FlutterSmartDialog.init(),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            GlobalMuiLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: const DiaryPage(diaryId: 'entry', startInEdit: true),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await _dismissDialogs(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

void _changeTitle(WidgetTester tester, [String title = 'unsaved title']) {
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
  tearDown(() => getIt.popScope());

  testWidgets('clean diary permits exit without another write', (tester) async {
    await _pumpDiary(tester);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(repository.writes, 0);
  });

  testWidgets('exit waits for the dirty draft before the debounce fires', (
    tester,
  ) async {
    await _pumpDiary(tester);
    _changeTitle(tester);
    repository.writeGate = Completer<void>();
    AppExitResponse? response;
    final exit = tester.binding.handleRequestAppExit().then((value) {
      response = value;
    });
    await tester.pump();
    expect(repository.writes, 1);
    expect(response, isNull);

    repository.writeGate!.complete();
    await tester.pump();
    await exit;
    expect(response, AppExitResponse.exit);
    expect(repository.diary.title, 'unsaved title');
    await tester.pump(const Duration(seconds: 3));
    expect(repository.writes, 1, reason: 'exit cancels the debounce timer');
  });

  testWidgets('exit waits for an autosave already in progress', (tester) async {
    await _pumpDiary(tester);
    _changeTitle(tester);
    repository.writeGate = Completer<void>();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.activeWrites, 1);

    AppExitResponse? response;
    final exit = tester.binding.handleRequestAppExit().then((value) {
      response = value;
    });
    await tester.pump();
    expect(response, isNull);
    expect(repository.activeWrites, 1);

    repository.writeGate!.complete();
    await tester.pump();
    await exit;
    expect(response, AppExitResponse.exit);
    expect(repository.diary.title, 'unsaved title');
    expect(repository.maxActiveWrites, 1);
  });

  testWidgets('failed save cancels exit and permits a later retry', (
    tester,
  ) async {
    await _pumpDiary(tester);
    _changeTitle(tester);
    repository.failWrites = true;
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);

    repository.failWrites = false;
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(repository.diary.title, 'unsaved title');
    await _dismissDialogs(tester);
  });

  testWidgets('exit also saves input received during the pending write', (
    tester,
  ) async {
    await _pumpDiary(tester);
    _changeTitle(tester);
    repository.writeGate = Completer<void>();
    AppExitResponse? response;
    final exit = tester.binding.handleRequestAppExit().then((value) {
      response = value;
    });
    await tester.pump();
    expect(repository.activeWrites, 1);
    _changeTitle(tester, 'latest title');

    repository.writeGate!.complete();
    await tester.pump();
    await exit;
    expect(response, AppExitResponse.exit);
    expect(repository.diary.title, 'latest title');
    final context = tester.element(find.byType(DiaryPage));
    expect(
      ProviderScope.containerOf(context)
          .read(editControllerProvider('entry', defaultType: .tiptap))
          .value!
          .title,
      'latest title',
    );
    expect(repository.maxActiveWrites, 1);
  });

  testWidgets('unexpected save exception also cancels exit', (tester) async {
    await _pumpDiary(tester, throwOnSave: true);
    _changeTitle(tester);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(repository.diary.title, 'unsaved title');
    await _dismissDialogs(tester);
  });
}
