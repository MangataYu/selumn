import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_utils/moodiary_utils.dart';

Future<List<String>> loadTagCandidates(String query) async {
  final tags = await getIt<DiaryRepository>().getAllTags();
  final ordered = orderedTagPaths(tags, MoodiaryKVs.tagOrder.get()!);
  final q = query.toLowerCase();
  return ordered
      .where((tag) => tag.toLowerCase().contains(q))
      .take(20)
      .toList();
}
