import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/locale.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:mui/mui.dart';

class LanguageDialog extends StatelessWidget {
  const LanguageDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final code = MoodiaryKVs.language.get() ?? Language.system.languageCode;
    final current = Language.values.firstWhere(
      (e) => e.languageCode == code,
      orElse: () => Language.system,
    );
    return SimpleDialog(
      title: Padding(
        padding: .fromLTRB(
          context.spacing.md,
          context.spacing.md,
          context.spacing.md,
          0,
        ),
        child: Text(context.l10n.app.language),
      ),
      titleTextStyle: context.theme.typography.titleMedium.emphasized.onSurface,
      titlePadding: EdgeInsets.zero,
      contentPadding: .symmetric(vertical: context.spacing.sm),
      children: [
        for (final lang in Language.values)
          _Option(
            label: lang.label(context),
            selected: current == lang,
            onTap: () async {
              MoodiaryKVs.language.set(lang.languageCode);
              await applyStoredLanguage();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: onTap,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: .symmetric(
            horizontal: context.spacing.md,
            vertical: context.spacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                selected ? LucideIcons.check : LucideIcons.languages,
                size: 20,
              ),
              SizedBox(width: context.spacing.md),
              Expanded(
                child: Text(
                  label,
                  style: context.theme.typography.bodyLarge.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
