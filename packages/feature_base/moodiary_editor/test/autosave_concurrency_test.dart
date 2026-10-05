import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_editor/moodiary_editor.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

class _Write {
  _Write(this.kind, this.diary);

  final String kind;
  final Diary? diary;
  final Completer<void> completed = Completer<void>();
}

class _DiaryRepository extends Fake implements DiaryRepository {
  Diary? stored;
  final subscribed = Completer<void>();
  late final _events = StreamController<DiaryEvent>.broadcast(
    onListen: () {
      if (!subscribed.isCompleted) subscribed.complete();
    },
  );
  final writes = <_Write>[];
  Completer<void> _writeStarted = Completer<void>();
  int activeWrites = 0;
  int maxActiveWrites = 0;

  @override
  Stream<DiaryEvent> get diaryEvents => _events.stream;

  @override
  Future<Diary?> getDiaryByBusinessId(String id) async => stored;

  Future<_Write> writeAt(int index) async {
    while (writes.length <= index) {
      await _writeStarted.future.timeout(const Duration(seconds: 5));
    }
    return writes[index];
  }

  Future<void> _persist(String kind, Diary? diary) async {
    final write = _Write(kind, diary);
    writes.add(write);
    activeWrites++;
    if (activeWrites > maxActiveWrites) maxActiveWrites = activeWrites;
    final started = _writeStarted;
    _writeStarted = Completer<void>();
    started.complete();
    try {
      await write.completed.future;
      stored = diary;
      if (diary != null) {
        _events.add(
          kind == 'insert' ? DiaryCreated(diary) : DiaryUpdated(diary),
        );
      }
    } finally {
      activeWrites--;
    }
  }

  @override
  Future<void> insertADiary(
    Diary diary, {
    bool fromSync = false,
    IndexMode index = .inline,
  }) => _persist('insert', diary);

  @override
  Future<void> updateADiary({
    required Diary newDiary,
    IndexMode index = .inline,
    bool fromSync = false,
  }) => _persist('update', newDiary);

  @override
  Future<bool> hardDeleteDiary(String id) async {
    await _persist('delete', null);
    return true;
  }

  Future<void> dispose() => _events.close();
}

String _body(String text) => jsonEncode({
  'type': 'doc',
  'content': [
    {
      'type': 'paragraph',
      'content': [
        {'type': 'text', 'text': text},
      ],
    },
  ],
});

void main() {
  late _DiaryRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _DiaryRepository();
    getIt.pushNewScope(
      init: (scope) {
        scope.registerSingleton<DiaryRepository>(repository);
        scope.registerSingleton<IKVStorage>(MemoryKVStorage());
      },
    );
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    await repository.dispose();
    await getIt.popScope();
  });

  Future<EditControllerProvider> openDiary({
    bool isNew = false,
    DiaryMood mood = .neutral,
  }) async {
    if (!isNew) {
      repository.stored = Diary.empty(type: .tiptap)
          .copyWith(id: 'entry', mood: mood);
    }
    final provider = editControllerProvider(
      isNew ? null : 'entry',
      defaultType: .tiptap,
    );
    container.listen(provider, (_, _) {});
    await container.read(provider.future);
    if (!isNew) await repository.subscribed.future;
    return provider;
  }

  Future<void> settleRepositoryEvent(
    EditControllerProvider provider,
    String title,
  ) async {
    final received = Completer<void>();
    final subscription = container.listen(
      getDiaryProvider(id: 'entry', defaultType: .tiptap),
      (_, next) {
        if (next.value?.title == title && !received.isCompleted) {
          received.complete();
        }
      },
      fireImmediately: true,
    );
    try {
      await received.future.timeout(const Duration(seconds: 5));
      await container.pump();
      await container.read(provider.future);
    } finally {
      subscription.close();
    }
  }

  test(
    'new mood selections accept emotions and reject activity states',
    () async {
      final provider = await openDiary(isNew: true);
      final controller = container.read(provider.notifier);
      for (final mood in DiaryMood.selectableValues) {
        controller.changeMood(mood);
        expect(container.read(provider).value!.mood, mood);
      }
      controller.changeMood(.grateful);
      for (final mood in DiaryMood.values.where((m) => !m.isSelectable)) {
        expect(() => controller.changeMood(mood), throwsArgumentError);
        expect(container.read(provider).value!.mood, DiaryMood.grateful);
      }
    },
  );

  test(
    'autosave preserves a legacy activity until an emotion is selected',
    () async {
      final provider = await openDiary(mood: .work);
      final controller = container.read(provider.notifier);
      expect(container.read(provider).value!.mood, DiaryMood.work);

      controller.changeTitle('updated title');
      final firstSave = controller.autoSave();
      final first = await repository.writeAt(0);
      expect(first.diary!.mood, DiaryMood.work);
      first.completed.complete();
      expect(await firstSave, DraftSaveResult.saved);
      await settleRepositoryEvent(provider, 'updated title');
      expect(repository.stored!.mood, DiaryMood.work);

      controller.changeMood(.grateful);
      final secondSave = controller.autoSave();
      final second = await repository.writeAt(1);
      expect(second.diary!.mood, DiaryMood.grateful);
      second.completed.complete();
      expect(await secondSave, DraftSaveResult.saved);
      expect(repository.stored!.mood, DiaryMood.grateful);
    },
  );

  test('repository updates are still applied while autosave is idle', () async {
    final provider = await openDiary();
    final updated = repository.stored!.copyWith(
      title: 'external title',
      content: _body('external body'),
      contentText: 'external body',
    );
    repository.stored = updated;
    repository._events.add(DiaryUpdated(updated, fromSync: true));
    await settleRepositoryEvent(provider, 'external title');

    expect(container.read(provider).value!.title, 'external title');
    expect(container.read(provider).value!.content, _body('external body'));
    expect(repository.writes, isEmpty);
  });

  test(
    'input during writes survives repository events and saves until stable',
    () async {
      final provider = await openDiary();
      final controller = container.read(provider.notifier);
      controller.changeTitle('first title');
      controller.changeContent(_body('first body'), contentText: 'first body');
      final saving = controller.autoSave();
      final first = await repository.writeAt(0);

      controller.changeTitle('second title');
      controller.changeContent(
        _body('second body'),
        contentText: 'second body',
      );
      first.completed.complete();
      final second = await repository.writeAt(1);
      await settleRepositoryEvent(provider, 'first title');
      expect(container.read(provider).value!.title, 'second title');
      expect(container.read(provider).value!.contentText, 'second body');

      controller.changeTitle('latest title');
      controller.changeContent(
        _body('latest body'),
        contentText: 'latest body',
      );
      second.completed.complete();
      final latest = await repository.writeAt(2);
      expect(latest.diary!.title, 'latest title');
      latest.completed.complete();
      expect(await saving, DraftSaveResult.saved);
      await settleRepositoryEvent(provider, 'latest title');
      expect(repository.stored!.title, 'latest title');
      expect(repository.stored!.contentText, 'latest body');
      expect(container.read(provider).value!.title, 'latest title');
      expect(container.read(provider).value!.content, _body('latest body'));
      expect(repository.maxActiveWrites, 1);
    },
  );

  test('concurrent autosave calls keep writes serial', () async {
    final provider = await openDiary();
    final controller = container.read(provider.notifier);
    controller.changeTitle('first title');
    final firstSave = controller.autoSave();
    final first = await repository.writeAt(0);
    controller.changeTitle('latest title');
    final secondSave = controller.autoSave();
    first.completed.complete();
    final second = await repository.writeAt(1);
    second.completed.complete();
    expect(await firstSave, DraftSaveResult.saved);
    final third = await repository.writeAt(2);
    third.completed.complete();
    expect(await secondSave, DraftSaveResult.saved);
    await settleRepositoryEvent(provider, 'latest title');
    expect(repository.stored!.title, 'latest title');
    expect(container.read(provider).value!.title, 'latest title');
    expect(repository.maxActiveWrites, 1);
  });

  test('failed follow-up write retains the newest draft for retry', () async {
    final provider = await openDiary();
    final controller = container.read(provider.notifier);
    controller.changeTitle('first title');
    final saving = controller.autoSave();
    final first = await repository.writeAt(0);
    controller.changeTitle('latest title');
    first.completed.complete();
    final second = await repository.writeAt(1);
    await settleRepositoryEvent(provider, 'first title');
    second.completed.completeError(StateError('storage unavailable'));
    expect(await saving, DraftSaveResult.failed);
    expect(container.read(provider).value!.title, 'latest title');
    expect(repository.stored!.title, 'first title');

    final retry = controller.autoSave();
    final third = await repository.writeAt(2);
    expect(third.kind, 'update');
    third.completed.complete();
    expect(await retry, DraftSaveResult.saved);
    await settleRepositoryEvent(provider, 'latest title');
    expect(repository.stored!.title, 'latest title');
    expect(container.read(provider).value!.title, 'latest title');
  });

  test(
    'new input during initial insert uses an update for the next snapshot',
    () async {
      final provider = await openDiary(isNew: true);
      final controller = container.read(provider.notifier);
      controller.changeTitle('first title');
      final saving = controller.autoSave();
      final first = await repository.writeAt(0);
      expect(first.kind, 'insert');
      controller.changeTitle('latest title');
      first.completed.complete();
      final second = await repository.writeAt(1);
      expect(second.kind, 'update');
      second.completed.complete();
      expect(await saving, DraftSaveResult.saved);
      expect(repository.stored!.title, 'latest title');
      expect(container.read(provider).value!.title, 'latest title');
      expect(repository.maxActiveWrites, 1);
    },
  );

  test(
    'input during blank draft deletion is reinserted and kept in state',
    () async {
      final provider = await openDiary(isNew: true);
      final controller = container.read(provider.notifier);
      controller.changeTitle('first title');
      final initialSave = controller.autoSave();
      (await repository.writeAt(0)).completed.complete();
      expect(await initialSave, DraftSaveResult.saved);

      controller.changeTitle('');
      final saving = controller.autoSave();
      final deletion = await repository.writeAt(1);
      expect(deletion.kind, 'delete');
      controller.changeTitle('restored title');
      deletion.completed.complete();
      final insertion = await repository.writeAt(2);
      expect(insertion.kind, 'insert');
      expect(insertion.diary!.title, 'restored title');
      insertion.completed.complete();
      expect(await saving, DraftSaveResult.saved);
      expect(repository.stored!.title, 'restored title');
      expect(container.read(provider).value!.title, 'restored title');
      expect(repository.maxActiveWrites, 1);
    },
  );
}
