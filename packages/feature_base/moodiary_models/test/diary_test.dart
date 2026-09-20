import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_models/moodiary_models.dart';

void main() {
  test('Diary.empty defaults mood to neutral', () {
    final d = Diary.empty(type: .tiptap);
    expect(d.mood, DiaryMood.neutral);
  });

  test('DiaryMood JSON round-trips by name and falls back to neutral', () {
    final d = Diary.empty(type: .tiptap).copyWith(mood: .positive);
    final json = d.toJson();
    expect(json['mood'], 'positive');
    expect(Diary.fromJson(json).mood, DiaryMood.positive);
    expect(DiaryMood.fromName('nope'), DiaryMood.neutral);
  });

  test(
    'pending category tag exclusions survive JSON and default for old payloads',
    () {
      final diary = Diary.empty(type: .tiptap).copyWith(
        categoryId: 'legacy',
        legacyCategoryExcludedTags: ['工作', '生活/运动'],
      );
      final json = diary.toJson();
      expect(json['legacyCategoryExcludedTags'], ['工作', '生活/运动']);
      expect(Diary.fromJson(json), diary);
      json.remove('legacyCategoryExcludedTags');
      expect(Diary.fromJson(json).legacyCategoryExcludedTags, isEmpty);
      expect(Diary.fromJson(json).categoryId, 'legacy');
    },
  );
}
