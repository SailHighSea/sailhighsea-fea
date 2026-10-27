import 'package:flutter/material.dart';

import 'appearance_settings.dart';
import 'color_themes.dart';

/// The two colours of the Home header gradient for a colour theme. Dark and Pure black use deeper
/// versions so white text keeps its contrast.
(Color, Color) headerGradientFor(ColorThemeId theme, ThemeVariant variant) {
  final (a, b) = switch (theme) {
    ColorThemeId.forest => (const Color(0xFF1B6FA8), const Color(0xFF1E9577)),
    ColorThemeId.ocean => (const Color(0xFF1B6FA8), const Color(0xFF3B4CCA)),
    ColorThemeId.sunset => (const Color(0xFFD9692E), const Color(0xFFB8432F)),
    ColorThemeId.graphite => (const Color(0xFF2F3A43), const Color(0xFF3A6E8F)),
    ColorThemeId.lavender => (const Color(0xFF6B4FBB), const Color(0xFFC2335F)),
    ColorThemeId.rose => (const Color(0xFFC2335F), const Color(0xFF8A2A6E)),
    ColorThemeId.lagoon => (const Color(0xFF0E7C86), const Color(0xFF1E9577)),
    ColorThemeId.indigo => (const Color(0xFF3B4CCA), const Color(0xFF6B4FBB)),
    ColorThemeId.mocha => (const Color(0xFF8A5A3B), const Color(0xFFB07A2E)),
    ColorThemeId.citrus => (const Color(0xFF5C7F0B), const Color(0xFF2E8B57)),
  };
  if (variant == ThemeVariant.light) return (a, b);
  final k = variant == ThemeVariant.pure ? 0.55 : 0.35;
  return (Color.lerp(a, Colors.black, k)!, Color.lerp(b, Colors.black, k)!);
}
