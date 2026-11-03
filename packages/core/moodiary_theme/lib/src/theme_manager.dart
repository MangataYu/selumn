import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';
import 'package:moodiary_logging/moodiary_logging.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_theme/moodiary_theme.dart';
import 'package:mui/mui.dart';

@lazySingleton
class ThemeManager {
  ThemeManager();

  ThemeData? _lightTheme;

  ThemeData? _darkTheme;

  Color? _systemSeed;

  ThemeData get lightTheme =>
      _lightTheme ?? buildMuiTheme(brightness: Brightness.light);

  ThemeData get darkTheme =>
      _darkTheme ?? buildMuiTheme(brightness: Brightness.dark);

  Color? get systemAccentSeed => _systemSeed;

  bool get supportDynamic => _systemSeed != null;

  Future<void> buildTheme() async {
    await findDynamicColor();
    final accent = resolveAccent();

    _lightTheme = buildMuiTheme(brightness: Brightness.light, accent: accent);
    _darkTheme = buildMuiTheme(brightness: Brightness.dark, accent: accent);
  }

  ThemeData exportTheme(Brightness brightness) =>
      buildMuiTheme(brightness: brightness);

  MuiAccent resolveAccent() {
    final index = MoodiaryKVs.themeAccentMode.get()!;
    final mode = index >= 0 && index < ThemeAccentMode.values.length
        ? ThemeAccentMode.values[index]
        : ThemeAccentMode.neutral;
    return switch (mode) {
      .neutral => const MuiAccent.neutral(),
      .system => switch (_systemSeed) {
        final seed? => MuiAccent.seeded(seed),
        _ => const MuiAccent.neutral(),
      },
      .custom => MuiAccent.seeded(Color(MoodiaryKVs.themeAccentColor.get()!)),
    };
  }

  Map<String, String> editorRoles(Brightness brightness) {
    final scheme = brightness == .light
        ? lightTheme.colorScheme
        : darkTheme.colorScheme;
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return {
      'surface': hex(scheme.surface),
      'onSurface': hex(scheme.onSurface),
      'onSurfaceVariant': hex(scheme.onSurfaceVariant),
      'surfaceContainerLow': hex(scheme.surfaceContainerLow),
      'surfaceContainer': hex(scheme.surfaceContainer),
      'surfaceContainerHigh': hex(scheme.surfaceContainerHigh),
      'surfaceContainerHighest': hex(scheme.surfaceContainerHighest),
      'primary': hex(scheme.primary),
      'onPrimary': hex(scheme.onPrimary),
      'secondaryContainer': hex(scheme.secondaryContainer),
      'onSecondaryContainer': hex(scheme.onSecondaryContainer),
      'inverseSurface': hex(scheme.inverseSurface),
      'onInverseSurface': hex(scheme.onInverseSurface),
      'outlineVariant': hex(scheme.outlineVariant),
      'error': hex(scheme.error),
    };
  }

  Future<void> findDynamicColor() async {
    try {
      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (corePalette != null) {
        _systemSeed = Color(corePalette.primary.get(40));
        return;
      }
    } on PlatformException {
      logger.d('dynamic_color: Failed to obtain core palette.');
    }

    try {
      final accentColor = await DynamicColorPlugin.getAccentColor();
      if (accentColor != null) {
        _systemSeed = accentColor;
        return;
      }
    } on PlatformException {
      logger.d('dynamic_color: Failed to obtain accent color.');
    }

    logger.d('dynamic_color: Dynamic color not detected on this device.');
  }

  (ThemeData, ThemeData) getThemeData() => (lightTheme, darkTheme);
}

extension ColorExt on Color {
  Brightness get brightness {
    final double relativeLuminance = computeLuminance();

    const double kThreshold = 0.15;
    if ((relativeLuminance + 0.05) * (relativeLuminance + 0.05) > kThreshold) {
      return .light;
    }
    return .dark;
  }
}
