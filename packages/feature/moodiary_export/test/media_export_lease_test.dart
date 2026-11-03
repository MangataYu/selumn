import 'dart:io';

import 'package:fast_press/fast_press.dart';
// FRB's mock API is intentionally internal to fast_press.
import 'package:fast_press/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_export/src/data/export_options.dart';
import 'package:moodiary_export/src/data/export_scope.dart';
import 'package:moodiary_export/src/data/export_service.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_platform/moodiary_platform.dart';

class _FakeCancelToken extends Fake implements CancelToken {}

class _FakePressApi extends Fake implements FastPressLibApi {
  @override
  CancelToken crateApiCancelCancelTokenNew() => _FakeCancelToken();
}

class _EmptyDiaryRepository extends Fake implements DiaryRepository {
  bool protected = false;

  @override
  Future<List<Diary>> getAllDiaries() async {
    protected = !await MediaGuard().tryExclusive(
      MediaType.image,
      'image-candidate.jpg',
      () async {},
    );
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('export holds media before resolving the diary snapshot', () async {
    FastPressLib.initMock(api: _FakePressApi());
    addTearDown(FastPressLib.dispose);
    final root = await Directory.systemTemp.createTemp('export_media_lease');
    PlatformService.get().applicationSupportPath = root.path;
    final repo = _EmptyDiaryRepository();
    getIt.registerSingleton<DiaryRepository>(repo);
    addTearDown(() async {
      await getIt.reset();
      await root.delete(recursive: true);
    });
    await expectLater(
      ExportService.run(
        format: .markdown,
        scope: const AllDiariesScope(),
        settings: const ExportSettings(),
        untitledLabel: 'Untitled',
        videoLabel: 'Video',
        audioLabel: 'Audio',
      ),
      throwsA(isA<ExportException>()),
    );
    expect(repo.protected, isTrue);
    expect(
      await MediaGuard().tryExclusive(
        MediaType.image,
        'image-candidate.jpg',
        () async {},
      ),
      isTrue,
    );
  });
}
