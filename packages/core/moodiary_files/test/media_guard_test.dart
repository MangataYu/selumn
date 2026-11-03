import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_lint/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late MediaGuard guard;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('media_guard');
    guard = MediaGuard(supportPath: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'same-process instances share leases and release only after last user',
    () async {
      final other = MediaGuard(supportPath: root.path);
      final first = await guard.acquire(.image, 'image-1.jpg');
      final second = await other.acquire(.image, 'image-1.jpg');
      var called = false;
      Future<void> action() async => called = true;
      expect(await other.tryExclusive(.image, 'image-1.jpg', action), isFalse);
      await first.release();
      expect(await guard.tryExclusive(.image, 'image-1.jpg', action), isFalse);
      await second.release();
      expect(await guard.tryExclusive(.image, 'image-1.jpg', action), isTrue);
      expect(called, isTrue);
    },
  );

  test('video and thumbnail share a lease', () async {
    final lease = await guard.acquire(.video, 'video-123.mp4');
    expect(
      await guard.tryExclusive(.video, 'thumbnail-123.jpeg', () async {}),
      isFalse,
    );
    await lease.release();
    expect(
      await guard.tryExclusive(.video, 'thumbnail-123.jpeg', () async {}),
      isTrue,
    );
  });

  test(
    'exclusive operation blocks new local uses until it completes',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final operation = guard.tryExclusive(.audio, 'audio-1.m4a', () async {
        started.complete();
        await finish.future;
      });
      await started.future;
      var acquired = false;
      final pending = MediaGuard(supportPath: root.path)
          .acquire(.audio, 'audio-1.m4a')
          .then((lease) {
            acquired = true;
            return lease;
          });
      await Future<void>.delayed(Duration.zero);
      expect(acquired, isFalse);
      finish.complete();
      expect(await operation, isTrue);
      await (await pending).release();
    },
  );

  test('legacy names remain usable but cannot be deleted', () async {
    for (final name in [
      '',
      '.',
      '..',
      '../x',
      r'..\x',
      '中文.jpg',
      'image-K.jpg',
      'IMAGE-~1.JPG',
      'image.jpg:stream',
      'image.jpg.',
      'image.jpg ',
      'CON',
      'nul.txt',
      'COM1.jpg',
      'lpt9',
      'line\nbreak.jpg',
    ]) {
      final lease = await guard.acquire(.image, name);
      expect(MediaGuard.supportsDeletion(MediaKey(.image, name)), isFalse);
      await lease.release();
      expect(await guard.tryExclusive(.image, name, () async {}), isFalse);
    }
    expect(
      MediaGuard.supportsDeletion(const MediaKey(.image, 'image-1_a.jpg')),
      isTrue,
    );
  });

  test('rejects use from a background isolate', () async {
    final path = root.path;
    await expectLater(
      Isolate.run(() => MediaGuard(supportPath: path).acquire(.image, 'x')),
      throwsStateError,
    );
  });

  test(
    'shared locks prevent another process from deleting and vice versa',
    () async {
      final lockPath = await _lockPath(root, .image, 'image-1.jpg');
      await File(lockPath).parent.create(recursive: true);
      final holder = await _startHolder(lockPath, 'shared');
      addTearDown(() async {
        holder.kill();
        await holder.exitCode;
      });
      expect(
        await guard.tryExclusive(.image, 'image-1.jpg', () async {}),
        isFalse,
      );
      holder.stdin.writeln('release');
      await holder.stdin.flush();
      expect(await holder.exitCode, 0);
      expect(
        await guard.tryExclusive(.image, 'image-1.jpg', () async {}),
        isTrue,
      );

      final own = await guard.acquire(.image, 'image-1.jpg');
      final other = await _startHolder(lockPath, 'shared');
      addTearDown(() async {
        other.kill();
        await other.exitCode;
      });
      // Releasing our handle must not release the other process's shared lock.
      await own.release();
      expect(
        await guard.tryExclusive(.image, 'image-1.jpg', () async {}),
        isFalse,
      );
      other.stdin.writeln('release');
      await other.stdin.flush();
      expect(await other.exitCode, 0);
      expect(
        await guard.tryExclusive(.image, 'image-1.jpg', () async {}),
        isTrue,
      );

      final exclusive = await _startHolder(lockPath, 'exclusive');
      addTearDown(() async {
        exclusive.kill();
        await exclusive.exitCode;
      });
      var acquired = false;
      final blocked = guard.acquire(.image, 'image-1.jpg').then((lease) {
        acquired = true;
        return lease;
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(acquired, isFalse);
      exclusive.stdin.writeln('release');
      await exclusive.stdin.flush();
      expect(await exclusive.exitCode, 0);
      await (await blocked).release();
    },
  );
}

Future<String> _lockPath(Directory root, MediaType type, String name) async {
  final resolved = p.normalize(await root.resolveSymbolicLinks());
  final identity = Platform.isWindows ? resolved.toLowerCase() : resolved;
  final id = '$identity\u0000media';
  final digest = sha256.convert(utf8.encode(id)).toString();
  return p.join(root.path, '.media-locks', '$digest.lock');
}

Future<Process> _startHolder(String path, String mode) async {
  final executable = Platform.isWindows ? 'dart.exe' : 'dart';
  final cache = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final sdkDart = File(p.join(cache.path, 'dart-sdk', 'bin', executable));
  final holder = await Process.start(
    await sdkDart.exists() ? sdkDart.path : executable,
    [
      p.join(
        repoRoot,
        'packages/core/moodiary_files/test/fixtures/media_lock_holder.dart',
      ),
      path,
      mode,
    ],
  );
  final ready = await holder.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  expect(ready, 'locked');
  return holder;
}
