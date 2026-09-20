import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_drawer.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

class _RecordingDiaryRepository extends Fake implements DiaryRepository {
  final renamedTags = <(String, String)>[];
  final deletedTags = <String>[];

  @override
  Future<int> renameTag(String tag, String replacement) async {
    renamedTags.add((tag, replacement));
    return 1;
  }

  @override
  Future<int> deleteTag(String tag) async {
    deletedTags.add(tag);
    return 1;
  }
}

void main() {
  late MemoryKVStorage kv;
  late _RecordingDiaryRepository repository;
  const expandedPaths = ['生活', '生活/旅行', '生活/旅行/海边', '生活/旅行记'];

  setUp(() {
    kv = MemoryKVStorage();
    kv.data[MoodiaryKVs.expandedTagPaths.name] = expandedPaths;
    repository = _RecordingDiaryRepository();
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(kv);
        gi.registerSingleton<DiaryRepository>(repository);
      },
    );
  });

  tearDown(() => getIt.popScope());

  Future<void> openTagAction(WidgetTester tester, String action) async {
    await tester.pumpWidget(
      muiTestApp(
        const TagDrawer(),
        overrides: [
          diaryTagsProvider.overrideWith(
            (ref) async => ['生活/旅行/海边/日落', '生活/旅行记/夏天'],
          ),
          tagDiaryCountsProvider.overrideWith(
            (ref) async =>
                (byTag: const <String, int>{}, total: 0, untagged: 0),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
    await tester.longPress(find.text('旅行'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets('renaming migrates expansion for the whole matching subtree', (
    tester,
  ) async {
    await openTagAction(tester, '重命名标签');
    await tester.enterText(find.byType(TextField), '生活/出游');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(repository.renamedTags, [('生活/旅行', '生活/出游')]);
    expect(repository.deletedTags, isEmpty);
    expect(
      kv.data[MoodiaryKVs.expandedTagPaths.name],
      unorderedEquals(['生活', '生活/出游', '生活/出游/海边', '生活/旅行记']),
    );
  });

  testWidgets('deleting removes only expansion under the matching prefix', (
    tester,
  ) async {
    await openTagAction(tester, '删除标签');
    expect(repository.deletedTags, isEmpty);
    expect(kv.data[MoodiaryKVs.expandedTagPaths.name], expandedPaths);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(repository.deletedTags, ['生活/旅行']);
    expect(repository.renamedTags, isEmpty);
    expect(
      kv.data[MoodiaryKVs.expandedTagPaths.name],
      unorderedEquals(['生活', '生活/旅行记']),
    );
  });
}
