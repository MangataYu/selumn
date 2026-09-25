import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/chat_repository.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_models/moodiary_models.dart';

void main() {
  late MoodiaryDatabase db;
  late ChatRepository repo;

  setUp(() {
    db = MoodiaryDatabase.forTesting(NativeDatabase.memory());
    repo = ChatRepository(db);
  });

  tearDown(() => db.close());

  test('countSessionsByProvider 只数钉住该供应商的会话', () async {
    for (final p in ['a', 'a', 'b']) {
      await repo.upsertSession(ChatSession.create(providerId: p, model: 'm'));
    }
    expect(await repo.countSessionsByProvider('a'), 2);
    expect(await repo.countSessionsByProvider('b'), 1);
    expect(await repo.countSessionsByProvider('c'), 0);
  });

  test('未命名会话只查询最早的用户消息，同时间按 ID 排序', () async {
    expect(await repo.getUntitledSessionFirstMessages(), isEmpty);
    final first = ChatSession.create(providerId: 'a', model: 'm');
    final second = ChatSession.create(providerId: 'b', model: 'n');
    final named = ChatSession.create(
      providerId: 'a',
      model: 'm',
    ).copyWith(title: '已有标题');
    final empty = ChatSession.create(providerId: 'a', model: 'm');
    final assistantOnly = ChatSession.create(providerId: 'a', model: 'm');
    for (final session in [first, second, named, empty, assistantOnly]) {
      await repo.upsertSession(session);
    }
    // Old databases may contain whitespace that SQLite's default trim misses.
    await (db.update(db.chatSessions)..where((s) => s.id.equals(second.id)))
        .write(const ChatSessionsCompanion(title: Value('\t \n\u3000')));
    final start = DateTime.utc(2026, 9, 18);
    final expectedFirst = ChatMessage(
      id: 'first-a',
      sessionId: first.id,
      role: 'user',
      content: '第一条用户消息',
      imageName: 'photo.png',
      createdAt: start.add(const Duration(minutes: 2)),
    );
    final expectedSecond = ChatMessage(
      id: 'second',
      sessionId: second.id,
      role: 'user',
      content: '另一个会话',
      createdAt: start.add(const Duration(minutes: 1)),
    );
    for (final message in [
      // Deliberately insert out of order, including equal timestamps.
      expectedFirst.copyWith(
        id: 'first-later',
        content: '后续消息',
        createdAt: start.add(const Duration(minutes: 3)),
      ),
      expectedFirst.copyWith(id: 'first-z', content: '同时间但 ID 更大'),
      expectedFirst,
      expectedFirst.copyWith(
        id: 'assistant',
        role: 'assistant',
        createdAt: start,
      ),
      expectedFirst.copyWith(id: 'system', role: 'system', createdAt: start),
      expectedSecond,
      expectedFirst.copyWith(id: 'named', sessionId: named.id),
      expectedFirst.copyWith(
        id: 'assistant-only',
        sessionId: assistantOnly.id,
        role: 'assistant',
      ),
    ]) {
      await repo.addMessage(message);
    }

    final firstMessages = await repo.getUntitledSessionFirstMessages();
    expect(firstMessages.keys, [second.id, first.id]);
    expect(firstMessages, {first.id: expectedFirst, second.id: expectedSecond});
  });

  test('生成标题仅更新标题，不覆盖会话设置、压缩状态或排序时间', () async {
    final session = ChatSession.create(providerId: 'a', model: 'm').copyWith(
      reasoningEffort: 'high',
      compactedSummary: 'summary',
      compactedUpToMessageId: 'message-1',
      compactedAt: DateTime.utc(2026, 9, 18),
      compactedInputTokensAtTrigger: 1024,
    );
    await repo.upsertSession(session);
    final stored = (await repo.getSession(session.id))!;

    expect(await repo.setSessionTitleIfEmpty(session.id, '  自动标题  '), isTrue);
    expect(await repo.getSession(session.id), stored.copyWith(title: '自动标题'));
    expect(await repo.setSessionTitleIfEmpty(session.id, '后到的标题'), isFalse);
    expect(await repo.getSession(session.id), stored.copyWith(title: '自动标题'));
  });

  test('生成标题可填充旧的空白标题，且只有成功写入才发会话事件', () async {
    final session = ChatSession.create(providerId: 'a', model: 'm');
    await repo.upsertSession(session);
    await (db.update(db.chatSessions)..where((s) => s.id.equals(session.id)))
        .write(const ChatSessionsCompanion(title: Value('\t \n\u3000')));
    var events = 0;
    final subscription = repo.sessionEvents.listen((_) => events++);
    addTearDown(subscription.cancel);

    expect(await repo.setSessionTitleIfEmpty(session.id, '\t \n'), isFalse);
    expect(await repo.setSessionTitleIfEmpty('', '标题'), isFalse);
    expect(await repo.setSessionTitleIfEmpty('missing', '标题'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(events, 0);

    expect(await repo.setSessionTitleIfEmpty(session.id, '自动标题'), isTrue);
    expect(await repo.setSessionTitleIfEmpty(session.id, '重复标题'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(events, 1);
    expect((await repo.getSession(session.id))!.title, '自动标题');
  });

  test('后台生成标题不会复活已删除的会话', () async {
    final session = ChatSession.create(providerId: 'a', model: 'm');
    await repo.upsertSession(session);
    await repo.deleteSession(session.id);
    var events = 0;
    final subscription = repo.sessionEvents.listen((_) => events++);
    addTearDown(subscription.cancel);

    expect(await repo.setSessionTitleIfEmpty(session.id, '迟到的标题'), isFalse);
    expect(await repo.getSession(session.id), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(events, 0);
  });

  test('旧空标题快照更新会话时保留后台标题，新会话使用空标题默认值', () async {
    final session = ChatSession.create(providerId: 'a', model: 'm');
    await repo.upsertSession(session);
    expect((await repo.getSession(session.id))!.title, isEmpty);
    await repo.setSessionTitleIfEmpty(session.id, '后台标题');

    // Both truly empty and whitespace-only old snapshots omit the title column.
    for (final title in ['', '\t \n']) {
      await repo.upsertSession(
        session.copyWith(title: title, model: 'updated-model'),
      );
      final stored = (await repo.getSession(session.id))!;
      expect(stored.title, '后台标题');
      expect(stored.model, 'updated-model');
    }
    await repo.upsertSession(session.copyWith(title: '明确的新标题'));
    expect((await repo.getSession(session.id))!.title, '明确的新标题');
  });

  test('落库的旧工具名读出时映射成新名', () async {
    final session = ChatSession.create(providerId: 'a', model: 'm');
    await repo.upsertSession(session);
    await repo.addMessage(
      ChatMessage(
        id: 'm1',
        sessionId: session.id,
        role: 'assistant',
        content: '',
        createdAt: DateTime.utc(2026, 9, 18),
        toolCalls: const [
          AssistantToolCall(callId: 'c1', name: 'queryDiaries', done: true),
          AssistantToolCall(callId: 'c2', name: 'listMemories', done: true),
        ],
      ),
    );
    final messages = await repo.getMessages(session.id);
    expect(messages.single.toolCalls.map((c) => c.name), [
      'searchDiaries',
      'recallMemory',
    ]);
  });
}
