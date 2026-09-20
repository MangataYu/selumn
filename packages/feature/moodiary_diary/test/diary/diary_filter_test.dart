import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';

void main() {
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
  });

  test('equality distinguishes all from uncategorized', () {
    expect(const DiaryFilter.all(), const DiaryFilter.all());
    expect(const DiaryFilter.all() == const .uncategorized(), isFalse);
    expect(const DiaryFilter.category('a') == const .category('a'), isTrue);
    expect(const DiaryFilter.category('a') == const .category('b'), isFalse);
    expect(
      const DiaryFilter.all().hashCode ==
          const DiaryFilter.uncategorized().hashCode,
      isFalse,
    );
  });
}
