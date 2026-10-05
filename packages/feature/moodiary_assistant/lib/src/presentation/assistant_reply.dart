import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:moodiary_assistant/src/presentation/markdown_code_block.dart';
import 'package:mui/mui.dart';

class AssistantReply extends StatelessWidget {
  const AssistantReply({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final bodyStyle = theme.typography.bodyLarge.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: .centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.92),
          padding: const .symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colors.surfaceContainer,
            borderRadius: const .only(
              topLeft: .circular(16),
              topRight: .circular(16),
              bottomLeft: .circular(4),
              bottomRight: .circular(16),
            ),
          ),
          child: SelectionArea(
            child: GptMarkdown(
              text,
              style: bodyStyle,
              inlineComponents: _inlineComponents,
              styleSheet: GptMarkdownStyleSheet(
                heading: HeadingStyle(
                  textStyle: TextStyle(
                    color: theme.colors.onSurface,
                    fontFamily: bodyStyle.fontFamily,
                    fontFamilyFallback: bodyStyle.fontFamilyFallback,
                  ),
                  dividerColor: theme.colors.outlineVariant,
                ),
                link: LinkStyle(
                  color: theme.colors.primary,
                  hoverColor: theme.colors.primary,
                ),
                table: TableStyle(
                  borderColor: theme.colors.outlineVariant,
                  headerBackground: theme.colors.surfaceContainerHighest,
                ),
              ),
              inlineCodeStyle: InlineCodeStyle(
                color: theme.colors.onSurface,
                backgroundColor: theme.colors.surfaceContainerHighest,
                borderColor: theme.colors.outlineVariant,
              ),
              codeBuilder: (context, name, code, closed) =>
                  MarkdownCodeBlock(name: name, code: code),
            ),
          ),
        ),
      ),
    );
  }
}

final _inlineComponents = [
  for (final component in MarkdownComponent.inlineComponents)
    if (component is BoldMd) _AccentBoldMd() else component,
];

class _AccentBoldMd extends BoldMd {
  @override
  InlineSpan span(
    BuildContext context,
    String text,
    GptMarkdownConfig config,
  ) => super.span(
    context,
    text,
    config.copyWith(
      style: (config.style ?? const TextStyle()).copyWith(
        color: context.theme.colors.primary,
      ),
    ),
  );
}
