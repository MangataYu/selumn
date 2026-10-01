import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_desktop/app/locale.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:mui/mui.dart';

class DesktopSettingPage extends ConsumerWidget {
  const DesktopSettingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.app.settingsTitle)),
    body: ListView(
      padding: EdgeInsets.all(context.spacing.md),
      children: [
        ValueListenableBuilder(
          valueListenable: MoodiaryKVs.themeMode.getNotifier(),
          builder: (context, mode, _) => SettingListTile(
            title: context.l10n.app.themeMode,
            leading: const Icon(LucideIcons.contrast),
            trailing: Text(_themeLabels(context)[mode.clamp(0, 2)]),
            onTap: () => showDialog(
              context: context,
              builder: (dialogContext) => SimpleDialog(
                title: Text(context.l10n.app.themeMode),
                children: [
                  for (final (index, label) in _themeLabels(context).indexed)
                    SimpleDialogOption(
                      onPressed: () async {
                        MoodiaryKVs.themeMode.set(index);
                        await ref
                            .read(appSettingsControllerProvider.notifier)
                            .bumpTheme();
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                      child: Text(label),
                    ),
                ],
              ),
            ),
          ),
        ),
        ValueListenableBuilder(
          valueListenable: MoodiaryKVs.language.getNotifier(),
          builder: (context, code, _) => SettingListTile(
            title: context.l10n.app.language,
            leading: const Icon(LucideIcons.languages),
            trailing: Text(
              Language.values
                  .firstWhere(
                    (language) => language.languageCode == code,
                    orElse: () => Language.system,
                  )
                  .label(context),
            ),
            onTap: () => showDialog(
              context: context,
              builder: (dialogContext) => SimpleDialog(
                title: Text(context.l10n.app.language),
                children: [
                  for (final language in Language.values)
                    SimpleDialogOption(
                      onPressed: () async {
                        MoodiaryKVs.language.set(language.languageCode);
                        await applyStoredLanguage();
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                      child: Text(language.label(context)),
                    ),
                ],
              ),
            ),
          ),
        ),
        SettingListTile(
          title: context.l10n.app.syncBackup,
          leading: const Icon(LucideIcons.refreshCw),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => const BackupSyncRoute().push(context),
        ),
      ],
    ),
  );

  List<String> _themeLabels(BuildContext context) => [
    context.l10n.app.themeModeSystem,
    context.l10n.app.themeModeLight,
    context.l10n.app.themeModeDark,
  ];
}
