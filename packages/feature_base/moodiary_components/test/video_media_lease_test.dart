import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_components/src/common/video/video_player_port_impl.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:mui/mui.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _BlockingVideoPlatform extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>.broadcast();
  final listened = Completer<void>();
  final disposeStarted = Completer<void>();
  final finishDispose = Completer<void>();

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 7;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    listened.complete();
    return events.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> dispose(int playerId) async {
    disposeStarted.complete();
    await finishDispose.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'video media stays leased until native player disposal completes',
    () async {
      final root = await Directory.systemTemp.createTemp('video_media_lease');
      PlatformService.get().applicationSupportPath = root.path;
      final platform = _BlockingVideoPlatform();
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = platform;
      addTearDown(() async {
        if (!platform.finishDispose.isCompleted) {
          platform.finishDispose.complete();
        }
        VideoPlayerPlatform.instance = previous;
        await platform.events.close();
        await root.delete(recursive: true);
      });
      final port = VideoPlayerPluginPort(
        VideoSource.file('${root.path}/video-1.mp4'),
      );
      final initializing = port.initialize();
      await platform.listened.future;
      platform.events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(100, 100),
        ),
      );
      await initializing;
      final closing = port.dispose();
      await platform.disposeStarted.future;
      final guard = MediaGuard();
      expect(
        await guard.tryExclusive(MediaType.video, 'video-1.mp4', () async {}),
        isFalse,
      );
      platform.finishDispose.complete();
      await closing;
      expect(
        await guard.tryExclusive(MediaType.video, 'video-1.mp4', () async {}),
        isTrue,
      );
    },
  );
}
