import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('media-reuse');
    PlatformService.get().applicationSupportPath = root.path;
    PlatformService.get().applicationCachePath = root.path;
    await Directory(p.join(root.path, 'image')).create();
    await Directory(p.join(root.path, 'video')).create();
    await Directory(p.join(root.path, 'external')).create();
  });
  tearDownAll(() async => root.delete(recursive: true));

  test(
    'reuses an existing app image but rejects missing and unrelated paths',
    () async {
      final local = File(p.join(root.path, 'image', 'image-same.jpg'));
      await local.writeAsString('local');
      expect(await MediaManager.saveImage(XFile(local.path)), 'image-same.jpg');
      expect(
        await MediaManager.saveImage(
          XFile(p.join(root.path, 'image', 'image-missing.jpg')),
        ),
        isNull,
      );
      expect(
        await MediaManager.saveImage(
          XFile(p.join(root.path, 'external', 'image-same.jpg')),
        ),
        isNull,
      );
      expect(await local.readAsString(), 'local');
    },
  );

  test('reuses an existing app video but rejects a deleted file', () async {
    final local = File(p.join(root.path, 'video', 'video-same.mp4'));
    await local.writeAsString('video');
    final reused = await MediaManager.saveVideo(
      videoFileList: [XFile(local.path)],
    );
    expect(reused[local.path], 'video-same.mp4');
    await local.delete();
    expect(
      await MediaManager.saveVideo(videoFileList: [XFile(local.path)]),
      isEmpty,
    );
  });
}
