import 'package:material_ui/material_ui.dart';

/// Selume's default pair, adapted from daisyUI 5.7.28 lemonade / dim.
///
/// The source OKLCH colors are converted to 8-bit sRGB (out-of-gamut channels
/// clipped). Lemonade container/fixed roles retain the daisyUI color pairs.
/// Dim uses a muted green secondary palette so selected navigation, settings
/// and chips share the primary hue instead of daisyUI's orange secondary.
/// In lemonade, foreground primary/secondary/tertiary reduce OKLCH lightness
/// to 43%/44%/44% at the source chroma/hue, giving at least 4.5:1 contrast even
/// on base-300; their filled-button labels use base-100. Muted text and outlines
/// blend base-content over base-100. Error and
/// success are foregrounds in Mui, so light mode uses the readable content
/// color while retaining the original pastel error as its container.
ColorScheme presetColorScheme(Brightness brightness) =>
    brightness == .light ? _lemonade : _dim;

Color presetSuccessColor(Brightness brightness) =>
    brightness == .light ? const Color(0xFF0D110E) : const Color(0xFF62EFBD);

const _lemonade = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF056300),
  onPrimary: Color(0xFFF8FDEF),
  primaryContainer: Color(0xFF419400),
  onPrimaryContainer: Color(0xFF010800),
  primaryFixed: Color(0xFF419400),
  primaryFixedDim: Color(0xFF419400),
  onPrimaryFixed: Color(0xFF010800),
  onPrimaryFixedVariant: Color(0xFF010800),
  secondary: Color(0xFF5B5700),
  onSecondary: Color(0xFFF8FDEF),
  secondaryContainer: Color(0xFFBDC000),
  onSecondaryContainer: Color(0xFF0D0E00),
  secondaryFixed: Color(0xFFBDC000),
  secondaryFixedDim: Color(0xFFBDC000),
  onSecondaryFixed: Color(0xFF0D0E00),
  onSecondaryFixedVariant: Color(0xFF0D0E00),
  tertiary: Color(0xFF6D4F00),
  onTertiary: Color(0xFFF8FDEF),
  tertiaryContainer: Color(0xFFEDD000),
  onTertiaryContainer: Color(0xFF141000),
  tertiaryFixed: Color(0xFFEDD000),
  tertiaryFixedDim: Color(0xFFEDD000),
  onTertiaryFixed: Color(0xFF141000),
  onTertiaryFixedVariant: Color(0xFF141000),
  error: Color(0xFF140E0E),
  onError: Color(0xFFEFC6C2),
  errorContainer: Color(0xFFEFC6C2),
  onErrorContainer: Color(0xFF140E0E),
  surface: Color(0xFFF8FDEF),
  onSurface: Color(0xFF151614),
  surfaceDim: Color(0xFFCBCFC3),
  surfaceBright: Color(0xFFF8FDEF),
  surfaceContainerLowest: Color(0xFFF8FDEF),
  surfaceContainerLow: Color(0xFFE1E6D9),
  surfaceContainer: Color(0xFFE1E6D9),
  surfaceContainerHigh: Color(0xFFCBCFC3),
  surfaceContainerHighest: Color(0xFFCBCFC3),
  onSurfaceVariant: Color(0xFF4E504B),
  outline: Color(0xFF878A82),
  outlineVariant: Color(0xFFCBCFC3),
  inverseSurface: Color(0xFF343300),
  onInverseSurface: Color(0xFFD2D3C7),
  inversePrimary: Color(0xFF9FE88D),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFF056300),
);

const _dim = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF9FE88D),
  onPrimary: Color(0xFF091307),
  primaryContainer: Color(0xFF9FE88D),
  onPrimaryContainer: Color(0xFF091307),
  primaryFixed: Color(0xFF9FE88D),
  primaryFixedDim: Color(0xFF9FE88D),
  onPrimaryFixed: Color(0xFF091307),
  onPrimaryFixedVariant: Color(0xFF091307),
  secondary: Color(0xFFB7CCB0),
  onSecondary: Color(0xFF20331D),
  secondaryContainer: Color(0xFF334A2E),
  onSecondaryContainer: Color(0xFFD2E8C9),
  secondaryFixed: Color(0xFFD2E8C9),
  secondaryFixedDim: Color(0xFFB7CCB0),
  onSecondaryFixed: Color(0xFF20331D),
  onSecondaryFixedVariant: Color(0xFF334A2E),
  tertiary: Color(0xFFC792E9),
  onTertiary: Color(0xFF0E0813),
  tertiaryContainer: Color(0xFFC792E9),
  onTertiaryContainer: Color(0xFF0E0813),
  tertiaryFixed: Color(0xFFC792E9),
  tertiaryFixedDim: Color(0xFFC792E9),
  onTertiaryFixed: Color(0xFF0E0813),
  onTertiaryFixedVariant: Color(0xFF0E0813),
  error: Color(0xFFFFAE9B),
  onError: Color(0xFF160B09),
  errorContainer: Color(0xFF160B09),
  onErrorContainer: Color(0xFFFFAE9B),
  surface: Color(0xFF2A303C),
  onSurface: Color(0xFFB2CCD6),
  surfaceDim: Color(0xFF20252E),
  surfaceBright: Color(0xFF2A303C),
  surfaceContainerLowest: Color(0xFF1C212B),
  surfaceContainerLow: Color(0xFF242933),
  surfaceContainer: Color(0xFF242933),
  surfaceContainerHigh: Color(0xFF20252E),
  surfaceContainerHighest: Color(0xFF20252E),
  onSurfaceVariant: Color(0xFF90A5B0),
  outline: Color(0xFF6E7E89),
  outlineVariant: Color(0xFF454F5B),
  inverseSurface: Color(0xFF1C212B),
  onInverseSurface: Color(0xFFB2CCD6),
  inversePrimary: Color(0xFF419400),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Color(0xFF9FE88D),
);
