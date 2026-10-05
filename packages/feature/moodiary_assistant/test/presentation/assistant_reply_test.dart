import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/presentation/assistant_reply.dart';
import 'package:moodiary_assistant/src/presentation/markdown_code_block.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';

Widget _host(Widget child, ThemeData data) => TranslationProvider(
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
      home: Scaffold(body: child),
    ),
  ),
);

List<(String, TextStyle)> _spansOf(WidgetTester tester) {
  final spans = <(String, TextStyle)>[];
  void walk(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return;
    final style = inherited.merge(span.style);
    if (span.text case final text?) spans.add((text, style));
    for (final child in span.children ?? <InlineSpan>[]) {
      walk(child, style);
    }
  }

  for (final text in tester.widgetList<RichText>(
    find.descendant(
      of: find.byType(AssistantReply),
      matching: find.byWidgetPredicate((widget) => widget is RichText),
    ),
  )) {
    walk(text.text, const TextStyle());
  }
  return spans;
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    _spansOf(tester).singleWhere((span) => span.$1.contains(text)).$2;

Color? _bubbleColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(AssistantReply),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('同一条回复随浅深模式和主题色切换更新，正文仍使用正文色', (tester) async {
    const reply = AssistantReply(
      text:
          '# 一级标题\n\n## 二级标题\n\n### 回复标题\n\n'
          '#### 四级标题\n\n##### 五级标题\n\n###### 六级标题\n\n'
          '普通正文 **强调文字**\n\n'
          '| 主题表头 |\n| --- |\n| 表格正文 |',
    );
    final themes = [
      buildMuiTheme(
        brightness: Brightness.light,
        accent: const MuiAccent.seeded(Color(0xFF6B7A3A)),
      ),
      buildMuiTheme(
        brightness: Brightness.dark,
        accent: const MuiAccent.seeded(Color(0xFF6B7A3A)),
      ),
      buildMuiTheme(
        brightness: Brightness.dark,
        accent: const MuiAccent.seeded(Color(0xFF2E59A7)),
        font: const MuiFontConfig(family: 'DiaryCustomFont'),
      ),
    ];
    final backgrounds = <Color?>[];
    final emphasisColors = <Color?>[];
    Element? replyElement;

    for (final theme in themes) {
      await tester.pumpWidget(_host(reply, theme));
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(AssistantReply));
      replyElement ??= element;
      expect(element, same(replyElement));
      expect(_bubbleColor(tester), theme.colorScheme.surfaceContainer);
      expect(_styleOf(tester, '普通正文').color, theme.colorScheme.onSurface);
      double? previousHeadingSize;
      for (final heading in ['一级标题', '二级标题', '回复标题', '四级标题', '五级标题', '六级标题']) {
        final style = _styleOf(tester, heading);
        expect(style.color, theme.colorScheme.onSurface);
        expect(style.fontFamily, theme.textTheme.bodyLarge!.fontFamily);
        final size = style.fontSize!;
        if (previousHeadingSize != null) {
          expect(previousHeadingSize, greaterThan(size));
        }
        previousHeadingSize = size;
      }
      expect(_styleOf(tester, '强调文字').color, theme.colorScheme.primary);
      expect(_styleOf(tester, '强调文字').fontWeight, FontWeight.bold);
      final table = tester.widget<Table>(find.byType(Table));
      expect(
        (table.children.first.decoration! as BoxDecoration).color,
        theme.colorScheme.surfaceContainerHighest,
      );
      expect(_styleOf(tester, '主题表头').color, theme.colorScheme.onSurface);
      backgrounds.add(_bubbleColor(tester));
      emphasisColors.add(_styleOf(tester, '强调文字').color);
    }

    expect(backgrounds[0], isNot(backgrounds[1]));
    expect(emphasisColors.toSet(), hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('列表和嵌套斜体保留 Markdown 语义，强调色不扩散到相邻正文', (tester) async {
    final theme = buildMuiTheme(
      brightness: Brightness.light,
      accent: const MuiAccent.seeded(Color(0xFF6B7A3A)),
    );
    await tester.pumpWidget(
      _host(
        const AssistantReply(
          text:
              '普通正文 **粗体包含 *斜体文字* 结尾** 后续正文\n\n'
              '- 列表正文 **列表强调**\n'
              '- 第二项',
        ),
        theme,
      ),
    );

    final italic = _styleOf(tester, '斜体文字');
    expect(italic.fontStyle, FontStyle.italic);
    expect(italic.fontWeight, FontWeight.bold);
    expect(italic.color, theme.colorScheme.primary);
    expect(_styleOf(tester, '列表强调').fontWeight, FontWeight.bold);
    expect(_styleOf(tester, '列表强调').color, theme.colorScheme.primary);
    for (final text in ['普通正文', '后续正文', '列表正文', '第二项']) {
      expect(_styleOf(tester, text).color, theme.colorScheme.onSurface);
      expect(_styleOf(tester, text).fontWeight, isNot(FontWeight.bold));
    }
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏中的长代码、表格和列表可布局，代码仍可完整复制', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final code = 'const message = "${'long text ' * 30}";';
    final text =
        '```javascript\n$code\n```\n\n'
        '| 日期 | 心情 |\n| --- | --- |\n| 周一 | 平静 |\n\n'
        '- **今日建议**：散步并记录沿途见闻。\n'
        '- 明天继续';
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(child: AssistantReply(text: text)),
        buildMuiTheme(brightness: Brightness.dark),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MarkdownCodeBlock), findsOneWidget);
    final rendered = _spansOf(tester).map((span) => span.$1).join();
    for (final text in ['周一', '平静', '今日建议', '明天继续']) {
      expect(rendered, contains(text));
    }
    final codeScroll = find.descendant(
      of: find.byType(MarkdownCodeBlock),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(codeScroll).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(codeScroll, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    await tester.tap(find.text('复制'));
    await tester.pump();
    expect(copied, '$code\n');
    expect(find.text('已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
