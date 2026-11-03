import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_editor/src/data/editor_migration_service.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_platform/moodiary_platform.dart';

class _DeletedRepository extends Fake implements DiaryRepository {
  bool readWhileProtected = false;

  @override
  Future<Diary?> getDiaryByBusinessId(String id) async {
    readWhileProtected = !await MediaGuard().tryExclusive(
      MediaType.image,
      'image-test.jpg',
      () async {},
    );
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'migration does not recreate a diary deleted after the list was loaded',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'editor_migration_media',
      );
      final platform = PlatformService.get();
      platform.applicationSupportPath = root.path;
      final repo = _DeletedRepository();
      getIt.registerSingleton<DiaryRepository>(repo);
      addTearDown(() async {
        await getIt.reset();
        await root.delete(recursive: true);
      });
      final snapshot = Diary.create(
        title: '',
        content: '![photo](image-test.jpg)',
        contentText: '',
        mood: DiaryMood.neutral,
        imageName: ['image-test.jpg'],
        audioName: const [],
        videoName: const [],
        tags: const [],
        type: DiaryType.markdown,
      );
      expect(await EditorMigrationService.migrate(snapshot), isFalse);
      expect(repo.readWhileProtected, isTrue);
      expect(
        await MediaGuard().tryExclusive(
          MediaType.image,
          'image-test.jpg',
          () async {},
        ),
        isTrue,
      );
    },
  );
}
