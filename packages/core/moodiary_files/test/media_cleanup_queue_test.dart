import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_files/moodiary_files.dart';

void main() {
  late Directory root;
  late MediaCleanupQueue queue;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media_cleanup_queue_');
    queue = MediaCleanupQueue(supportPath: root.path);
  });

  tearDown(() async => root.delete(recursive: true));

  test('requests survive a new queue instance and can be completed', () async {
    await queue.enqueue([
      const MediaKey(MediaType.image, 'image-a.jpg'),
      const MediaKey(MediaType.video, 'video-b.mp4'),
    ]);
    final recovered = await MediaCleanupQueue(supportPath: root.path).pending();
    expect(recovered, hasLength(1));
    expect(recovered.single.candidates.map((e) => (e.type, e.name)), [
      (MediaType.image, 'image-a.jpg'),
      (MediaType.video, 'video-b.mp4'),
    ]);
    await recovered.single.complete();
    await recovered.single.complete();
    expect(await queue.pending(), isEmpty);
  });

  test('incomplete writes are never treated as cleanup requests', () async {
    final dir = Directory('${root.path}/.media-cleanup-queue');
    await dir.create();
    await File('${dir.path}/interrupted.tmp').writeAsString('partial');
    expect(await queue.pending(), isEmpty);
  });

  test(
    'malformed requests report an error and remain for inspection',
    () async {
      final dir = Directory('${root.path}/.media-cleanup-queue');
      await dir.create();
      final file = File('${dir.path}/broken.json');
      await file.writeAsString('{}');
      await expectLater(queue.pending(), throwsFormatException);
      expect(await file.exists(), isTrue);
    },
  );

  test('one malformed request does not block other queued cleanup', () async {
    final dir = Directory('${root.path}/.media-cleanup-queue');
    await dir.create();
    final bad = File('${dir.path}/broken.json');
    await bad.writeAsString('{}');
    await queue.enqueue([const MediaKey(MediaType.image, 'image-ok.jpg')]);
    final errors = <Object>[];
    final requests = await queue.pending(
      onInvalid: (error, _) => errors.add(error),
    );
    expect(errors, hasLength(1));
    expect(requests.single.candidates.single.name, 'image-ok.jpg');
    await requests.single.complete();
    expect(await bad.exists(), isTrue);
  });
}
