import 'dart:async';

import 'package:moodiary_di/moodiary_di.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'diary_repository.dart';

part 'tag_controller.g.dart';

void _watchTags(Ref ref, DiaryRepository repository) {
  Timer? debounce;
  final subscription = repository.diaryEvents.listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 200), ref.invalidateSelf);
  });
  ref.onDispose(() {
    debounce?.cancel();
    subscription.cancel();
  });
}

@riverpod
Future<List<String>> diaryTags(Ref ref) {
  final repository = getIt<DiaryRepository>();
  _watchTags(ref, repository);
  return repository.getAllTags();
}

@riverpod
Future<({Map<String, int> byTag, int total, int untagged})> tagDiaryCounts(
  Ref ref,
) {
  final repository = getIt<DiaryRepository>();
  _watchTags(ref, repository);
  return repository.diaryCountByTag();
}
