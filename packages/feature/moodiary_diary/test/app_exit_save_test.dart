import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/presentation/detail/diary_page.dart';
import 'package:moodiary_editor/moodiary_editor.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
import 'package:mui/mui.dart';

class _DiaryRepository extends Fake implements DiaryRepository {
  final events = StreamController<DiaryEvent>.broadcast();
  Diary diary = Diary.empty(type: .tiptap).copyWith(id: 'entry');
  List<DiaryVersion> versions = [];
  Completer<void>? writeGate;
  bool failWrites = false;
  int writes = 0;
  int restores = 0;
  int activeWrites = 0;
  int maxActiveWrites = 0;

  @override
  Stream<DiaryEvent> get diaryEvents => events.stream;

  @override
  Future<Diary?> getDiaryByBusinessId(String id) async => diary;

  @override
  Future<List<DiaryVersion>> getDiaryVersions(
    String id, {
    int? limit,
    int? beforeId,
  }) async {
    final remaining = beforeId == null
        ? versions
        : versions.where((version) => version.id < beforeId);
    return (limit == null ? remaining : remaining.take(limit)).toList();
  }

  @override
  Future<void> deleteDiaryVersion(String diaryId, DiaryVersion version) async {
    if (diaryId == diary.id) versions.remove(version);
  }

  @override
  Future<void> clearDiaryVersions(String diaryId) async {
    if (diaryId == diary.id) versions.clear();
  }

  @override
  Future<bool> restoreDiaryVersion(String diaryId, DiaryVersion version) async {
    restores++;
    if (diaryId != diary.id || !versions.contains(version)) return false;
    versions.insert(0, (id: versions.first.id + 1, diary: diary));
    diary = version.diary.copyWith(lastModified: DateTime.now());
    events.add(DiaryUpdated(diary));
    return true;
  }

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

Future<void> _pumpDiary(
  WidgetTester tester, {
  bool throwOnSave = false,
  bool startInEdit = true,
}) async {
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
          home: DiaryPage(diaryId: 'entry', startInEdit: startInEdit),
        ),
      ),
    ),
  );
  for (var attempt = 0; attempt < 200; attempt++) {
    if (find.byType(MoodiaryEditor).evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(find.byType(MoodiaryEditor), findsOneWidget);
  await tester.pumpAndSettle();
  addTearDown(() async {
    await _dismissDialogs(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final guard = MediaGuard();
    var released = false;
    for (var attempt = 0; attempt < 200 && !released; attempt++) {
      await tester.pump();
      released = (await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return guard.tryExclusive(MediaType.image, 'widget-test', () async {});
      }))!;
    }
    expect(released, isTrue, reason: 'diary media lease must be released');
  });
}

void _changeTitle(WidgetTester tester, [String title = 'unsaved title']) {
  tester.widget<MoodiaryEditor>(find.byType(MoodiaryEditor)).onTitleChanged!(
    title,
  );
}

void main() {
  late _DiaryRepository repository;
  late Directory mediaRoot;

  setUpAll(() {
    mediaRoot = Directory.systemTemp.createTempSync('diary-page-media-guard');
    PlatformService.get().applicationSupportPath = mediaRoot.path;
  });
  tearDownAll(() async => mediaRoot.delete(recursive: true));

  setUp(() {
    repository = _DiaryRepository();
    getIt.pushNewScope(
      init: (scope) {
        scope.registerSingleton<DiaryRepository>(
          repository,
          dispose: (_) => repository.events.close(),
        );
        scope.registerSingleton<IKVStorage>(MemoryKVStorage());
        scope.registerSingleton<ISecureKVStorage>(MemorySecureKVStorage());
        scope.registerSingleton<OpenDiaryRegistry>(OpenDiaryRegistry());
        scope.registerSingleton<ThemeManager>(ThemeManager());
        scope.registerSingleton<EditorLocalServer>(_EditorServer());
      },
    );
  });
  tearDown(() => getIt.popScope());

  testWidgets('opens a saved version without editing the live diary', (
    tester,
  ) async {
    const oldBody =
        '{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Previous body"}]}]}';
    repository.diary = repository.diary.copyWith(title: 'Current title');
    repository.versions = [
      (
        id: 1,
        diary: repository.diary.copyWith(
          title: 'Previous title',
          content: oldBody,
          contentText: 'Previous body',
          lastModified: DateTime.utc(2026, 11, 10),
        ),
      ),
    ];

    await _pumpDiary(tester, startInEdit: false);
    await tester.tap(find.byTooltip(l10n.diary.versionHistory));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous title'));
    await tester.pumpAndSettle();

    final preview = tester.widget<MoodiaryEditor>(find.byType(MoodiaryEditor));
    expect(preview.readOnly, isTrue);
    expect(preview.initialTitle, 'Previous title');
    expect(preview.initialContent, oldBody);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<MoodiaryEditor>(find.byType(MoodiaryEditor)).initialTitle,
      'Current title',
    );
    expect(repository.writes, 0);
  });

  testWidgets(
    'restoring from the preview returns to the updated current diary',
    (tester) async {
      final current = repository.diary.copyWith(title: 'Current title');
      final earlier = (
        id: 1,
        diary: current.copyWith(
          title: 'Previous title',
          type: DiaryType.richText.value,
          content: r'[{"insert":"Previous body\n"}]',
          contentText: 'Previous body',
        ),
      );
      repository.diary = current;
      repository.versions = [earlier];

      await _pumpDiary(tester, startInEdit: false);
      final originalEditor = tester.element(find.byType(MoodiaryEditor));
      await tester.tap(find.byTooltip(l10n.diary.versionHistory));
      await tester.pumpAndSettle();
      expect(find.text(l10n.diary.versionHistoryRetention), findsOneWidget);
      await tester.tap(find.text('Previous title'));
      await tester.pumpAndSettle();

      final restore = find.byTooltip(l10n.diary.versionHistoryRestore);
      expect(
        find.widgetWithIcon(IconButton, LucideIcons.undo2),
        findsOneWidget,
      );
      final cancel = find.text(tester.element(restore).muiL10n.cancel);
      final preview = tester.widget<MoodiaryEditor>(
        find.byType(MoodiaryEditor),
      );
      expect(preview.initialContent, contains('Previous body'));
      expect(preview.initialContent, isNot(earlier.diary.content));

      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.diary.versionHistoryRestoreMessage),
        findsOneWidget,
      );
      expect(repository.restores, 0);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(repository.restores, 0);
      expect(repository.diary, current);

      await tester.tap(restore);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.diary.recycleRestore),
      );
      await tester.pumpAndSettle();
      expect(repository.restores, 1);
      expect(repository.versions.map((version) => version.diary), [
        current,
        earlier.diary,
      ]);
      expect(find.byType(DiaryPage), findsOneWidget);
      expect(find.text(l10n.diary.versionHistoryRetention), findsNothing);
      final editor = tester.widget<MoodiaryEditor>(find.byType(MoodiaryEditor));
      expect(editor.readOnly, isTrue);
      expect(editor.initialTitle, 'Previous title');
      expect(editor.initialContent, preview.initialContent);
      expect(
        tester.element(find.byType(MoodiaryEditor)),
        isNot(same(originalEditor)),
      );
      expect(repository.writes, 0);
      await _dismissDialogs(tester);
    },
  );

  testWidgets('restores from the list and returns to the list after deleting', (
    tester,
  ) async {
    final current = repository.diary.copyWith(title: 'Current title');
    final older = (id: 1, diary: current.copyWith(title: 'Version 1'));
    final newer = (id: 2, diary: current.copyWith(title: 'Version 2'));
    repository.diary = current;
    repository.versions = [newer, older];

    await _pumpDiary(tester, startInEdit: false);
    await tester.tap(find.byTooltip(l10n.diary.versionHistory));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Version 1'),
        matching: find.byTooltip(l10n.diary.versionHistoryRestore),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.diary.versionHistoryRestoreMessage), findsOneWidget);
    expect(repository.restores, 0);
    await tester.tap(
      find.widgetWithText(FilledButton, l10n.diary.recycleRestore),
    );
    await tester.pumpAndSettle();
    expect(repository.restores, 1);
    expect(repository.diary.title, 'Version 1');
    expect(find.byType(DiaryPage), findsOneWidget);
    expect(find.text(l10n.diary.versionHistoryRetention), findsNothing);
    expect(
      tester.widget<MoodiaryEditor>(find.byType(MoodiaryEditor)).initialTitle,
      'Version 1',
    );
    await _dismissDialogs(tester);

    await tester.tap(find.byTooltip(l10n.diary.versionHistory));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Current title'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Version 2'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.diary.versionHistoryRestore), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, LucideIcons.undo2), findsOneWidget);
    expect(find.widgetWithIcon(IconButton, LucideIcons.trash2), findsOneWidget);
    final delete = find.byTooltip(l10n.diary.versionHistoryDelete);
    final cancel = find.text(tester.element(delete).muiL10n.cancel);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text(l10n.diary.versionHistoryDelete), findsOneWidget);
    expect(repository.versions, contains(newer));
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(delete, findsOneWidget);
    expect(repository.versions, contains(newer));

    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.common.delete));
    await tester.pumpAndSettle();
    expect(repository.versions, isNot(contains(newer)));
    expect(find.widgetWithText(ListTile, 'Version 2'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Version 1'), findsOneWidget);
    expect(find.text(l10n.diary.versionHistoryRetention), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repository.diary.title, 'Version 1');
    expect(repository.writes, 0);
  });

  testWidgets(
    'confirms deleting one version and clearing the remaining history',
    (tester) async {
      final current = repository.diary.copyWith(title: 'Current title');
      repository.diary = current;
      final older = (id: 1, diary: current.copyWith(title: 'Version 1'));
      final newer = (id: 2, diary: current.copyWith(title: 'Version 2'));
      repository.versions = [newer, older];

      await _pumpDiary(tester, startInEdit: false);
      await tester.tap(find.byTooltip(l10n.diary.versionHistory));
      await tester.pumpAndSettle();

      final historyBar = find.widgetWithText(AppBar, l10n.diary.versionHistory);
      final cancel = find.text(tester.element(historyBar).muiL10n.cancel);
      final removeNewer = find.descendant(
        of: find.widgetWithText(ListTile, 'Version 2'),
        matching: find.byTooltip(l10n.diary.versionHistoryDelete),
      );
      await tester.tap(removeNewer);
      await tester.pumpAndSettle();
      expect(find.text(l10n.diary.versionHistoryDelete), findsOneWidget);
      expect(repository.versions, [newer, older]);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(repository.versions, [newer, older]);

      await tester.tap(removeNewer);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.common.delete));
      await tester.pumpAndSettle();
      expect(repository.versions, [older]);
      expect(find.text('Version 2'), findsNothing);
      expect(find.text('Version 1'), findsOneWidget);

      final clearHistory = find.widgetWithText(
        TextButton,
        l10n.diary.versionHistoryClear,
      );
      await tester.tap(clearHistory);
      await tester.pumpAndSettle();
      expect(find.text(l10n.diary.versionHistoryClearMessage), findsOneWidget);
      expect(repository.versions, [older]);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(repository.versions, [older]);

      await tester.tap(clearHistory);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.diary.versionHistoryClear),
      );
      await tester.pumpAndSettle();
      expect(repository.versions, isEmpty);
      expect(find.text(l10n.diary.versionHistoryEmpty), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(MoodiaryEditor), findsOneWidget);
      expect(repository.diary, current);
      expect(repository.writes, 0);
    },
  );

  testWidgets('clean diary permits exit without another write', (tester) async {
    await _pumpDiary(tester);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(repository.writes, 0);
  });

  testWidgets('keeps media protected while dispose waits for the final save', (
    tester,
  ) async {
    await _pumpDiary(tester);
    _changeTitle(tester);
    repository.writeGate = Completer<void>();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final guard = MediaGuard();
    final duringSave = await tester.runAsync(
      () => guard.tryExclusive(MediaType.image, 'image-test.jpg', () async {}),
    );
    expect(duringSave, isFalse);

    repository.writeGate!.complete();
    await tester.pump();
    var released = false;
    for (var attempt = 0; attempt < 200 && !released; attempt++) {
      await tester.pump();
      released = (await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return guard.tryExclusive(
          MediaType.image,
          'image-test.jpg',
          () async {},
        );
      }))!;
    }
    expect(released, isTrue);
  });

  testWidgets(
    'selected tags use the latest draft and autosave without a dialog',
    (tester) async {
      repository.diary = repository.diary.copyWith(title: '已有日记', tags: ['已有']);
      await _pumpDiary(tester);
      final editor = tester.widget<MoodiaryEditor>(find.byType(MoodiaryEditor));
      expect(editor.onAddTag, isNull);

      // Reuse the same callback before a rebuild, as consecutive bridge messages do.
      editor.onSelectTag!(' #工作 / 项目 ');
      editor.onSelectTag!('生活 随记');
      editor.onSelectTag!('C#');
      editor.onSelectTag!('工作/项目');
      await tester.pump();
      expect(find.text(l10n.diary.addTag), findsNothing);
      expect(repository.writes, 0);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(repository.writes, 1);
      expect(repository.diary.tags, ['已有', '工作/项目', '生活 随记', 'C#']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid and already selected tags leave the diary clean', (
    tester,
  ) async {
    repository.diary = repository.diary.copyWith(
      title: '已有日记',
      tags: ['工作/项目'],
    );
    await _pumpDiary(tester);
    final selectTag = tester
        .widget<MoodiaryEditor>(find.byType(MoodiaryEditor))
        .onSelectTag!;
    for (final tag in ['', ' ', '#', '工作//项目', '工作\n项目', ' #工作 / 项目 ']) {
      selectTag(tag);
    }
    await tester.pump(const Duration(seconds: 3));
    expect(repository.writes, 0);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(repository.writes, 0);
    expect(repository.diary.tags, ['工作/项目']);
    expect(find.text(l10n.diary.addTag), findsNothing);
    expect(tester.takeException(), isNull);
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
