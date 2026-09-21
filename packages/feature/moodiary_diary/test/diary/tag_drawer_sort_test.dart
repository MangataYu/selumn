import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_drawer.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

void main() {
  late MemoryKVStorage kv;

  setUp(() {
    kv = MemoryKVStorage();
    getIt.pushNewScope(init: (gi) => gi.registerSingleton<IKVStorage>(kv));
  });
  tearDown(() => getIt.popScope());

  Future<void> pumpDrawer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      muiTestApp(
        const TagDrawer(),
        overrides: [
          diaryTagsProvider.overrideWith((ref) async => ['a/child', 'b', 'c']),
          tagDiaryCountsProvider.overrideWith(
            (ref) async =>
                (byTag: const <String, int>{}, total: 0, untagged: 0),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> visibleRoots(WidgetTester tester) {
    final roots = ['a', 'b', 'c'];
    roots.sort(
      (a, b) => tester
          .getTopLeft(find.byKey(ValueKey('tag-row:$a')))
          .dy
          .compareTo(tester.getTopLeft(find.byKey(ValueKey('tag-row:$b'))).dy),
    );
    return roots;
  }

  Future<void> reorder(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('tag-sort-button')));
    await tester.pumpAndSettle();
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 2);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sorting applies only after saving and survives drawer recreation',
    (tester) async {
      kv.data[MoodiaryKVs.expandedTagPaths.name] = ['a'];
      await pumpDrawer(tester);
      expect(visibleRoots(tester), ['a', 'b', 'c']);
      await reorder(tester);
      expect(kv.data[MoodiaryKVs.tagOrder.name], isNull);
      await tester.tap(find.byKey(const ValueKey('tag-sort-save')));
      await tester.pumpAndSettle();
      expect(kv.data[MoodiaryKVs.tagOrder.name], ['b', 'c', 'a', 'a/child']);
      expect(visibleRoots(tester), ['b', 'c', 'a']);
      expect(find.byKey(const ValueKey('tag-row:a/child')), findsOneWidget);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['a']);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpDrawer(tester);
      expect(visibleRoots(tester), ['b', 'c', 'a']);
    },
  );

  testWidgets('cancelling the sort leaves saved and visible order unchanged', (
    tester,
  ) async {
    kv.data[MoodiaryKVs.tagOrder.name] = ['c', 'a', 'a/child', 'b'];
    await pumpDrawer(tester);
    await reorder(tester);
    await tester.tap(find.byKey(const ValueKey('tag-sort-back')));
    await tester.pumpAndSettle();
    expect(kv.data[MoodiaryKVs.tagOrder.name], ['c', 'a', 'a/child', 'b']);
    expect(visibleRoots(tester), ['c', 'a', 'b']);
  });
}
