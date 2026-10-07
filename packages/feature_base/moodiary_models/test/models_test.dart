import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_models/moodiary_models.dart';

void main() {
  test('Category holds an optional color', () {
    final c = Category.create(categoryName: 'work', color: 0xFF42A5F5);
    expect(c.color, 0xFF42A5F5);
  });

  test('Category color defaults to null when unset', () {
    final c = Category.create(categoryName: 'life');
    expect(c.color, isNull);
  });

  test('DiaryMood JSON round-trips by name and falls back to neutral', () {
    for (final mood in DiaryMood.values) {
      final d = Diary.empty(type: .tiptap).copyWith(mood: mood);
      final json = d.toJson();
      expect(json['mood'], mood.name);
      expect(Diary.fromJson(json).mood, mood);
      expect(DiaryMood.fromName(mood.name), mood);
    }
    expect(DiaryMood.fromName('nope'), DiaryMood.neutral);
    final unknownMoodJson = Diary.empty(type: .tiptap).toJson()
      ..['mood'] = 'futureMood';
    expect(Diary.fromJson(unknownMoodJson).mood, DiaryMood.neutral);
  });

  test(
    'DiaryMood selections contain only the twenty moods without duplicates',
    () {
      expect(DiaryMood.selectableValues, const <DiaryMood>[
        .positive,
        .neutral,
        .negative,
        .fulfilled,
        .angry,
        .anxious,
        .tired,
        .speechless,
        .love,
        .relaxed,
        .grateful,
        .lonely,
        .excited,
        .expectant,
        .proud,
        .relieved,
        .hurt,
        .disappointed,
        .irritated,
        .confused,
      ]);
      expect(
        DiaryMood.selectableValues.toSet(),
        hasLength(DiaryMood.selectableValues.length),
      );
      expect(
        DiaryMood.values.where((mood) => mood.isSelectable),
        DiaryMood.selectableValues,
      );
    },
  );

  test('Legacy activities remain readable without being selectable', () {
    const legacyNames = [
      'study',
      'slacking',
      'food',
      'work',
      'travel',
      'sports',
      'sick',
      'celebrating',
      'focused',
      'meeting',
      'overtime',
      'commuting',
      'sleep',
      'coffee',
      'home',
      'shopping',
      'cooking',
      'gaming',
      'music',
      'movie',
    ];
    for (final name in legacyNames) {
      final mood = DiaryMood.fromName(name);
      expect(mood.name, name);
      expect(mood.isSelectable, isFalse);
      final json = Diary.empty(type: .tiptap).toJson()..['mood'] = name;
      final restored = Diary.fromJson(json);
      expect(restored.mood, mood);
      expect(restored.toJson()['mood'], name);
    }
  });

  group('DiaryWeather 展示串', () {
    test('有温度：完整形式带度数，紧凑形式只留度数', () {
      const w = DiaryWeather(icon: '100', temp: '26', text: '晴');
      expect(w.displayText, '晴 26°');
      expect(w.compactText, '26°');
    });

    test('手选天气没有温度：两种形式都退回描述，不留裸的度数符号', () {
      const w = DiaryWeather(icon: '305', text: '小雨');
      expect(w.displayText, '小雨');
      expect(w.compactText, '小雨');
    });

    test('空串与 null 同等对待（旧库迁移可能留下空串）', () {
      const w = DiaryWeather(icon: '104', temp: '', text: '阴');
      expect(w.displayText, '阴');
      expect(w.compactText, '阴');
    });

    test('JSON 往返：temp 缺席即 null', () {
      const w = DiaryWeather(icon: '400', text: '小雪');
      expect(DiaryWeather.fromJson(w.toJson()), w);
      expect(DiaryWeather.fromJson({'icon': '400', 'text': '小雪'}).temp, isNull);
    });
  });

  group('ManualWeather', () {
    test('fromCode 认得自己的码，不在候选里的返回 null', () {
      expect(
        ManualWeather.values.map((w) => w.code).toSet(),
        hasLength(ManualWeather.values.length),
      );
      expect(ManualWeather.fromCode('305'), ManualWeather.lightRain);
      expect(ManualWeather.fromCode('313'), isNull);
      expect(ManualWeather.fromCode(''), isNull);
    });
  });

  group('AssistantProviderType.fromId', () {
    test('所有协议值都认得，包括订阅登录', () {
      for (final t in AssistantProviderType.values) {
        expect(AssistantProviderType.fromId(t.id), t);
      }
    });

    test('认不出来时回落到兼容面最广的 chat completions', () {
      expect(
        AssistantProviderType.fromId(null),
        AssistantProviderType.openaiCompletions,
      );
      expect(
        AssistantProviderType.fromId('gemini'),
        AssistantProviderType.openaiCompletions,
      );
    });

    test('isAnthropic 只对 messages 协议为真', () {
      expect(AssistantProviderType.anthropicMessages.isAnthropic, isTrue);
      expect(AssistantProviderType.openaiCompletions.isAnthropic, isFalse);
      expect(AssistantProviderType.openaiResponses.isAnthropic, isFalse);
    });
  });
}
