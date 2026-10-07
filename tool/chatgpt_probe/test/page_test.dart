import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mui/mui.dart';
import 'package:selume_chatgpt_probe/i18n/strings.g.dart';
import 'package:selume_chatgpt_probe/main.dart';
import 'package:selume_chatgpt_probe/src/probe_controller.dart';
import 'package:selume_chatgpt_probe/src/protocol.dart';

class _TimedOutController extends ProbeController {
  @override
  Future<void> initialize() async {}

  @override
  String get phase => 'failed';

  @override
  String get errorCode => 'authorization_timeout';

  @override
  String get failedPhase => 'waiting_browser';

  @override
  int get failedElapsedSeconds => 900;
}

class _EmptyResponseController extends ProbeController {
  @override
  Future<void> initialize() async {}
  @override
  String get phase => 'failed';
  @override
  String get errorCode => 'empty_response_body';
  @override
  String get failedPhase => 'testing';
  @override
  int get errorHttpStatus => 200;
  @override
  String get responseFormat => 'missing';
  @override
  String get responseBodyFormat => 'empty';
  @override
  int get responseBytes => 0;
}

class _PendingController extends ProbeController {
  _PendingController({required this.active});

  final bool active;
  String? submittedAddress;

  @override
  Future<void> initialize() async {}

  @override
  String get phase => active ? 'waiting_browser' : 'pending_authorization';

  @override
  bool get busy => active && submittedAddress == null;

  @override
  bool get hasPendingSignIn => submittedAddress == null;

  @override
  bool get canPasteCallback => hasPendingSignIn;

  @override
  Future<void> submitCallbackUrl(String raw) async {
    if (!raw.contains('fixture-code')) {
      throw const ProbeException('state_mismatch');
    }
    submittedAddress = raw;
    notifyListeners();
  }
}

class _TestController extends ProbeController {
  final completion = Completer<void>();
  String currentPhase = 'restored';
  String currentReply = '';
  String? failure;
  bool running = false;
  bool passed = false;
  bool refreshed = false;

  @override
  Future<void> initialize() async {}
  @override
  bool get signedIn => true;
  @override
  bool get planEnabled => true;
  @override
  List<ProbeModel> get models => const [ProbeModel('fixture', 'Fixture model')];
  @override
  String get selectedModel => 'fixture';
  @override
  String get phase => currentPhase;
  @override
  String get reply => currentReply;
  @override
  String? get errorCode => failure;
  @override
  String? get failedPhase => failure == null ? null : 'testing';
  @override
  String? get responseFormat => failure == null ? null : 'html';
  @override
  bool get busy => running;
  @override
  List<ProbeStep> get steps => [ProbeStep('response', passed)];

  @override
  Future<void> sendTest() async {
    running = true;
    currentPhase = 'testing';
    notifyListeners();
    await completion.future;
    running = false;
    notifyListeners();
  }

  @override
  Future<void> refreshAndTest() {
    refreshed = true;
    return sendTest();
  }

  void finish({String? error}) {
    failure = error;
    currentReply = 'OK';
    passed = error == null;
    currentPhase = passed ? 'completed' : 'failed';
    completion.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty response explains failure and copies body diagnostics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await LocaleSettings.setLocale(ProbeLocale.zh);
    final controller = _EmptyResponseController();
    addTearDown(controller.dispose);
    String? diagnostics;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          diagnostics = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      TranslationProvider(child: ProbeApp(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text(probeL10n.emptyResponseError), findsOneWidget);
    expect(find.text(probeL10n.testSuccess), findsNothing);
    await tester.scrollUntilVisible(
      find.text(probeL10n.copy),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(probeL10n.copy));
    await tester.pumpAndSettle();
    expect(diagnostics, contains('Selume ChatGPT Probe 0.1.4'));
    expect(diagnostics, contains('code=empty_response_body'));
    expect(diagnostics, contains('http=200'));
    expect(diagnostics, contains('response_format=missing'));
    expect(diagnostics, contains('body_format=empty'));
    expect(diagnostics, contains('received_bytes=0'));
    expect(tester.takeException(), isNull);
  });

  for (final refresh in [false, true]) {
    for (final error in <String?>[null, 'unexpected_html_response']) {
      testWidgets(
        '${refresh ? "refresh" : "send"} shows progress then ${error ?? "success"} next to the test button',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await LocaleSettings.setLocale(ProbeLocale.zh);
          final controller = _TestController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            TranslationProvider(child: ProbeApp(controller: controller)),
          );
          await tester.pumpAndSettle();
          final scrollable = find.byType(Scrollable).first;
          final button = find.text(
            refresh ? probeL10n.refreshTest : probeL10n.test,
          );
          await tester.scrollUntilVisible(button, 200, scrollable: scrollable);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pump();
          final status = find.byKey(const ValueKey('test-status'));
          await tester.ensureVisible(status);
          await tester.pump();
          expect(tester.widget<Text>(status).data, probeL10n.testRunning);
          expect(controller.refreshed, refresh);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, probeL10n.test),
                )
                .onPressed,
            isNull,
          );

          controller.finish(error: error);
          await tester.pumpAndSettle();
          final expected = error == null
              ? probeL10n.testSuccess
              : probeL10n.testFailed;
          expect(tester.widget<Text>(status).data, expected);
          expect(find.widgetWithText(SnackBar, expected), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('OK'),
            100,
            scrollable: scrollable,
          );
          expect(find.text('OK'), findsOneWidget);
          if (error != null) {
            expect(find.text(probeL10n.testSuccess), findsNothing);
            expect(find.text(probeL10n.partialReply), findsOneWidget);
            expect(find.text(probeL10n.htmlResponseError), findsWidgets);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final active in [true, false]) {
    testWidgets(
      'manual callback can finish a ${active ? "waiting" : "restored"} sign-in',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await LocaleSettings.setLocale(ProbeLocale.zh);
        final controller = _PendingController(active: active);
        addTearDown(controller.dispose);
        var clipboardReads = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.getData') clipboardReads++;
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          TranslationProvider(child: ProbeApp(controller: controller)),
        );
        await tester.pump();
        await tester.ensureVisible(find.text(probeL10n.pasteCallback));
        await tester.tap(find.text(probeL10n.pasteCallback));
        await tester.pump(const Duration(milliseconds: 350));
        expect(clipboardReads, 0);
        final input = tester.widget<TextField>(find.byType(TextField));
        expect(input.obscureText, isTrue);
        expect(input.enableIMEPersonalizedLearning, isFalse);

        await tester.enterText(
          find.byType(TextField),
          'https://auth.openai.com/',
        );
        await tester.tap(find.text(probeL10n.callbackSubmit));
        await tester.pump();
        expect(find.text(probeL10n.callbackInputError), findsOneWidget);
        expect(input.controller!.text, isEmpty);
        expect(controller.submittedAddress, isNull);

        const fixture =
            'http://127.0.0.1:3456/auth/callback?code=fixture-code&state=fixture';
        await tester.enterText(find.byType(TextField), fixture);
        await tester.tap(find.text(probeL10n.callbackSubmit));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(controller.submittedAddress, fixture);
        expect(find.text(fixture), findsNothing);
        expect(clipboardReads, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('phone layout requires sign-in and disables inference', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await LocaleSettings.setLocale(ProbeLocale.zh);
    var requests = 0;
    final controller = ProbeController(
      readState: () async => null,
      writeState: (_) async {},
      clientFactory: () => MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      TranslationProvider(child: ProbeApp(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    final testButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, probeL10n.test),
    );
    expect(testButton.onPressed, isNull);
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restored account still requires model selection at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = ProbeController(
        readState: () async => jsonEncode({
          'ext_agent_host_id': 'urn:uuid:12345678-1234-4234-8234-123456789abc',
          'client_id': 'oaiapp_fixture',
          'subject': 'fixture',
          'email': 'test@example.invalid',
          'access_token': 'fixture-not-a-real-token',
          'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
          'scopes': ['chatgpt.tokens.use.direct'],
        }),
        writeState: (_) async {},
        clientFactory: () => MockClient((_) async => http.Response('{}', 500)),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        TranslationProvider(child: ProbeApp(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(controller.planEnabled, isTrue);
      expect(controller.selectedModel, isNull);
      expect(find.text(probeL10n.permissionOn), findsOneWidget);
      await tester.scrollUntilVisible(find.text(probeL10n.test), 200);
      final testButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, probeL10n.test),
      );
      expect(testButton.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('authorization timeout explains retry before disabled testing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await LocaleSettings.setLocale(ProbeLocale.zh);
    final controller = _TimedOutController();
    addTearDown(controller.dispose);
    String? diagnostics;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          diagnostics = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      TranslationProvider(child: ProbeApp(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text(probeL10n.authorizationTimeoutError), findsOneWidget);
    final progressPosition = tester
        .getTopLeft(find.text(probeL10n.resultTitle))
        .dy;
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, probeL10n.login),
          )
          .onPressed,
      isNotNull,
    );
    final pageScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text(probeL10n.modelTitle),
      200,
      scrollable: pageScroll,
    );
    final scrollPosition = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(
      tester.getTopLeft(find.text(probeL10n.modelTitle)).dy + scrollPosition,
      greaterThan(progressPosition),
    );
    await tester.scrollUntilVisible(
      find.text(probeL10n.test),
      200,
      scrollable: pageScroll,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, probeL10n.test),
          )
          .onPressed,
      isNull,
    );

    await tester.scrollUntilVisible(
      find.text(probeL10n.copy),
      -200,
      scrollable: pageScroll,
    );
    await tester.tap(find.text(probeL10n.copy));
    await tester.pumpAndSettle();
    expect(diagnostics, contains('code=authorization_timeout'));
    expect(diagnostics, contains('failed_phase=waiting_browser'));
    expect(diagnostics, contains('elapsed_seconds=900'));
    expect(tester.takeException(), isNull);
  });
}
