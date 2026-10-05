import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_editor/src/editor_local_server.dart';
import 'package:moodiary_http/moodiary_http.dart';

class _RecordingHttpServer extends Fake implements IHttpServer {
  late HttpServerHandler handler;

  @override
  Future<void> start({
    required HttpServerHandler handler,
    int preferredPort = 0,
    bool loopbackOnly = false,
    String? spoolDir,
    void Function(int received, int? total)? onBodyProgress,
  }) async {
    this.handler = handler;
  }

  @override
  int get port => 8080;

  @override
  Future<void> stop() async {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });

  for (final compressed in [false, true]) {
    test(
      'serves bundled TTF with font MIME (compressed=$compressed)',
      () async {
        final fontBytes = Uint8List.fromList([0, 1, 0, 0, 12, 34, 56, 78]);
        final assetName =
            'packages/moodiary_editor/assets/editor/NotoEmoji.ttf'
            '${compressed ? '.gz' : ''}';
        final assetBytes = compressed
            ? Uint8List.fromList(gzip.encode(fontBytes))
            : fontBytes;
        binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
          message,
        ) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          return key == assetName ? ByteData.sublistView(assetBytes) : null;
        });
        final transport = _RecordingHttpServer();
        final server = EditorLocalServer(transport);
        addTearDown(server.dispose);
        await server.ensureStarted();

        final response = await transport.handler(
          HttpServerRequest(
            method: 'GET',
            path: '/NotoEmoji.ttf',
            body: Uint8List(0),
          ),
        );

        expect(response.statusCode, 200);
        expect(response.headers['content-type'], 'font/ttf');
        expect(response.headers.containsKey('content-encoding'), isFalse);
        expect(response.body, fontBytes);
      },
    );
  }
}
