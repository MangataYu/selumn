import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/application/diary_citation.dart';
import 'package:moodiary_assistant/src/data/chat_repository.dart';
import 'package:moodiary_assistant/src/presentation/assistant_page.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';

void main() {
  late MoodiaryDatabase db;
  late ChatRepository repo;

  setUp(() async {
    db = MoodiaryDatabase.forTesting(NativeDatabase.memory());
    repo = ChatRepository(db);
    getIt.registerSingleton<ChatRepository>(repo);
    // Open the native database before entering the widget test's fake clock.
    await db.customSelect('SELECT 1').getSingle();
  });

  tearDown(() async {
    await getIt.reset();
    await db.close();
  });

  Widget host([Widget child = const AssistantSessionListPage()]) {
    final data = buildMuiTheme(brightness: Brightness.light);
    return TranslationProvider(
      child: MuiTheme(
        data: data,
        child: MaterialApp(
          theme: data,
          locale: const Locale('zh'),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            GlobalMuiLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: .topLeft,
              child: SizedBox(width: 360, child: child),
            ),
          ),
        ),
      ),
    );
  }

  Future<ChatSession> seed({
    required String text,
    String title = '',
    String? imageName,
  }) async {
    final session = ChatSession.create(
      providerId: 'provider',
      model: 'model',
    ).copyWith(title: title);
    await repo.upsertSession(session);
    await repo.addMessage(
      ChatMessage.create(
        sessionId: session.id,
        role: 'user',
        content: text,
      ).copyWith(imageName: imageName),
    );
    return session;
  }

  testWidgets('未命名会话显示首条用户消息的本地标题', (tester) async {
    final session = await seed(text: '周末去哪散步？想找安静的路线。');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('周末去哪散步'), findsOneWidget);
    expect(find.text('周末去哪散步？想找安静的路线。'), findsNothing);
    expect((await repo.getSession(session.id))!.title, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已保存的正式标题优先于首条消息', (tester) async {
    await seed(text: '原始问题', title: 'AI 已概括的标题');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('AI 已概括的标题'), findsOneWidget);
    expect(find.text('原始问题'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('纯图片会话显示本地化图片标签', (tester) async {
    await seed(text: '', imageName: 'private-image.png');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final l10n = tester.element(find.byType(AssistantSessionListPage)).l10n;
    expect(find.text(l10n.assistant.imageMessageLabel), findsOneWidget);
    expect(find.textContaining('private-image.png'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('引用日记的标题不泄露原始引用 ID', (tester) async {
    const diaryId = '01912345-1234-7123-8123-123456789abc';
    const emptyCitationId = '01912345-5678-7123-8123-123456789abc';
    await seed(text: citeDiary('帮我回顾这一天。还有哪些值得记录？', diaryId));
    await seed(text: citeDiary('', emptyCitationId));

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final l10n = tester.element(find.byType(AssistantSessionListPage)).l10n;
    expect(find.text('帮我回顾这一天'), findsOneWidget);
    expect(find.text(l10n.assistant.citationRead), findsOneWidget);
    expect(find.textContaining(diaryId), findsNothing);
    expect(find.textContaining(emptyCitationId), findsNothing);
    expect(find.textContaining('[diary:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('后台标题保存事件将列表中的本地标题刷新为 AI 标题', (tester) async {
    final session = await seed(text: '今天如何安排时间？');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('今天如何安排时间'), findsOneWidget);

    expect(await repo.setSessionTitleIfEmpty(session.id, '每日时间安排'), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('每日时间安排'), findsOneWidget);
    expect(find.text('今天如何安排时间'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('列表关闭后保存的标题在重新打开时仍然显示', (tester) async {
    final session = await seed(text: '帮我规划周末。');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('帮我规划周末'), findsOneWidget);

    await tester.pumpWidget(host(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(find.byType(AssistantSessionListPage), findsNothing);
    expect(await repo.setSessionTitleIfEmpty(session.id, '周末出行计划'), isTrue);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('周末出行计划'), findsOneWidget);
    expect(find.text('帮我规划周末'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
