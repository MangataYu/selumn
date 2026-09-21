import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_diary/src/application/tag_order.dart';

void main() {
  test(
    'default order includes implicit parents and groups entire subtrees',
    () {
      expect(orderedTagPaths(['B/x', 'A/z', 'A/a', 'A-2'], []), [
        'A',
        'A/a',
        'A/z',
        'A-2',
        'B',
        'B/x',
      ]);
    },
  );

  test('saved order compares siblings and appends new siblings by name', () {
    expect(
      orderedTagPaths(
        ['A/old', 'A/new-z', 'A/new-a', 'B/child', 'C'],
        ['B', 'A/old', 'A', 'deleted', 'B'],
      ),
      ['B', 'B/child', 'A', 'A/old', 'A/new-a', 'A/new-z', 'C'],
    );
  });

  test('moving a parent carries its subtree and preserves child ordering', () {
    final draft = TagOrderDraft(
      ['A/a/leaf', 'A/b', 'B/a', 'C'],
      ['A', 'A/b', 'A/a', 'B', 'C'],
    );
    draft.reorder(null, 0, 2);
    expect(draft.paths, ['B', 'B/a', 'C', 'A', 'A/b', 'A/a', 'A/a/leaf']);
    draft.reorder('A', 1, 0);
    expect(draft.paths, ['B', 'B/a', 'C', 'A', 'A/a', 'A/a/leaf', 'A/b']);
  });

  test('draft edits leave caller tags and saved order untouched', () {
    final tags = ['A', 'B'];
    final order = ['B', 'A'];
    final draft = TagOrderDraft(tags, order)..reorder(null, 0, 1);
    expect(draft.paths, ['A', 'B']);
    expect(tags, ['A', 'B']);
    expect(order, ['B', 'A']);
  });

  test('rename remaps descendants and removes duplicates after a merge', () {
    expect(renameTagOrder(['A', 'A/a', 'AB', 'B', 'B/a'], 'A', 'B'), [
      'B',
      'B/a',
      'AB',
    ]);
  });

  test('delete drops only the requested subtree', () {
    expect(deleteTagOrder(['A', 'A/a', 'AB', 'B/a'], 'A'), ['AB', 'B/a']);
  });
}
