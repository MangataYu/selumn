import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_sort_page.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

void main() {
  Future<void> openSorter(
    WidgetTester tester, {
    required ValueChanged<List<String>?> onResult,
    List<String> tags = const ['A/a', 'A/b', 'B'],
    List<String> order = const [],
  }) async {
    await tester.pumpWidget(
      muiTestApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showTagSortPage(context, tags: tags, initialOrder: order),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> dragAfter(
    WidgetTester tester,
    String source,
    String target,
  ) async {
    final handle = find.byKey(ValueKey('tag-sort-handle:$source'));
    final targetRow = find.byKey(ValueKey('tag-sort-row:$target'));
    final start = tester.getCenter(handle);
    final end = Offset(start.dx, tester.getBottomLeft(targetRow).dy + 10);
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

  testWidgets('dragging root tags saves whole subtrees in the new order', (
    tester,
  ) async {
    List<String>? result;
    await openSorter(tester, onResult: (value) => result = value);
    expect(find.text('标签排序'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-sort-row:A/a')), findsNothing);
    await dragAfter(tester, 'A', 'B');
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('tag-sort-row:B'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('tag-sort-row:A'))).dy,
      ),
    );
    expect(result, isNull);
    await tester.tap(find.byKey(const ValueKey('tag-sort-save')));
    await tester.pumpAndSettle();
    expect(result, ['B', 'A', 'A/a', 'A/b']);
  });

  testWidgets('child ordering survives navigating back and saves from root', (
    tester,
  ) async {
    List<String>? result;
    await openSorter(tester, onResult: (value) => result = value);
    await tester.tap(find.byKey(const ValueKey('tag-sort-row:A')));
    await tester.pumpAndSettle();
    expect(find.text('#A'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-sort-row:B')), findsNothing);
    await dragAfter(tester, 'A/a', 'A/b');
    await tester.tap(find.byKey(const ValueKey('tag-sort-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-sort-row:A')), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.byKey(const ValueKey('tag-sort-save')));
    await tester.pumpAndSettle();
    expect(result, ['A', 'A/b', 'A/a', 'B']);
  });

  testWidgets('system back navigates parents before cancelling the draft', (
    tester,
  ) async {
    var completed = false;
    List<String>? result;
    await openSorter(
      tester,
      onResult: (value) {
        completed = true;
        result = value;
      },
    );
    await tester.tap(find.byKey(const ValueKey('tag-sort-row:A')));
    await tester.pumpAndSettle();
    await dragAfter(tester, 'A/a', 'A/b');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tag-sort-row:A')), findsOneWidget);
    expect(completed, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('save from a nested level returns the whole draft', (
    tester,
  ) async {
    List<String>? result;
    await openSorter(tester, onResult: (value) => result = value);
    await tester.tap(find.byKey(const ValueKey('tag-sort-row:A')));
    await tester.pumpAndSettle();
    await dragAfter(tester, 'A/a', 'A/b');
    await tester.tap(find.byKey(const ValueKey('tag-sort-save')));
    await tester.pumpAndSettle();
    expect(result, ['A', 'A/b', 'A/a', 'B']);
  });

  testWidgets('empty tag set stays usable', (tester) async {
    List<String>? result;
    await openSorter(tester, tags: [], onResult: (value) => result = value);
    expect(find.text('暂无标签'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tag-sort-save')));
    await tester.pumpAndSettle();
    expect(result, isEmpty);
  });
}
