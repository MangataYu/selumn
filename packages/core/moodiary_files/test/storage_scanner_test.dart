import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String support;
  late String cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('storage-scanner-test-');
    support = p.join(root.path, 'support');
    cache = p.join(root.path, 'cache');
    await Directory(support).create();
    await Directory(cache).create();
  });

  tearDown(() => root.delete(recursive: true));

  Future<void> write(String path, int bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(bytes, 42));
  }

  Future<void> linkTo(String link, String target) async {
    if (Platform.isWindows) {
      final result = await Process.run('cmd', [
        '/c',
        'mklink',
        '/J',
        link,
        target,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    } else {
      await Link(link).create(target);
    }
  }

  test('accounts for app files and cache without mutating them', () async {
    await write(p.join(support, 'database', 'moodiary.db'), 10);
    await write(p.join(support, 'image', 'thumb', 'one.webp'), 20);
    await write(p.join(support, 'audio', 'one.m4a'), 30);
    await write(p.join(support, 'video', 'one.mp4'), 40);
    await write(p.join(support, 'model', 'model.onnx'), 50);
    await write(p.join(support, 'font', 'font.ttf'), 60);
    await write(p.join(support, 'sync_logs', 'today.log'), 70);
    await write(p.join(support, 'error.log'), 80);
    await write(p.join(support, 'error.log.1'), 5);
    await write(p.join(support, 'other', 'one'), 90);
    await write(p.join(cache, 'sync-media', 'active.part'), 100);

    final usage = await StorageScanner(
      supportPath: support,
      cachePath: cache,
    ).scan();

    expect(usage.bytesByCategory[StorageCategory.database], 10);
    expect(usage.bytesByCategory[StorageCategory.image], 20);
    expect(usage.bytesByCategory[StorageCategory.audio], 30);
    expect(usage.bytesByCategory[StorageCategory.video], 40);
    expect(usage.bytesByCategory[StorageCategory.model], 50);
    expect(usage.bytesByCategory[StorageCategory.font], 60);
    expect(usage.bytesByCategory[StorageCategory.logs], 155);
    expect(usage.bytesByCategory[StorageCategory.other], 90);
    expect(usage.bytesByCategory[StorageCategory.cache], 100);
    expect(usage.totalBytes, 555);
    expect(
      await File(p.join(cache, 'sync-media', 'active.part')).exists(),
      isTrue,
    );
  });

  test('does not count a nested cache tree twice', () async {
    final nestedCache = p.join(support, 'app-cache');
    await write(p.join(support, 'image', 'one.jpg'), 11);
    await write(p.join(nestedCache, 'temporary'), 13);

    final usage = await StorageScanner(
      supportPath: support,
      cachePath: nestedCache,
    ).scan();

    expect(usage.bytesByCategory[StorageCategory.image], 11);
    expect(usage.bytesByCategory[StorageCategory.cache], 13);
    expect(usage.bytesByCategory[StorageCategory.other], 0);
    expect(usage.totalBytes, 24);
  });

  test('does not count a nested support tree twice', () async {
    final nestedSupport = p.join(cache, 'app-data');
    await write(p.join(nestedSupport, 'database', 'db'), 7);
    await write(p.join(cache, 'temporary'), 9);

    final usage = await StorageScanner(
      supportPath: nestedSupport,
      cachePath: cache,
    ).scan();

    expect(usage.bytesByCategory[StorageCategory.database], 7);
    expect(usage.bytesByCategory[StorageCategory.cache], 9);
    expect(usage.totalBytes, 16);
  });

  test('reports missing directories as empty', () async {
    final usage = await StorageScanner(
      supportPath: p.join(root.path, 'missing-support'),
      cachePath: p.join(root.path, 'missing-cache'),
    ).scan();
    expect(usage.totalBytes, 0);
    expect(usage.bytesByCategory.keys, containsAll(StorageCategory.values));
  });

  test('rejects identical paths instead of misclassifying data', () async {
    expect(
      StorageScanner(supportPath: support, cachePath: support).scan(),
      throwsArgumentError,
    );
  });

  test('rejects roots that resolve to the same directory', () async {
    final alias = p.join(root.path, 'alias');
    await linkTo(alias, support);
    expect(
      StorageScanner(supportPath: support, cachePath: alias).scan(),
      throwsArgumentError,
    );
  });

  test('classifies a linked nested cache only once', () async {
    final nested = p.join(support, 'app-cache');
    final alias = p.join(root.path, 'cache-alias');
    await write(p.join(support, 'image', 'one.jpg'), 11);
    await write(p.join(nested, 'temporary'), 13);
    await linkTo(alias, nested);

    final usage = await StorageScanner(
      supportPath: support,
      cachePath: alias,
    ).scan();
    expect(usage.bytesByCategory[StorageCategory.image], 11);
    expect(usage.bytesByCategory[StorageCategory.cache], 13);
    expect(usage.bytesByCategory[StorageCategory.other], 0);
    expect(usage.totalBytes, 24);
  });

  test('reports an invalid root instead of treating it as empty', () async {
    final file = p.join(root.path, 'not-a-directory');
    await write(file, 1);
    await expectLater(
      StorageScanner(supportPath: file, cachePath: cache).scan(),
      throwsA(isA<FileSystemException>()),
    );
  });
}
