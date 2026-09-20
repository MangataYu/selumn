import 'dart:convert';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
import 'package:mui/mui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryKVStorage storage;
  late ThemeManager theme;

  setUp(() async {
    await getIt.reset();
    storage = MemoryKVStorage();
    getIt.registerSingleton<IKVStorage>(storage);
    theme = ThemeManager();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DynamicColorPlugin.channel, null);
    await getIt.reset();
  });

  test('持久化模式索引不变，新默认模式追加在末尾', () {
    expect(ThemeAccentMode.neutral.index, 0);
    expect(ThemeAccentMode.system.index, 1);
    expect(ThemeAccentMode.custom.index, 2);
    expect(ThemeAccentMode.preset.index, 3);
  });

  test('未保存强调色时使用 lemonade / dim，且不写入用户偏好', () {
    expect(MoodiaryKVs.themeAccentMode.get(), ThemeAccentMode.preset.index);
    expect(
      MoodiaryKVs.themeAccentMode.getNotifier().value,
      ThemeAccentMode.preset.index,
    );
    expect(theme.lightTheme.colorScheme.surface, const Color(0xFFF8FDEF));
    expect(theme.lightTheme.colorScheme.primary, const Color(0xFF056300));
    expect(theme.darkTheme.colorScheme.surface, const Color(0xFF2A303C));
    expect(theme.darkTheme.colorScheme.primary, const Color(0xFF9FE88D));
    expect(MoodiaryKVs.themeAccentColor.getNotifier().value, 0xFF4F794A);
    expect(storage.data, isEmpty);
  });

  test('已有其他偏好但未选择主题的用户也使用默认主题对', () {
    MoodiaryKVs.firstStart.set(false);
    MoodiaryKVs.language.set('en');

    expect(theme.lightTheme.colorScheme, presetColorScheme(.light));
    expect(theme.darkTheme.colorScheme, presetColorScheme(.dark));
    expect(storage.data.containsKey(MoodiaryKVs.themeAccentMode.name), isFalse);
    expect(
      storage.data.containsKey(MoodiaryKVs.themeAccentColor.name),
      isFalse,
    );
  });

  for (final index in [-1, 99]) {
    test('无效模式 $index 回退默认主题且保留存储值', () {
      MoodiaryKVs.themeAccentMode.set(index);
      expect(theme.lightTheme.colorScheme, presetColorScheme(.light));
      expect(theme.darkTheme.colorScheme, presetColorScheme(.dark));
      expect(MoodiaryKVs.themeAccentMode.get(), index);
    });
  }

  for (final mode in ThemeAccentMode.values) {
    test('保留已保存的 $mode 模式与颜色', () async {
      MoodiaryKVs.themeAccentMode.set(mode.index);
      MoodiaryKVs.themeAccentColor.set(0xFF2E59A7);
      final before = (theme.lightTheme, theme.darkTheme);

      await theme.buildTheme();

      expect(MoodiaryKVs.themeAccentMode.get(), mode.index);
      expect(MoodiaryKVs.themeAccentColor.get(), 0xFF2E59A7);
      expect((theme.lightTheme, theme.darkTheme), before);
      for (final brightness in Brightness.values) {
        final scheme = brightness == .light
            ? theme.lightTheme.colorScheme
            : theme.darkTheme.colorScheme;
        expect(
          scheme,
          mode == .preset
              ? presetColorScheme(brightness)
              : resolveColorScheme(
                  brightness,
                  mode == .custom
                      ? const MuiAccent.seeded(Color(0xFF2E59A7))
                      : const MuiAccent.neutral(),
                ),
        );
      }
    });
  }

  test('已保存的系统强调色仍使用系统种子生成主题', () async {
    MoodiaryKVs.themeAccentMode.set(ThemeAccentMode.system.index);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          DynamicColorPlugin.channel,
          (call) async =>
              call.method == DynamicColorPlugin.accentColorMethodName
              ? 0xFF2E59A7
              : null,
        );

    await theme.buildTheme();

    expect(theme.resolveAccent().seed, const Color(0xFF2E59A7));
    expect(
      theme.darkTheme.colorScheme,
      resolveColorScheme(.dark, const MuiAccent.seeded(Color(0xFF2E59A7))),
    );
  });

  test('浏览器预览fixture与实际编辑器主题桥接完全一致', () {
    final fixture = jsonDecode(
      File('test/fixtures/default_editor_themes.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final brightness in Brightness.values) {
      expect(theme.editorRoles(brightness), fixture[brightness.name]);
    }
  });

  test('正文、填充按钮和状态文字在两种默认主题中保持可读', () {
    for (final brightness in Brightness.values) {
      final scheme = presetColorScheme(brightness);
      for (final pair in [
        (scheme.surface, scheme.onSurface),
        (scheme.surface, scheme.onSurfaceVariant),
        (scheme.primary, scheme.onPrimary),
        (scheme.secondary, scheme.onSecondary),
        (scheme.tertiary, scheme.onTertiary),
        (scheme.primaryContainer, scheme.onPrimaryContainer),
        (scheme.secondaryContainer, scheme.onSecondaryContainer),
        (scheme.tertiaryContainer, scheme.onTertiaryContainer),
        (scheme.errorContainer, scheme.onErrorContainer),
        (scheme.surface, scheme.error),
        (scheme.surface, presetSuccessColor(brightness)),
        for (final background in [
          scheme.surface,
          scheme.surfaceContainer,
          scheme.surfaceContainerHighest,
        ])
          for (final foreground in [
            scheme.primary,
            scheme.secondary,
            scheme.tertiary,
          ])
            (background, foreground),
      ]) {
        final a = pair.$1.computeLuminance();
        final b = pair.$2.computeLuminance();
        final contrast = a > b
            ? (a + 0.05) / (b + 0.05)
            : (b + 0.05) / (a + 0.05);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason: '$brightness: $pair',
        );
      }
    }
  });

  test('分享卡片导出继续使用无彩主题', () {
    for (final brightness in Brightness.values) {
      expect(
        theme.exportTheme(brightness).colorScheme,
        resolveColorScheme(brightness, const MuiAccent.neutral()),
      );
    }
  });

  testWidgets('跟随系统自动切换默认主题，手动模式不受系统变化影响', (tester) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    late ColorScheme current;
    Future<void> show(ThemeMode mode) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.lightTheme,
          darkTheme: theme.darkTheme,
          themeMode: mode,
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (context) {
              current = Theme.of(context).colorScheme;
              return const SizedBox();
            },
          ),
        ),
      );
    }

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await show(ThemeMode.system);
    expect(current, presetColorScheme(.light));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(current, presetColorScheme(.dark));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(current, presetColorScheme(.light));

    await show(ThemeMode.dark);
    expect(current, presetColorScheme(.dark));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(current, presetColorScheme(.dark));

    await show(ThemeMode.light);
    expect(current, presetColorScheme(.light));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(current, presetColorScheme(.light));
  });
}
