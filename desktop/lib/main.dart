import 'dart:ui';

import 'package:fast_image/fast_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_desktop/app/boot_failure_page.dart';
import 'package:moodiary_desktop/app/di/bootstrap.dart';
import 'package:moodiary_desktop/app/di/di.dart';
import 'package:moodiary_desktop/app/licenses.dart';
import 'package:moodiary_desktop/app/lifecycle/app_lock_observer.dart';
import 'package:moodiary_desktop/app/locale.dart';
import 'package:moodiary_desktop/app/router/router.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_editor/moodiary_editor.dart'
    show EditorMigrationService;
import 'package:moodiary_export/moodiary_export.dart' show showDiaryShareSheet;
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_migration/moodiary_migration.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_sync/moodiary_sync.dart';
import 'package:moodiary_theme/moodiary_theme.dart';

Future<void> _initSystem() async {
  await FastImageRuntime.init();
  await bootstrapPlatform();
  await configureDependencies();
  initializeUsageStartTime();
  await AppLockPin.load();
  await getIt<DiaryRepository>().migrateLegacyCategoriesToTags();
  await VersionMigrator.run();
  await setupPluralResolvers();
  await applyStoredLanguage();
  await EngineMigrationService.refresh();
  await EditorMigrationService.refreshRequiresMigration();

  try {
    final font = await getIt<FontRepository>().getActiveFont();
    await getIt<ThemeManager>().buildTheme(customFont: font?.themeDescriptor);
  } catch (error, stack) {
    logger.e(
      'desktop theme initialization failed',
      error: error,
      stackTrace: stack,
    );
    await getIt<ThemeManager>().buildTheme();
  }
  try {
    await activateSyncProvider();
  } catch (error, stack) {
    // An unavailable remote must not prevent access to the local diary.
    logger.e(
      'sync provider activation failed',
      error: error,
      stackTrace: stack,
    );
  }
  if (getIt<MoodiaryDatabase>().upgradedFrom != null) {
    MoodiaryKVs.syncPendingLocal.set(true);
  }
  getIt<AutoSyncWatcher>().start();
  DiaryShare.register(showDiaryShareSheet);
  runStartupMaintenance();
}

@visibleForTesting
String resolveInitialLocation() =>
    AppLockPin.enabled.value ? LockRoute.path : DiaryHomeRoute.path;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logger.e(
      'Flutter error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.f('desktop error', error: error, stackTrace: stack);
    return true;
  };
  registerThirdPartyLicenses();
  try {
    await _initSystem();
    buildRouter(initialLocation: resolveInitialLocation());
  } catch (error, stack) {
    logger.f('desktop bootstrap failed', error: error, stackTrace: stack);
    runApp(BootFailurePage(error: error));
    return;
  }
  runApp(
    TranslationProvider(
      child: ProviderScope(
        retry: (_, _) => null,
        child: const MoodiaryDesktop(),
      ),
    ),
  );
}

class MoodiaryDesktop extends ConsumerWidget {
  const MoodiaryDesktop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.common.appName,
      routerConfig: router,
      builder: (context, child) {
        // ignore: deprecated_member_use
        return MaterialUiCompatibilityBridge(
          child: FrostedGlassOverlayComponent(
            child: AppLockObserver(
              child: FlutterSmartDialog.init()(context, child!),
            ),
          ),
        );
      },
      theme: settings.lightTheme,
      darkTheme: settings.darkTheme,
      themeMode: settings.themeMode,
      locale: TranslationProvider.of(context).flutterLocale,
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        GlobalMuiLocalizations.delegate,
      ],
      supportedLocales: AppLocaleUtils.supportedLocales,
    );
  }
}
