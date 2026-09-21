import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';

void main() {
  test('content filters remain separate from tags and all diaries', () {
    const filters = [
      DiaryFilter.images(),
      DiaryFilter.links(),
      DiaryFilter.audio(),
    ];
    expect(filters.toSet(), hasLength(3));
    expect(filters.map((filter) => filter.content).toSet(), hasLength(3));
    for (final filter in filters) {
      expect(filter.isAll, isFalse);
      expect(filter.untagged, isFalse);
      expect(filter.tagPath, isNull);
      expect(filter, isNot(const DiaryFilter.all()));
      expect(filter, isNot(const DiaryFilter.untagged()));
    }
    expect(const DiaryFilter.images(), const DiaryFilter.images());
    expect(const DiaryFilter.links().toString(), 'DiaryFilter.links()');
  });
  test('reselecting a tag still notifies navigation listeners', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final picks = <DiaryFilter>[];
    container.listen(homeDiaryFilterProvider, (_, next) => picks.add(next));
    final controller = container.read(homeDiaryFilterProvider.notifier);
    controller.select(const DiaryFilter.tag('生活'));
    controller.select(const DiaryFilter.tag('生活'));
    expect(picks, [const DiaryFilter.tag('生活'), const DiaryFilter.tag('生活')]);
  });

  test('tag filters distinguish parent paths, exact paths and untagged', () {
    const parent = DiaryFilter.tag('生活');
    const child = DiaryFilter.tag('生活/旅行');
    const none = DiaryFilter.untagged();

    expect(parent.tagPath, '生活');
    expect(parent.isAll, isFalse);
    expect(child, isNot(parent));
    expect(child, const DiaryFilter.tag('生活/旅行'));
    expect(none.untagged, isTrue);
    expect(none.tagPath, isNull);
    expect(none.isAll, isFalse);
    expect(none, isNot(const DiaryFilter.all()));
  });

  test('three states are mutually exclusive', () {
    const all = DiaryFilter.all();
    const cat = DiaryFilter.category('tr');
    const none = DiaryFilter.uncategorized();

    expect(all.isAll, isTrue);
    expect(all.uncategorized, isFalse);
    expect(all.categoryId, isNull);

    expect(cat.isAll, isFalse);
    expect(cat.categoryId, 'tr');

    expect(none.categoryId, isNull);
    expect(none.isAll, isFalse);
    expect(none.uncategorized, isTrue);

    expect(all == none, isFalse);
    expect(cat == const DiaryFilter.category('b'), isFalse);
  });
}
