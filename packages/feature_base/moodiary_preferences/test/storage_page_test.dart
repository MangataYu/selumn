import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_preferences/moodiary_preferences.dart';
import 'package:mui/mui.dart';

Widget _host(Widget child) => TranslationProvider(
  child: MaterialApp(
    theme: buildMuiTheme(brightness: Brightness.light),
    localizationsDelegates: const [GlobalMuiLocalizations.delegate],
    builder: FlutterSmartDialog.init(),
    home: child,
  ),
);

void main() {
  setUpAll(() async => LocaleSettings.setLocale(AppLocale.zh));

  testWidgets('shows a grouped snapshot and opens model management', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _host(
        StoragePage(
          loadUsage: () async => StorageUsage({
            .database: 1024,
            .image: 1024,
            .audio: 1024,
            .video: 1024,
            .model: 1024,
          }),
          onManageModels: () async => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('5.00 KB'), findsOneWidget);
    expect(find.text('3.00 KB'), findsOneWidget);
    expect(find.text(l10n.storage.database), findsOneWidget);
    expect(find.text(l10n.storage.media), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.storage.manageModels));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a failed scan and retries when requested', (tester) async {
    final first = Completer<StorageUsage>();
    var calls = 0;
    await tester.pumpWidget(
      _host(
        StoragePage(
          loadUsage: () {
            calls++;
            return calls == 1 ? first.future : Future.value(StorageUsage({}));
          },
        ),
      ),
    );
    expect(find.text(l10n.storage.loading), findsOneWidget);
    first.completeError(StateError('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.storage.failed), findsOneWidget);
    await tester.tap(find.text(l10n.storage.retry));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('0 B'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirms cleanup, reports partial failure and refreshes usage', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var scans = 0;
    var cleanups = 0;
    final cleanup =
        Completer<({int deletedFiles, int deletedBytes, int failedFiles})>();
    await tester.pumpWidget(
      _host(
        StoragePage(
          loadUsage: () async {
            scans++;
            return StorageUsage({});
          },
          cleanDownloads: () async {
            cleanups++;
            return cleanup.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.storage.cleanDownloads));
    await tester.pumpAndSettle();
    expect(cleanups, 0);
    await tester.tap(find.text(l10n.storage.cleanConfirm));
    await tester.pumpAndSettle();
    expect(cleanups, 1);
    cleanup.complete((deletedFiles: 1, deletedBytes: 1024, failedFiles: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find
          .text(l10n.storage.cleanPartial(count: 1, size: '1.00 KB', failed: 1))
          .hitTestable(),
      findsNWidgets(2),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(scans, 2);
    expect(
      find.text(
        l10n.storage.cleanPartial(count: 1, size: '1.00 KB', failed: 1),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the cleanup result visible if the rescan fails', (
    tester,
  ) async {
    var scans = 0;
    await tester.pumpWidget(
      _host(
        StoragePage(
          loadUsage: () async {
            if (++scans > 1) throw StateError('scan failed');
            return StorageUsage({});
          },
          cleanDownloads: () async =>
              (deletedFiles: 1, deletedBytes: 1024, failedFiles: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.storage.cleanDownloads));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.storage.cleanConfirm));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text(l10n.storage.failed), findsOneWidget);
    expect(
      find.text(l10n.storage.cleanDone(count: 1, size: '1.00 KB')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
