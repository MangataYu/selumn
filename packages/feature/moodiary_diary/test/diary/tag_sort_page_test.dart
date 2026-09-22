import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/presentation/tag/tag_manager_page.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

void main() {
  late MemoryKVStorage kv;

  Finder row(String path) => find.byKey(ValueKey('tag-manager-row:$path'));

  setUp(() {
    kv = MemoryKVStorage();
    getIt.pushNewScope(init: (gi) => gi.registerSingleton<IKVStorage>(kv));
  });

  tearDown(() => getIt.popScope());

  Future<void> openManager(
    WidgetTester tester, {
    List<String> tags = const ['A/a', 'A/b', 'B'],
    List<String> order = const [],
  }) async {
    if (order.isNotEmpty) kv.data[MoodiaryKVs.tagOrder.name] = order;
    await tester.pumpWidget(
      muiTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const TagManagerPage()),
            ),
            child: const Text('open'),
          ),
        ),
        overrides: [
          diaryTagsProvider.overrideWith((ref) async => tags),
          tagDiaryCountsProvider.overrideWith(
            (ref) async =>
                (byTag: const <String, int>{}, total: 0, untagged: 0),
          ),
        ],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> enterChildren(WidgetTester tester, String path) async {
    await tester.tap(find.byKey(ValueKey('tag-manager-children:$path')));
    await tester.pumpAndSettle();
  }

  Future<void> dragAfter(
    WidgetTester tester,
    String source,
    String target, {
    bool fromHandleEdge = false,
  }) async {
    final handle = find.byKey(ValueKey('tag-manager-handle:$source'));
    final start = fromHandleEdge
        ? tester.getTopLeft(handle) + const Offset(4, 4)
        : tester.getCenter(handle);
    final end = Offset(start.dx, tester.getBottomLeft(row(target)).dy + 10);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 6; step++) {
      await gesture.moveTo(Offset.lerp(start, end, step / 6)!);
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
    await gesture.moveBy(const Offset(0, 1));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dragging root tags immediately saves their whole subtrees', (
    tester,
  ) async {
    await openManager(tester);
    expect(find.text('标签管理'), findsOneWidget);
    expect(row('A/a'), findsNothing);
    await dragAfter(tester, 'A', 'B', fromHandleEdge: true);
    expect(
      tester.getTopLeft(row('B')).dy,
      lessThan(tester.getTopLeft(row('A')).dy),
    );
    expect(kv.data[MoodiaryKVs.tagOrder.name], ['B', 'A', 'A/a', 'A/b']);
    expect(find.byType(TagManagerPage), findsOneWidget);
  });

  testWidgets(
    'child ordering survives navigating back and reopening children',
    (tester) async {
      await openManager(tester);
      await enterChildren(tester, 'A');
      expect(find.text('#A'), findsOneWidget);
      expect(row('B'), findsNothing);
      await dragAfter(tester, 'A/a', 'A/b');
      expect(kv.data[MoodiaryKVs.tagOrder.name], ['A', 'A/b', 'A/a', 'B']);
      await tester.tap(find.byKey(const ValueKey('tag-manager-back')));
      await tester.pumpAndSettle();
      expect(row('A'), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-manager-parent')), findsNothing);
      await enterChildren(tester, 'A');
      expect(
        tester.getTopLeft(row('A/b')).dy,
        lessThan(tester.getTopLeft(row('A/a')).dy),
      );
    },
  );

  testWidgets('system back visits each parent before leaving saved ordering', (
    tester,
  ) async {
    await openManager(tester, tags: ['A/a/one', 'A/a/two', 'A/b', 'B']);
    await enterChildren(tester, 'A');
    await enterChildren(tester, 'A/a');
    await dragAfter(tester, 'A/a/one', 'A/a/two');
    final saved = ['A', 'A/a', 'A/a/two', 'A/a/one', 'A/b', 'B'];
    expect(kv.data[MoodiaryKVs.tagOrder.name], saved);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('#A'), findsOneWidget);
    expect(row('A/a'), findsOneWidget);
    expect(row('B'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(row('A'), findsOneWidget);
    expect(row('B'), findsOneWidget);
    expect(find.byType(TagManagerPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TagManagerPage), findsNothing);
    expect(kv.data[MoodiaryKVs.tagOrder.name], saved);
  });

  testWidgets('sorting a nested level saves the complete tree immediately', (
    tester,
  ) async {
    await openManager(tester, tags: ['A/a/leaf', 'A/b', 'B']);
    await enterChildren(tester, 'A');
    await dragAfter(tester, 'A/a', 'A/b');
    expect(kv.data[MoodiaryKVs.tagOrder.name], [
      'A',
      'A/b',
      'A/a',
      'A/a/leaf',
      'B',
    ]);
    expect(find.text('#A'), findsOneWidget);
    expect(find.byType(TagManagerPage), findsOneWidget);
  });

  testWidgets('empty tag set stays usable without creating a saved order', (
    tester,
  ) async {
    await openManager(tester, tags: []);
    expect(find.text('暂无标签'), findsOneWidget);
    expect(find.byType(ReorderableDragStartListener), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-manager-back')));
    await tester.pumpAndSettle();
    expect(find.byType(TagManagerPage), findsNothing);
    expect(kv.data.containsKey(MoodiaryKVs.tagOrder.name), isFalse);
  });
}
