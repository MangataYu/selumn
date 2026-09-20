import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';
import 'package:moodiary_diary/src/application/diary_selection.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_drawer.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

import '../support/pump.dart';

Widget _drawer({
  TextScaler textScaler = TextScaler.noScaling,
  Widget? navigation,
  VoidCallback? onFilterSelected,
  List<String> tags = const ['a/b/c', 'a/z', 'reading'],
  Map<String, int> counts = const {
    'a': 123,
    'a/b': 24,
    'a/b/c': 3,
    'a/z': 7,
    'reading': 5,
  },
}) => muiTestApp(
  Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: TagDrawer(
        navigation: navigation,
        onFilterSelected: onFilterSelected,
      ),
    ),
  ),
  overrides: [
    diaryTagsProvider.overrideWith((ref) async => tags),
    tagDiaryCountsProvider.overrideWith(
      (ref) async => (byTag: counts, total: 125, untagged: 10),
    ),
  ],
);

Finder _row(String path) => find.byKey(ValueKey('tag-row:$path'));

Finder _hash(String path) =>
    find.descendant(of: _row(path), matching: find.byIcon(LucideIcons.hash));

double _iconCenter(WidgetTester tester, String path) =>
    tester.getCenter(_hash(path)).dx - tester.getTopLeft(_row(path)).dx;

double _ownGuideStart(WidgetTester tester, String path) =>
    tester.getRect(_hash(path)).bottom - tester.getRect(_row(path)).top + 2;

Finder _foregroundPaints(String path) => find.descendant(
  of: _row(path),
  matching: find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.foregroundPainter != null,
  ),
);

void _expectGuides(
  WidgetTester tester,
  String path,
  List<(double, double, double)> lines,
) {
  final finder = _foregroundPaints(path).first;
  final painter = tester.widget<CustomPaint>(finder).foregroundPainter!;
  final size = tester.getSize(finder);
  void paint(Canvas canvas) => painter.paint(canvas, size);

  final pattern = paints;
  for (final (x, start, end) in lines) {
    pattern.something(
      (method, arguments) =>
          method == #drawLine &&
          ((arguments[0] as Offset) - Offset(x, start)).distance < 0.01 &&
          ((arguments[1] as Offset) - Offset(x, end)).distance < 0.01,
    );
  }
  expect(paint, pattern, reason: 'Guide endpoints for $path');
  expect(paint, paintsExactlyCountTimes(#drawLine, lines.length));
}

void main() {
  late MemoryKVStorage kv;

  setUp(() {
    kv = MemoryKVStorage();
    getIt.pushNewScope(init: (gi) => gi.registerSingleton<IKVStorage>(kv));
  });

  tearDown(() => getIt.popScope());

  Future<void> pumpDrawer(
    WidgetTester tester, {
    List<String> expanded = const ['a', 'a/b'],
    Widget? child,
  }) async {
    kv.data[MoodiaryKVs.expandedTagPaths.name] = expanded;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(child ?? _drawer());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'counts align across every row and arrows reach the drawer edge',
    (tester) async {
      var filterPicks = 0;
      await pumpDrawer(
        tester,
        child: _drawer(onFilterSelected: () => filterPicks++),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TagDrawer)),
      );
      container
          .read(homeDiaryFilterProvider.notifier)
          .select(const DiaryFilter.tag('reading'));
      container.read(diarySelectionProvider.notifier).enter('selected-diary');
      await tester.pumpAndSettle();

      final right = tester.getRect(find.text('125')).right;
      // Include the all/untagged filters, two parent depths and leaf tags,
      // with one-, two- and three-digit counts.
      for (final count in ['123', '24', '3', '7', '5', '10']) {
        expect(tester.getRect(find.text(count)).right, closeTo(right, 0.01));
      }

      final drawerRight = tester.getRect(find.byType(Drawer)).right;
      for (final path in ['a', 'a/b']) {
        final button = find.byKey(ValueKey('tag-expand:$path'));
        final icon = find.descendant(of: button, matching: find.byType(Icon));
        expect(tester.getSize(button), const Size(40, 40));
        expect(tester.getRect(button).right, closeTo(drawerRight - 8, 0.01));
        expect(tester.getRect(icon).right, closeTo(drawerRight - 8, 0.01));
      }

      // The part of the button outside the icon must toggle without selecting.
      final parentButton = find.byKey(const ValueKey('tag-expand:a'));
      await tester.tapAt(tester.getTopLeft(parentButton) + const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(_row('a/b'), findsNothing);
      expect(_row('a'), findsOneWidget);
      expect(kv.data[MoodiaryKVs.expandedTagPaths.name], ['a/b']);
      expect(filterPicks, 0);
      expect(
        container.read(homeDiaryFilterProvider),
        const DiaryFilter.tag('reading'),
      );
      expect(container.read(diarySelectionProvider), {'selected-diary'});
      expect(find.byType(Drawer), findsOneWidget);
    },
  );

  testWidgets('settings sit beside the title before navigation and tags', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      child: _drawer(
        navigation: const SizedBox(height: 40, child: Text('Navigation')),
      ),
    );

    final settings = find.byTooltip(l10n.app.homeNavigatorSetting);
    expect(settings, findsOneWidget);
    expect(find.byIcon(LucideIcons.settings), findsOneWidget);
    final settingsRect = tester.getRect(settings);
    final titleRect = tester.getRect(find.text(l10n.common.appName));
    final countRect = tester.getRect(
      find.text(l10n.diary.searchResult(count: 125)),
    );
    expect(settingsRect.left, greaterThanOrEqualTo(titleRect.right));
    expect(settingsRect.top, lessThan(titleRect.bottom));
    expect(settingsRect.bottom, greaterThan(titleRect.top));
    expect(countRect.top, greaterThanOrEqualTo(titleRect.bottom));
    expect(countRect.left, closeTo(titleRect.left, 0.01));
    expect(
      settingsRect.bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Navigation')).top),
    );
    expect(settingsRect.bottom, lessThan(tester.getRect(_row('a')).top));
  });

  testWidgets(
    'resize preserves guides, aligned counts and large-text targets',
    (tester) async {
      await pumpDrawer(tester);
      for (final path in ['a', 'a/b', 'a/b/c', 'a/z', 'reading']) {
        expect(tester.getSize(_row(path)).height, 40);
      }
      await tester.pumpWidget(_drawer(textScaler: const TextScaler.linear(2)));
      await tester.pumpAndSettle();
      double previousInset = 0;
      for (final width in <double>[320, 390, 768]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final root = _iconCenter(tester, 'a');
        expect(root, greaterThan(previousInset));
        previousInset = root;
        final height = tester.getSize(_foregroundPaints('a').first).height;
        _expectGuides(tester, 'a', [
          (root, _ownGuideStart(tester, 'a'), height),
        ]);

        final right = tester.getRect(find.text('125')).right;
        for (final count in ['123', '24', '3', '7', '5', '10']) {
          expect(tester.getRect(find.text(count)).right, closeTo(right, 0.01));
        }
        final button = find.byKey(const ValueKey('tag-expand:a'));
        expect(tester.getSize(button), const Size(40, 40));
        expect(tester.getRect(_row('a')).height, greaterThan(40));
        expect(tester.getRect(_row('reading')).height, greaterThan(40));
        expect(
          tester
              .getRect(find.descendant(of: button, matching: find.byType(Icon)))
              .right,
          closeTo(tester.getRect(find.byType(Drawer)).right - 8, 0.01),
        );
      }
      await tester.tap(find.byKey(const ValueKey('tag-expand:a')));
      await tester.pumpAndSettle();
      expect(_row('a/b'), findsNothing);
    },
  );

  testWidgets('hyphenated siblings stay after the complete preceding subtree', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      expanded: ['a', 'a/b', 'a/b-b', 'a-b'],
      child: _drawer(tags: ['a-b/x', 'a/b-b/z', 'a/z', 'a/b/d', 'a/b/c']),
    );

    final paths = [
      'a',
      'a/b',
      'a/b/c',
      'a/b/d',
      'a/b-b',
      'a/b-b/z',
      'a/z',
      'a-b',
      'a-b/x',
    ];
    for (var index = 1; index < paths.length; index++) {
      expect(
        tester.getRect(_row(paths[index])).top,
        greaterThanOrEqualTo(tester.getRect(_row(paths[index - 1])).bottom),
      );
    }
  });

  testWidgets('each ancestor guide ends at its last visible descendant', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      expanded: ['a', 'a/b', 'a-b'],
      child: _drawer(tags: ['a/b/c', 'a/b/d', 'a/z', 'a-b/x']),
    );

    final height = tester.getSize(_foregroundPaints('a').first).height;
    final middle = height / 2;
    final root = _iconCenter(tester, 'a');
    final child = _iconCenter(tester, 'a/b');
    _expectGuides(tester, 'a', [(root, _ownGuideStart(tester, 'a'), height)]);
    _expectGuides(tester, 'a/b', [
      (root, 0, height),
      (child, _ownGuideStart(tester, 'a/b'), height),
    ]);
    _expectGuides(tester, 'a/b/c', [(root, 0, height), (child, 0, height)]);
    _expectGuides(tester, 'a/b/d', [(root, 0, height), (child, 0, middle)]);
    _expectGuides(tester, 'a/z', [(root, 0, middle)]);
    _expectGuides(tester, 'a-b', [
      (root, _ownGuideStart(tester, 'a-b'), height),
    ]);
    _expectGuides(tester, 'a-b/x', [(root, 0, middle)]);

    await tester.tap(find.byKey(const ValueKey('tag-expand:a/b')));
    await tester.pumpAndSettle();
    expect(_row('a/b/c'), findsNothing);
    _expectGuides(tester, 'a/b', [(root, 0, height)]);
    _expectGuides(tester, 'a/z', [(root, 0, middle)]);
  });

  testWidgets('deep paths keep at most four visible ancestor guides', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      expanded: ['a', 'a/b', 'a/b/c', 'a/b/c/d', 'a/b/c/d/e', 'a/b/c/d/e/f'],
      child: _drawer(tags: ['a/b/c/d/e/f/g']),
    );

    const path = 'a/b/c/d/e/f/g';
    final middle = tester.getSize(_foregroundPaints(path).first).height / 2;
    _expectGuides(tester, path, [
      for (final ancestor in ['a', 'a/b', 'a/b/c', 'a/b/c/d'])
        (_iconCenter(tester, ancestor), 0, middle),
    ]);
  });

  testWidgets('search results keep count alignment without tree guides', (
    tester,
  ) async {
    await pumpDrawer(
      tester,
      expanded: ['a', 'a/b', 'a-b'],
      child: _drawer(tags: ['a/b/c', 'a/b/d', 'a/z', 'a-b/x', 'reading']),
    );
    final right = tester.getRect(find.text('125')).right;

    expect(find.byType(SearchBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tag-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'a');
    await tester.pumpAndSettle();

    for (final count in ['123', '24', '3', '7', '5', '10']) {
      expect(tester.getRect(find.text(count)).right, closeTo(right, 0.01));
    }
    expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
    expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
    for (final path in ['a', 'a/b', 'a/b/c', 'a/b/d', 'a/z', 'a-b', 'a-b/x']) {
      expect(_row(path), findsOneWidget);
      for (final element in _foregroundPaints(path).evaluate()) {
        final widget = element.widget as CustomPaint;
        final size = tester.getSize(find.byWidget(widget));
        expect(
          (Canvas canvas) => widget.foregroundPainter!.paint(canvas, size),
          paintsExactlyCountTimes(#drawLine, 0),
          reason: 'Search result $path should have no tree guides',
        );
      }
    }
  });
}
