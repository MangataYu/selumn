import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

class _EmptyDiaries extends Fake implements DiaryRepository {
  @override
  Stream<DiaryEvent> get diaryEvents => const Stream.empty();

  @override
  Future<List<Diary>> getAllDiaries() async => [];
}

class _EmptyCategories extends Fake implements CategoryRepository {
  @override
  Stream<CategoryEvent> get categoryEvents => const Stream.empty();

  @override
  Future<List<Category>> getAllCategories() async => [];
}

void main() {
  group('使用天数按本地自然日计算，包含首日', () {
    test('同一天始终为 1', () {
      expect(
        dashboardUseDays(
          startTime: DateTime(2026, 9, 23, 8).millisecondsSinceEpoch,
          now: DateTime(2026, 9, 23, 23, 59),
        ),
        1,
      );
    });

    test('跨过午夜即增加，无需满 24 小时', () {
      expect(
        dashboardUseDays(
          startTime: DateTime(2026, 9, 23, 23, 59).millisecondsSinceEpoch,
          now: DateTime(2026, 9, 24, 0, 1),
        ),
        2,
      );
    });

    test('跨年和闰日正确累计', () {
      for (final (first, now, expected) in [
        (DateTime(2025, 12, 31, 23), DateTime(2026, 1, 2), 3),
        (DateTime(2024, 2, 28, 23), DateTime(2024, 3, 1), 3),
      ]) {
        expect(
          dashboardUseDays(startTime: first.millisecondsSinceEpoch, now: now),
          expected,
        );
      }
    });

    test('UTC 时刻也按设备的本地日期计算', () {
      expect(
        dashboardUseDays(
          startTime: DateTime(2026, 9, 23, 23, 59).millisecondsSinceEpoch,
          now: DateTime(2026, 9, 24, 0, 1).toUtc(),
        ),
        2,
      );
    });

    test('缺失、无效或未来的起始时间不会显示负数或异常大值', () {
      for (final first in [
        null,
        0,
        -1,
        DateTime(2026, 9, 25).millisecondsSinceEpoch,
      ]) {
        expect(
          dashboardUseDays(startTime: first, now: DateTime(2026, 9, 24)),
          1,
        );
      }
    });
  });

  test('统计读取持久化起始时间，重新加载也不会重置', () async {
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(MemoryKVStorage());
        gi.registerSingleton<DiaryRepository>(_EmptyDiaries());
        gi.registerSingleton<CategoryRepository>(_EmptyCategories());
      },
    );
    addTearDown(getIt.popScope);
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day - 3);
    MoodiaryKVs.startTime.set(first.millisecondsSinceEpoch);
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    final subscription = container.listen(
      dashboardControllerProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    expect(
      (await container.read(dashboardControllerProvider.future)).useDays,
      4,
    );
    container.invalidate(dashboardControllerProvider);
    expect(
      (await container.read(dashboardControllerProvider.future)).useDays,
      4,
    );
    expect(MoodiaryKVs.startTime.get(), first.millisecondsSinceEpoch);
  });
}
