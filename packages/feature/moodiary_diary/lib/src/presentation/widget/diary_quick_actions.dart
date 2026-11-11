import 'package:moodiary_components/moodiary_components.dart' show DiaryShare;
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:mui/mui.dart';

import '../detail/diary_version_history_page.dart';

class DiaryQuickActions extends StatelessWidget {
  static const buttonSize = 48.0;
  static const _iconSize = 20.0;

  final String diaryId;
  final String timeLabel;
  final double timeTopInset;
  final bool canEdit;

  const DiaryQuickActions({
    super.key,
    required this.diaryId,
    required this.timeLabel,
    this.timeTopInset = 0,
    this.canEdit = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final defaultStyle = DefaultTextStyle.of(context);
    final time = TextPainter(
      text: TextSpan(
        text: timeLabel,
        style: defaultStyle.style.merge(
          context.theme.typography.labelMedium.onSurfaceVariant,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: defaultStyle.textHeightBehavior,
      maxLines: 1,
    )..layout();
    final iconOffset = timeTopInset + (time.height - buttonSize) / 2;
    time.dispose();

    return MMenuButton<VoidCallback>(
      tooltip: l10n.common.more,
      anchorBounds: Rect.fromCenter(
        center: Offset(buttonSize / 2, buttonSize / 2 + iconOffset),
        width: _iconSize,
        height: _iconSize,
      ),
      entries: [
        MMenuEntry(
          value: () => DiaryRoute(diaryId: diaryId, edit: true).push(context),
          label: l10n.diary.edit,
          icon: LucideIcons.squarePen,
          enabled: canEdit,
        ),
        MMenuEntry(
          value: () =>
              AssistantConversationRoute(citedDiaryId: diaryId).push(context),
          label: l10n.diary.askAssistant,
          icon: LucideIcons.botMessageSquare,
        ),
        MMenuEntry(
          value: () => DiaryShare.open(context, diaryId),
          label: l10n.diary.share,
          icon: LucideIcons.share,
        ),
        MMenuEntry(
          value: () => _openHistory(context),
          label: l10n.diary.versionHistory,
          icon: LucideIcons.history,
        ),
      ],
      onSelected: (action) {
        if (context.mounted) action();
      },
      child: SizedBox.square(
        dimension: buttonSize,
        child: Center(
          child: Transform.translate(
            offset: Offset(0, iconOffset),
            transformHitTests: false,
            child: Icon(
              LucideIcons.ellipsis,
              color: context.theme.colors.onSurfaceVariant,
              size: _iconSize,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    // A restored tag or date can remove the tile from the current feed.
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final restored = await DiaryVersionHistoryPage.open(context, diaryId);
    if (restored == true && navigator.mounted) {
      await router.pushRoute<void>(DiaryRoute(diaryId: diaryId));
    }
  }
}
