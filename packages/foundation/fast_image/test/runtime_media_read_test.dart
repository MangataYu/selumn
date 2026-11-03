import 'dart:async';
import 'dart:io';

import 'package:fast_image/fast_image.dart';
// FRB's mock interface is intentionally internal to this package.
import 'package:fast_image/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

class _BlockingImageApi extends Fake implements FastImageLibApi {
  final baselineStarted = Completer<void>();
  final finishBaseline = Completer<void>();

  @override
  Future<FastImageProbe> crateApiImageFastImageCodecProbe({
    required String filePath,
  }) async => const FastImageProbe(
    format: .jpeg,
    width: 5000,
    height: 5000,
    progressive: true,
    regionDecodable: false,
  );

  @override
  Future<FastImageMeta> crateApiImageFastImageCodecMakeThumbnails({
    required String filePath,
    required List<FastThumbnailTarget> targets,
    int? quality,
  }) async => const FastImageMeta(width: 5000, height: 5000, ext: 'jpg');

  @override
  Future<void> crateApiImageFastImageCodecToBaselineFile({
    required String filePath,
    required String outputPath,
  }) async {
    baselineStarted.complete();
    await finishBaseline.future;
  }
}

void main() {
  tearDown(() => FastImageRuntime.mediaReadLeaseFactory = null);

  test(
    'media lease remains held until an asynchronous read finishes',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      var held = false;
      FastImageRuntime.mediaReadLeaseFactory = () async {
        held = true;
        return () async => held = false;
      };
      final read = FastImageRuntime.withMediaRead(() async {
        started.complete();
        await finish.future;
        expect(held, isTrue);
        return 42;
      });
      await started.future;
      expect(held, isTrue);
      finish.complete();
      expect(await read, 42);
      expect(held, isFalse);
    },
  );

  test('media lease is released after a read fails', () async {
    var released = false;
    FastImageRuntime.mediaReadLeaseFactory = () async => () async {
      released = true;
    };
    await expectLater(
      FastImageRuntime.withMediaRead<void>(
        () async => throw StateError('read'),
      ),
      throwsStateError,
    );
    expect(released, isTrue);
  });

  test('derivative deletion does not reacquire a media read lease', () async {
    final root = await Directory.systemTemp.createTemp('fast_image_lock');
    addTearDown(() => root.delete(recursive: true));
    FastImageRuntime.configure(imageDir: root.path, thumbDir: root.path);
    FastImageRuntime.mediaReadLeaseFactory = () async =>
        throw StateError('must not acquire under the cleanup lock');
    await FastImageDerivatives.deleteFor('image-123.jpg');
  });

  test('detached baseline conversion holds its own lease until done', () async {
    final root = await Directory.systemTemp.createTemp('fast_image_baseline');
    final thumbs = await Directory('${root.path}/thumb').create();
    final input = File('${root.path}/image-baseline.jpg');
    final bytes = List<int>.filled(2 * 1024 * 1024, 0);
    bytes.setRange(0, 3, [0xff, 0xd8, 0xff]);
    await input.writeAsBytes(bytes);
    FastImageRuntime.configure(imageDir: root.path, thumbDir: thumbs.path);
    final api = _BlockingImageApi();
    FastImageLib.initMock(api: api);
    addTearDown(() async {
      if (!api.finishBaseline.isCompleted) api.finishBaseline.complete();
      FastImageLib.dispose();
      await root.delete(recursive: true);
    });
    var held = 0;
    FastImageRuntime.mediaReadLeaseFactory = () async {
      held++;
      return () async => held--;
    };
    await FastImageDerivatives.warm(input.path);
    await api.baselineStarted.future;
    expect(held, greaterThan(0));
    api.finishBaseline.complete();
    // The detached job releases its lease independently of the warm caller.
    for (var i = 0; i < 100 && held != 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(held, 0);
  });
}
