import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_plus/isar_plus.dart';
import 'package:moodiary_migration/src/legacy/legacy_models.dart';
import 'package:moodiary_migration/src/orphan_media_cleaner.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('legacy-media-preservation');
    PlatformService.get().applicationSupportPath = root.path;
  });
  tearDownAll(() async => root.delete(recursive: true));

  setUp(() async {
    await Directory(p.join(root.path, 'database')).create();
    await Directory(p.join(root.path, 'image')).create();
  });
  tearDown(() async {
    await Directory(p.join(root.path, 'database')).delete(recursive: true);
    await Directory(p.join(root.path, 'image')).delete(recursive: true);
  });

  test(
    'does not inspect or delete media before the legacy database is ready',
    () async {
      final database = File(p.join(root.path, 'database', 'default.isar'));
      final image = File(p.join(root.path, 'image', 'image-legacy.jpg'));
      await database.writeAsString('legacy database not yet available');
      await image.writeAsString('photo');

      await cleanOrphanMediaIn(p.dirname(database.path));

      expect(await image.readAsString(), 'photo');
      expect(
        await database.readAsString(),
        'legacy database not yet available',
      );
      expect(
        await Directory(p.join(root.path, '.media-cleanup-queue')).exists(),
        isFalse,
      );
    },
  );

  final dylib = Platform.environment['ISAR_TEST_DYLIB'];
  test(
    'preserves an image referenced only by an unmigrated Isar chat message',
    () async {
      await Isar.initialize(dylib!);
      final dir = p.join(root.path, 'database');
      var isar = Isar.open(
        schemas: legacyMigrationSchemas,
        directory: dir,
        inspector: false,
      );
      isar.write(
        (db) => db.chatMessages.put(
          ChatMessage(
            id: 'message',
            sessionId: 'session',
            role: 'user',
            content: '',
            createdAt: DateTime.utc(2026),
            imageName: 'image-legacy.jpg',
          ),
        ),
      );
      isar.close();
      final image = File(p.join(root.path, 'image', 'image-legacy.jpg'));
      await image.writeAsString('chat photo');

      await cleanOrphanMediaIn(dir);

      expect(await image.readAsString(), 'chat photo');
      isar = Isar.open(
        schemas: legacyMigrationSchemas,
        directory: dir,
        inspector: false,
      );
      expect(
        isar.chatMessages.where().findFirst()?.imageName,
        'image-legacy.jpg',
      );
      isar.close();
    },
    skip: dylib == null || dylib.isEmpty
        ? '需要 ISAR_TEST_DYLIB 指向 libisar_plus 动态库'
        : false,
  );
}
