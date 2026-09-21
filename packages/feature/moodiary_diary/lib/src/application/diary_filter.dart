import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_models/moodiary_models.dart';

class DiaryFilter {
  final String? categoryId;

  final bool uncategorized;

  final String? tagPath;

  final bool untagged;

  final DiaryContentFilter? content;

  const DiaryFilter._(
    this.categoryId,
    this.uncategorized, [
    this.tagPath,
    this.untagged = false,
    this.content,
  ]);

  const DiaryFilter.all() : this._(null, false);

  const DiaryFilter.category(String id) : this._(id, false);

  const DiaryFilter.uncategorized() : this._(null, true);

  const DiaryFilter.tag(String path) : this._(null, false, path);

  const DiaryFilter.untagged() : this._(null, false, null, true);

  const DiaryFilter.images() : this._(null, false, null, false, .images);

  const DiaryFilter.links() : this._(null, false, null, false, .links);

  const DiaryFilter.audio() : this._(null, false, null, false, .audio);

  bool get hasImages => content == .images;

  bool get hasLinks => content == .links;

  bool get hasAudio => content == .audio;

  bool get isAll =>
      categoryId == null &&
      !uncategorized &&
      tagPath == null &&
      !untagged &&
      content == null;

  @override
  bool operator ==(Object other) =>
      other is DiaryFilter &&
      other.categoryId == categoryId &&
      other.uncategorized == uncategorized &&
      other.tagPath == tagPath &&
      other.untagged == untagged &&
      other.content == content;

  @override
  int get hashCode =>
      Object.hash(categoryId, uncategorized, tagPath, untagged, content);

  @override
  String toString() => isAll
      ? 'DiaryFilter.all()'
      : content != null
      ? 'DiaryFilter.${content!.name}()'
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
