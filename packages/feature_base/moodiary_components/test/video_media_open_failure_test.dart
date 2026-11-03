import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_components/src/common/video/video_fullscreen_page.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:mui/mui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => LocaleSettings.setLocale(AppLocale.zh));

  testWidgets('failed media lock shows an error and permits a later retry', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('video_open_failure');
    final support = Directory('${root.path}/missing');
    PlatformService.get().applicationSupportPath = support.path;
    addTearDown(() => root.deleteSync(recursive: true));

    late BuildContext context;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: buildMuiTheme(brightness: Brightness.light),
          localizationsDelegates: const [GlobalMuiLocalizations.delegate],
          builder: FlutterSmartDialog.init(),
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => MVideoPlayerPage.showByName(context, name: 'video-1.mp4'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.common.loadFailed), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Retry after the context is gone: a fresh lock file proves the previous
    // failure did not leave the static opening flag stuck on.
    await tester.pumpWidget(const SizedBox.shrink());
    support.createSync();
    await tester.runAsync(
      () => MVideoPlayerPage.showByName(context, name: 'video-1.mp4'),
    );
    final lockDirectory = Directory('${support.path}/.media-locks');
    expect(lockDirectory.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });
}
