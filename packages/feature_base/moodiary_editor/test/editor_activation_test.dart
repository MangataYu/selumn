import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_editor/src/editor_local_server.dart';
import 'package:moodiary_editor/src/moodiary_editor.dart';
import 'package:moodiary_editor/src/transport/editor_transport.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

class _HttpServer extends Fake implements IHttpServer {
  @override
  Future<void> start({
    required HttpServerHandler handler,
    int preferredPort = 0,
    bool loopbackOnly = false,
    String? spoolDir,
    void Function(int received, int? total)? onBodyProgress,
  }) async {}

  @override
  int get port => 8080;
}

class _Transport extends EditorTransport {
  _Transport({this.readyDuringPrepare = false, this.result = true});

  final bool readyDuringPrepare;
  Object? result;
  Completer<Object?>? pendingActivation;
  late OnTransportMessage onMessage;
  final scripts = <String>[];
  int viewTaps = 0;

  void ready() => onMessage(jsonEncode({'type': 'ready'}));

  @override
  Future<void> prepare({
    required Uri pageUri,
    required OnTransportMessage onMessage,
    required OnTransportConsoleError onConsoleError,
    required OnTransportWebError onWebError,
    required bool debug,
  }) async {
    this.onMessage = onMessage;
    if (readyDuringPrepare) ready();
  }

  @override
  Future<void> run(String source) async {}

  @override
  Future<Object?> runForResult(String source) async {
    scripts.add(source);
    if (scripts.length == 1 && pendingActivation != null) {
      return pendingActivation!.future;
    }
    return result;
  }

  @override
  Widget buildView() => GestureDetector(
    key: const ValueKey('editor-view'),
    behavior: HitTestBehavior.opaque,
    onTap: () => viewTaps++,
    child: const SizedBox.expand(),
  );

  @override
  void dispose() {}
}

Widget _host(Widget child) => TranslationProvider(
  child: MaterialApp(
    theme: buildMuiTheme(brightness: Brightness.light),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() {
    getIt.registerSingleton<IKVStorage>(MemoryKVStorage());
    getIt.registerSingleton<EditorLocalServer>(
      EditorLocalServer(_HttpServer()),
    );
  });
  tearDown(() async => getIt.reset());

  test('initializes the editor in order without losing or executing text', () {
    const content = '{"text":"正文\\n\\"quoted\\""}';
    const title = '标题\n"; window.unexpected = true; //';
    const meta = '{"category":"生活"}';
    const links = '{"outgoing":[]}';
    const theme = <String, dynamic>{'dark': false, 'roles': <String, String>{}};

    final source = buildEditorActivationJs(
      content: content,
      title: title,
      editable: true,
      theme: theme,
      saveStatus: 'saved',
      meta: meta,
      links: links,
    );
    final lines = source.split('\n');
    expect(lines.removeAt(0), '(() => {');
    expect(lines.removeLast(), '})()');
    expect(lines.removeLast(), 'return true;');

    const names = [
      'setContent',
      'setTitle',
      'setEditable',
      'setTheme',
      'setSaveStatus',
      'setMeta',
      'setLinks',
    ];
    expect(lines, hasLength(names.length));
    final arguments = <dynamic>[];
    for (var i = 0; i < names.length; i++) {
      final prefix = 'window.MoodiaryBridge.${names[i]}(';
      expect(lines[i], startsWith(prefix));
      expect(lines[i], endsWith(');'));
      arguments.add(
        jsonDecode(lines[i].substring(prefix.length, lines[i].length - 2)),
      );
    }
    expect(arguments, [content, title, true, theme, 'saved', meta, links]);
  });

  testWidgets('a late ready after timeout initializes the document', (
    tester,
  ) async {
    final transport = _Transport();
    final controller = MoodiaryEditorController();
    var readyCalls = 0;
    await tester.pumpWidget(
      _host(
        MoodiaryEditor(
          controller: controller,
          initialContent: '已有日记正文',
          transportFactory: () => transport,
          onReady: () => readyCalls++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));

    expect(
      find.textContaining(l10n.editor.initializationTimeout),
      findsOneWidget,
    );
    expect(transport.scripts, isEmpty);
    expect(controller.isReady, isFalse);
    expect(readyCalls, 0);
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('editor-view'))) +
          const Offset(8, 8),
    );
    expect(transport.viewTaps, 0);

    transport.ready();
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining(l10n.editor.initializationTimeout),
      findsNothing,
    );
    expect(transport.scripts, hasLength(1));
    expect(transport.scripts.single, contains(jsonEncode('已有日记正文')));
    expect(controller.isReady, isTrue);
    expect(readyCalls, 1);
  });

  testWidgets('failed JavaScript activation never marks the editor ready', (
    tester,
  ) async {
    final transport = _Transport(result: null);
    final controller = MoodiaryEditorController();
    var readyCalls = 0;
    await tester.pumpWidget(
      _host(
        MoodiaryEditor(
          controller: controller,
          transportFactory: () => transport,
          onReady: () => readyCalls++,
        ),
      ),
    );
    await tester.pump();
    transport.ready();
    await tester.pump();
    await tester.pump();

    expect(transport.scripts, hasLength(1));
    expect(
      find.textContaining(l10n.editor.initializationFailed),
      findsOneWidget,
    );
    expect(controller.isReady, isFalse);
    expect(readyCalls, 0);
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const ValueKey('editor-view'))) +
          const Offset(8, 8),
    );
    expect(transport.viewTaps, 0);
  });

  testWidgets('ignores a ready message received after disposal', (
    tester,
  ) async {
    final transport = _Transport();
    var readyCalls = 0;
    await tester.pumpWidget(
      _host(
        MoodiaryEditor(
          transportFactory: () => transport,
          onReady: () => readyCalls++,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    transport.ready();
    await tester.pump();

    expect(transport.scripts, isEmpty);
    expect(readyCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready received during transport preparation is not lost', (
    tester,
  ) async {
    final transport = _Transport(readyDuringPrepare: true, result: 'true');
    final controller = MoodiaryEditorController();
    await tester.pumpWidget(
      _host(
        MoodiaryEditor(
          controller: controller,
          transportFactory: () => transport,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(transport.scripts, hasLength(1));
    expect(controller.isReady, isTrue);
  });

  testWidgets('replays updated state before allowing editing', (tester) async {
    final transport = _Transport()..pendingActivation = Completer<Object?>();
    final controller = MoodiaryEditorController();
    var readyCalls = 0;
    Widget editor(String meta) => _host(
      MoodiaryEditor(
        controller: controller,
        initialContent: '已有正文',
        metaJson: meta,
        transportFactory: () => transport,
        onReady: () => readyCalls++,
      ),
    );

    await tester.pumpWidget(editor('old'));
    await tester.pump();
    transport.ready();
    await tester.pump();
    expect(transport.scripts, hasLength(1));
    expect(controller.isReady, isFalse);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('editor-view'))),
    );
    expect(transport.viewTaps, 0);

    await tester.pumpWidget(editor('new'));
    transport.pendingActivation!.complete(true);
    await tester.pump();
    await tester.pump();

    expect(transport.scripts, hasLength(2));
    expect(transport.scripts.last, contains('setMeta(${jsonEncode('new')})'));
    expect(transport.scripts.last, contains(jsonEncode('已有正文')));
    expect(controller.isReady, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(readyCalls, 1);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('editor-view'))),
    );
    expect(transport.viewTaps, 1);
  });
}
