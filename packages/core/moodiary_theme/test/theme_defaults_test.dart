import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
import 'package:mui/mui.dart';

class _ThemeWithoutSystemColor extends ThemeManager {
  @override
  Future<void> findDynamicColor() async {}
}

void main() {
  late MemoryKVStorage storage;
  late ThemeManager theme;

  setUp(() async {
    await getIt.reset();
    storage = MemoryKVStorage();
    getIt.registerSingleton<IKVStorage>(storage);
    theme = ThemeManager();
  });

  tearDown(() => getIt.reset());

  test('未保存强调色时使用 Selume 绿色，且不写入用户偏好', () {
    expect(MoodiaryKVs.themeAccentMode.get(), ThemeAccentMode.custom.index);
    expect(theme.resolveAccent().seed, const Color(0xFF4F794A));
    expect(
      MoodiaryKVs.themeAccentMode.getNotifier().value,
      ThemeAccentMode.custom.index,
    );
    expect(MoodiaryKVs.themeAccentColor.getNotifier().value, 0xFF4F794A);
    expect(storage.data, isEmpty);
  });

  test('已有其他偏好但未选择主题的用户也使用绿色', () {
    MoodiaryKVs.firstStart.set(false);
    MoodiaryKVs.language.set('en');

    expect(theme.resolveAccent().seed, const Color(0xFF4F794A));
    expect(storage.data.containsKey(MoodiaryKVs.themeAccentMode.name), isFalse);
    expect(
      storage.data.containsKey(MoodiaryKVs.themeAccentColor.name),
      isFalse,
    );
  });

  test('旧字体偏好不会影响应用主题，也不会被删除', () async {
    MoodiaryKVs.customFont.set('Previously imported font');
    final manager = _ThemeWithoutSystemColor();

    await manager.buildTheme();

    final expected = buildMuiTheme(
      brightness: Brightness.light,
      accent: manager.resolveAccent(),
    );
    expect(
      manager.lightTheme.textTheme.bodyMedium,
      expected.textTheme.bodyMedium,
    );
    expect(MoodiaryKVs.customFont.get(), 'Previously imported font');
  });

  for (final mode in ThemeAccentMode.values) {
    test('保留已保存的 $mode 模式与颜色', () {
      MoodiaryKVs.themeAccentMode.set(mode.index);
      MoodiaryKVs.themeAccentColor.set(0xFF2E59A7);

      final accent = theme.resolveAccent();

      expect(MoodiaryKVs.themeAccentMode.get(), mode.index);
      expect(MoodiaryKVs.themeAccentColor.get(), 0xFF2E59A7);
      if (mode == ThemeAccentMode.custom) {
        expect(accent.seed, const Color(0xFF2E59A7));
      } else {
        // 无系统种子时，系统档仍按既有逻辑回退无彩档。
        expect(accent.isNeutral, isTrue);
      }
    });
  }
}
