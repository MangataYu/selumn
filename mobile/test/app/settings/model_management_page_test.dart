import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_ml/moodiary_ml.dart';
import 'package:moodiary_mobile/app/settings/presentation/services_page.dart';
import 'package:moodiary_mobile/app/settings/setting_routes.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

class _UnusedHttp extends Fake implements IHttpClient {}

class _ModelManager extends EmbeddingModelManager {
  _ModelManager() : super(_UnusedHttp());

  bool downloaded = false;
  EmbeddingModelSpec? selected;
  Completer<void>? downloadGate;
  Completer<void>? deleteGate;
  int downloadCalls = 0;
  int deleteCalls = 0;

  @override
  EmbeddingModelSpec? get active => selected;

  @override
  bool isDownloaded(EmbeddingModelSpec spec) => downloaded;

  @override
  Future<void> download(
    EmbeddingModelSpec spec, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    downloadCalls++;
    onProgress?.call(25, 100);
    await downloadGate?.future;
    downloaded = true;
  }

  @override
  Future<void> activate(EmbeddingModelSpec spec) async {
    selected = spec;
  }

  @override
  Future<void> delete(EmbeddingModelSpec spec) async {
    deleteCalls++;
    await deleteGate?.future;
    downloaded = false;
  }

  @override
  void deactivate() {
    selected = null;
  }
}

class _IndexService extends Fake implements EmbedIndexService {
  Completer<void>? clearGate;

  @override
  Future<int> drain({int? maxDiaries}) async => 0;

  @override
  Future<void> clearAll() async {
    await clearGate?.future;
  }
}

void main() {
  late Directory root;
  late _ModelManager models;
  late _IndexService index;
  late String? oldLocale;

  setUpAll(() async {
    await LocaleSettings.setLocale(AppLocale.zh);
    root = await Directory.systemTemp.createTemp('model-management');
    final support = await Directory('${root.path}/support').create();
    final cache = await Directory('${root.path}/cache').create();
    PlatformService.get().applicationSupportPath = support.path;
    PlatformService.get().applicationCachePath = cache.path;
  });

  tearDownAll(() async => root.delete(recursive: true));

  setUp(() async {
    oldLocale = Intl.defaultLocale;
    models = _ModelManager();
    index = _IndexService();
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(MemoryKVStorage());
        gi.registerSingleton<EmbeddingModelManager>(models);
        gi.registerSingleton<EmbedIndexService>(index);
      },
    );
  });

  tearDown(() async {
    await getIt.popScope();
    Intl.defaultLocale = oldLocale;
  });

  Widget host({required Widget child}) => TranslationProvider(
    child: MaterialApp(
      theme: buildMuiTheme(brightness: Brightness.light),
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        GlobalMuiLocalizations.delegate,
      ],
      supportedLocales: AppLocaleUtils.supportedLocales,
      locale: const Locale('zh'),
      builder: FlutterSmartDialog.init(),
      home: child,
    ),
  );

  testWidgets(
    'directly shows the model and download action on a narrow screen',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(child: const ModelManagementPage()));
      await tester.pumpAndSettle();

      expect(find.text(l10n.storage.manageModels), findsOneWidget);
      expect(
        find.text(embeddingModelCatalog.first.displayName),
        findsOneWidget,
      );
      expect(find.text(l10n.app.semanticEnableConfirm), findsOneWidget);
      expect(
        find.textContaining(l10n.app.semanticModelNotDownloaded),
        findsOneWidget,
      );
      expect(find.text(l10n.app.services), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('activating a downloaded model keeps the management page open', (
    tester,
  ) async {
    models.downloaded = true;
    await tester.pumpWidget(host(child: const ModelManagementPage()));
    await tester.pumpAndSettle();

    expect(find.text(l10n.app.semanticDeleteConfirm), findsOneWidget);
    expect(
      find.textContaining(l10n.app.semanticModelDownloaded),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.app.semanticEnableTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticEnableTitle).last);
    await tester.pumpAndSettle();

    expect(models.active?.id, embeddingModelCatalog.first.id);
    expect(find.byType(ModelManagementPage), findsOneWidget);
    expect(find.text(l10n.app.semanticDisableTitle), findsOneWidget);
    expect(
      find.textContaining('· ${l10n.app.semanticModelActive}'),
      findsOneWidget,
    );
    expect(find.text(l10n.app.semanticDeleteConfirm), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('disabling an active model reveals its delete action', (
    tester,
  ) async {
    models.downloaded = true;
    models.selected = embeddingModelCatalog.first;
    await tester.pumpWidget(host(child: const ModelManagementPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.app.semanticDisableTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticDisableConfirm));
    await tester.pumpAndSettle();

    expect(models.active, isNull);
    expect(find.byType(ModelManagementPage), findsOneWidget);
    expect(
      find.textContaining(l10n.app.semanticModelDownloaded),
      findsOneWidget,
    );
    expect(find.text(l10n.app.semanticDeleteConfirm), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a downloaded model updates the page', (tester) async {
    models.downloaded = true;
    await tester.pumpWidget(host(child: const ModelManagementPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticDeleteConfirm));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticDeleteConfirm).last);
    await tester.pumpAndSettle();

    expect(models.downloaded, isFalse);
    expect(find.byType(ModelManagementPage), findsOneWidget);
    expect(
      find.textContaining(l10n.app.semanticModelNotDownloaded),
      findsOneWidget,
    );
    expect(find.text(l10n.app.semanticDeleteConfirm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'download continues after leaving and reentering without a duplicate',
    (tester) async {
      models.downloadGate = Completer<void>();
      await tester.pumpWidget(
        host(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const ModelManagementPage(),
                  ),
                ),
                child: const Text('Open models'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open models'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.app.semanticEnableConfirm));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.app.semanticEnableConfirm).last);
      await tester.pump();
      expect(models.downloadCalls, 1);
      expect(
        find.textContaining(l10n.app.semanticDownloading(percent: '25')),
        findsOneWidget,
      );

      Navigator.of(tester.element(find.byType(ModelManagementPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open models'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.textContaining(l10n.app.semanticDownloading(percent: '25')),
        findsOneWidget,
      );
      final downloadButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, l10n.app.semanticEnableConfirm),
      );
      expect(downloadButton.onPressed, isNull);
      expect(models.downloadCalls, 1);

      models.downloadGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(models.active?.id, embeddingModelCatalog.first.id);
      expect(find.byType(ModelManagementPage), findsOneWidget);
      expect(
        find.textContaining('· ${l10n.app.semanticModelActive}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    },
  );

  testWidgets('failed download clears busy state and can be retried', (
    tester,
  ) async {
    models.downloadGate = Completer<void>();
    await tester.pumpWidget(host(child: const ModelManagementPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticEnableConfirm));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticEnableConfirm).last);
    await tester.pump();
    models.downloadGate!.completeError(StateError('download failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(models.operation.value, isNull);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, l10n.app.semanticEnableConfirm),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.byType(ModelManagementPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('delete and deactivate disable all model actions while running', (
    tester,
  ) async {
    models.downloaded = true;
    models.deleteGate = Completer<void>();
    await tester.pumpWidget(host(child: const ModelManagementPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticDeleteConfirm));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticDeleteConfirm).last);
    await tester.pump();
    expect(models.deleteCalls, 1);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, l10n.app.semanticDeleteConfirm),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, l10n.app.semanticEnableTitle),
          )
          .onPressed,
      isNull,
    );
    models.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(models.downloaded, isFalse);

    models.downloaded = true;
    models.selected = embeddingModelCatalog.first;
    index.clearGate = Completer<void>();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(child: const ModelManagementPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticDisableTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.app.semanticDisableConfirm));
    await tester.pump();
    expect(models.operation.value?.kind, EmbeddingModelOperationKind.disable);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, l10n.app.semanticEnableTitle),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, l10n.app.semanticDeleteConfirm),
          )
          .onPressed,
      isNull,
    );
    index.clearGate!.complete();
    await tester.pumpAndSettle();
    expect(models.operation.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('storage route opens model management instead of services', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: StorageRoute.path,
      routes: settingRoutes(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp.router(
          theme: buildMuiTheme(brightness: Brightness.light),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            GlobalMuiLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          locale: const Locale('zh'),
          builder: FlutterSmartDialog.init(),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (find.text(l10n.storage.loading).evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.storage.manageModels));
    await tester.pumpAndSettle();

    expect(find.byType(ModelManagementPage), findsOneWidget);
    expect(find.byType(ServicesPage), findsNothing);
    expect(find.text(embeddingModelCatalog.first.displayName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
