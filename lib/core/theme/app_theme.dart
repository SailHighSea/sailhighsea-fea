import 'package:flutter/material.dart';

import 'appearance_settings.dart';
import 'color_themes.dart';

const appFontFamily = 'DM Sans';

/// Radii from docs/SPEC.md section 2.
abstract final class AppRadii {
  static const double card = 24;
  static const double smallCard = 20;
  static const double button = 999;
}

/// Minimum tap target (rule 8).
const double kMinTapTarget = 44;

/// [transparentScaffold] lets a personal background picture or gradient show through the screens.
ThemeData buildTheme(
  AppearanceSettings settings,
  ThemeVariant variant, {
  bool transparentScaffold = false,
}) {
  final tokens = tokensFor(
    settings.colorTheme,
    variant,
    colorBlind: settings.colorBlindCharts,
  );
  final brightness = variant == ThemeVariant.light
      ? Brightness.light
      : Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: tokens.primary,
    onPrimary: tokens.onPrimary,
    secondary: tokens.ringAccent,
    onSecondary: tokens.text,
    error: tokens.rose,
    onError: tokens.onPrimary,
    surface: tokens.surface,
    onSurface: tokens.text,
    outline: tokens.border,
    surfaceContainerHighest: tokens.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    scaffoldBackgroundColor: transparentScaffold
        ? const Color(0x00000000)
        : tokens.background,
    canvasColor: tokens.background,
    dividerColor: tokens.border,
    splashFactory: InkRipple.splashFactory,
    // Visible keyboard focus and mouse hover on every tappable surface (desktop polish).
    focusColor: tokens.primary.withValues(alpha: 0.22),
    hoverColor: tokens.primary.withValues(alpha: 0.08),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [tokens],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: appFontFamily,
      bodyColor: tokens.text,
      displayColor: tokens.text,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? tokens.primary
            : tokens.toggleOff,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Color(0x00000000)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surface,
      surfaceTintColor: const Color(0x00000000),
      textStyle: TextStyle(
        color: tokens.text,
        fontFamily: appFontFamily,
        fontSize: 15,
      ),
    ),
  );
}

ThemeMode themeModeFor(AppearanceMode mode) => switch (mode) {
  AppearanceMode.system => ThemeMode.system,
  AppearanceMode.light => ThemeMode.light,
  AppearanceMode.dark || AppearanceMode.pureBlack => ThemeMode.dark,
};

/// The dark slot is Pure black when that mode is chosen, otherwise regular Dark.
ThemeVariant darkVariantFor(AppearanceMode mode) =>
    mode == AppearanceMode.pureBlack ? ThemeVariant.pure : ThemeVariant.dark;
