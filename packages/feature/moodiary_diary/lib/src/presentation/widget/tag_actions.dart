import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_diary/src/application/tag_management.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

import 'tag_rename_sheet.dart';

Future<void> showTagActions(BuildContext context, String tag) async {
  final management = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(tagManagementProvider);
  final isDefault = management.savedDefaultTag == tag;
  final action = await MSheet.show<String>(
    context,
    builder: (sheetContext) => MSheetScaffold<String>(
      title: '#$tag',
      icon: LucideIcons.tag,
      actions: [MAction(label: sheetContext.l10n.common.cancel)],
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          MSheetOptionTile<String>(
            option: MSheetOption(
              value: 'default',
              label: isDefault
                  ? sheetContext.l10n.diary.tagClearDefault
                  : sheetContext.l10n.diary.tagSetDefault,
              icon: LucideIcons.star,
            ),
            selected: isDefault,
            onTap: () => Navigator.of(sheetContext).pop('default'),
          ),
          MSheetOptionTile<String>(
            option: MSheetOption(
              value: 'rename',
              label: sheetContext.l10n.diary.tagRename,
              icon: LucideIcons.pencil,
            ),
            selected: false,
            onTap: () => Navigator.of(sheetContext).pop('rename'),
          ),
          MDangerRow(
            label: sheetContext.l10n.diary.tagDelete,
            onPressed: () => Navigator.of(sheetContext).pop('delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'default') {
    try {
      management.setDefaultTag(isDefault ? '' : tag);
    } catch (_) {
      toast.error(message: l10n.diary.saveFailed);
    }
  } else if (action == 'rename') {
    await MSheet.show<void>(
      context,
      builder: (sheetContext) => TagRenameSheet(
        tag: tag,
        onSubmit: (value) async {
          try {
            await management.rename(tag, value);
            return null;
          } catch (_) {
            final message = l10n.diary.tagUpdateFailed;
            if (!sheetContext.mounted ||
                ModalRoute.of(sheetContext)?.isCurrent != true) {
              toast.error(message: message);
            }
            return message;
          }
        },
      ),
    );
  } else if (action == 'delete') {
    final confirmed = await MSheet.show<bool>(
      context,
      builder: (sheetContext) => MSheetScaffold<bool>(
        title: sheetContext.l10n.diary.tagDelete,
        icon: LucideIcons.trash2,
        isDestructive: true,
        actions: [
          MAction(label: sheetContext.l10n.common.cancel, value: false),
          MAction(
            label: sheetContext.l10n.common.delete,
            value: true,
            isDestructive: true,
          ),
        ],
        child: Text(
          sheetContext.l10n.diary.tagDeleteMessage(tag: tag),
          style: sheetContext.theme.typography.bodyMedium.onSurfaceVariant,
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await management.delete(tag);
    } catch (_) {
      toast.error(message: l10n.diary.tagUpdateFailed);
    }
  }
}
