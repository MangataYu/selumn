import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

import 'diary_filter.dart';
import 'diary_selection.dart';
import 'tag_order.dart';

final tagManagementProvider = Provider(TagManagementController.new);

class TagManagementController {
  final Ref _ref;
  late final _repository = getIt<DiaryRepository>();
  late final _storage = getIt<IKVStorage>();

  TagManagementController(this._ref);

  List<String> get savedOrder =>
      _storage.get<List<String>>(MoodiaryKVs.tagOrder.name) ?? const [];

  List<String> get _expandedPaths =>
      _storage.get<List<String>>(MoodiaryKVs.expandedTagPaths.name) ?? const [];

  void saveOrder(List<String> order, List<String> fallbackTags) {
    if (!_ref.mounted) return;
    final tags = _ref.read(diaryTagsProvider).value ?? fallbackTags;
    _storage.set(MoodiaryKVs.tagOrder.name, orderedTagPaths(tags, order));
  }

  Future<void> rename(String tag, String replacement) async {
    final storage = _storage;
    await _repository.renameTag(tag, replacement);
    // Finish the saved metadata even if the initiating page has been closed.
    try {
      storage.set(
        MoodiaryKVs.tagOrder.name,
        renameTagOrder(savedOrder, tag, replacement),
      );
      storage.set(
        MoodiaryKVs.expandedTagPaths.name,
        {
          for (final path in _expandedPaths)
            TagPath.replacePrefix(path, tag, replacement),
        }.toList()..sort(),
      );
    } finally {
      _updateSelection(tag, replacement);
    }
  }

  Future<void> delete(String tag) async {
    final storage = _storage;
    await _repository.deleteTag(tag);
    try {
      storage.set(MoodiaryKVs.tagOrder.name, deleteTagOrder(savedOrder, tag));
      storage.set(
        MoodiaryKVs.expandedTagPaths.name,
        [
          for (final path in _expandedPaths)
            if (!TagPath.matches(path, tag)) path,
        ]..sort(),
      );
    } finally {
      _updateSelection(tag, null);
    }
  }

  void _updateSelection(String tag, String? replacement) {
    if (!_ref.mounted) return;
    final selected = _ref.read(homeDiaryFilterProvider).tagPath;
    if (selected == null || !TagPath.matches(selected, tag)) return;
    final filter = _ref.read(homeDiaryFilterProvider.notifier);
    if (replacement == null) {
      filter.reset();
    } else {
      filter.select(.tag(TagPath.replacePrefix(selected, tag, replacement)));
    }
    _ref.read(diarySelectionProvider.notifier).clear();
  }
}
