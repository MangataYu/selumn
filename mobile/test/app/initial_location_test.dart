import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_mobile/app/di/bootstrap.dart';
import 'package:moodiary_mobile/main.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

void main() {
  setUp(() {
    MmkvKVStorage.legacyMigrationPending = false;
    getIt.pushNewScope(
      init: (gi) {
        gi.registerSingleton<IKVStorage>(MemoryKVStorage());
        gi.registerSingleton<ISecureKVStorage>(MemorySecureKVStorage());
      },
    );
    AppLockPin.hasher = (pin) async => r'$argon2-fake';
  });

  tearDown(() async {
    MmkvKVStorage.legacyMigrationPending = false;
    await AppLockPin.clear();
    await getIt.popScope();
  });

  test('设了应用锁：首帧落在锁屏', () async {
    await AppLockPin.set('1234');
    expect(resolveInitialLocation(), LockRoute.path);
  });

  test('首次启动也直接进主界面（引导页已下架，首启不再有拦截）', () {
    expect(resolveInitialLocation(), DiaryHomeRoute.path);
  });

  group('使用天数起始时间', () {
    for (final invalid in <int?>[null, 0, -1]) {
      test('缺失或无效起始时间 $invalid 会在启动时补齐', () {
        if (invalid != null) MoodiaryKVs.startTime.set(invalid);
        final before = DateTime.now().millisecondsSinceEpoch;

        initializeUsageStartTime();

        final after = DateTime.now().millisecondsSinceEpoch;
        expect(MoodiaryKVs.startTime.get(), inInclusiveRange(before, after));
      });
    }

    test('已有起始时间会保留，不随重复启动重置', () {
      final original = DateTime(2024, 5, 10).millisecondsSinceEpoch;
      MoodiaryKVs.startTime.set(original);

      initializeUsageStartTime();
      initializeUsageStartTime();

      expect(MoodiaryKVs.startTime.get(), original);
    });

    test('补齐的起始时间在重复启动时保留', () {
      initializeUsageStartTime();
      final original = MoodiaryKVs.startTime.get();

      initializeUsageStartTime();

      expect(MoodiaryKVs.startTime.get(), original);
    });

    test('旧 KV 迁移待处理时不写入，迁移完成后保留旧时间', () {
      MmkvKVStorage.legacyMigrationPending = true;

      initializeUsageStartTime();

      expect(MoodiaryKVs.startTime.get(), isNull);

      final migrated = DateTime(2023, 2, 15).millisecondsSinceEpoch;
      MoodiaryKVs.startTime.set(migrated);
      MmkvKVStorage.legacyMigrationPending = false;
      initializeUsageStartTime();

      expect(MoodiaryKVs.startTime.get(), migrated);
    });
  });
}
