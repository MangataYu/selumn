import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiaryFilter {
  final String? categoryId;

  final bool uncategorized;

  final String? tagPath;

  final bool untagged;

  const DiaryFilter._(
    this.categoryId,
    this.uncategorized, [
    this.tagPath,
    this.untagged = false,
  ]);

  const DiaryFilter.all() : this._(null, false);

  const DiaryFilter.category(String id) : this._(id, false);

  const DiaryFilter.uncategorized() : this._(null, true);

  const DiaryFilter.tag(String path) : this._(null, false, path);

  const DiaryFilter.untagged() : this._(null, false, null, true);

  bool get isAll =>
      categoryId == null && !uncategorized && tagPath == null && !untagged;

  @override
  bool operator ==(Object other) =>
      other is DiaryFilter &&
      other.categoryId == categoryId &&
      other.uncategorized == uncategorized &&
      other.tagPath == tagPath &&
      other.untagged == untagged;

  @override
  int get hashCode => Object.hash(categoryId, uncategorized, tagPath, untagged);

  @override
  String toString() => isAll
      ? 'DiaryFilter.all()'
      : untagged
      ? 'DiaryFilter.untagged()'
      : tagPath != null
      ? 'DiaryFilter.tag($tagPath)'
      : uncategorized
      ? 'DiaryFilter.uncategorized()'
      : 'DiaryFilter.category($categoryId)';
}

class DiaryFilterNotifier extends Notifier<DiaryFilter> {
  @override
  DiaryFilter build() => const .all();

  // Selecting the same tag from another page still requests diary navigation.
  @override
  bool updateShouldNotify(DiaryFilter previous, DiaryFilter next) => true;

  void select(DiaryFilter filter) => state = filter;

  void reset() => state = const .all();
}

final homeDiaryFilterProvider =
    NotifierProvider<DiaryFilterNotifier, DiaryFilter>(DiaryFilterNotifier.new);
