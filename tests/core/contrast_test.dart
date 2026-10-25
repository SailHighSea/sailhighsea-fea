import 'dart:math' as math;

import 'package:family_expenses/core/theme/appearance_settings.dart';
import 'package:family_expenses/core/theme/color_themes.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double ratio(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  final hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // WCAG AA: 4.5:1 for text under 18pt. Every text colour used on its real background, in every
  // colour theme and every mode.
  for (final theme in ColorThemeId.values) {
    for (final variant in ThemeVariant.values) {
      final t = tokensFor(theme, variant);
      final name = '${theme.name}/${variant.name}';
      void check(String what, Color fg, Color bg, [double min = 4.5]) {
        test('$name: $what', () {
          final r = ratio(fg, bg);
          expect(
            r,
            greaterThanOrEqualTo(min),
            reason: '${r.toStringAsFixed(2)}:1',
          );
        });
      }

      check('text on background', t.text, t.background);
      check('text on surface', t.text, t.surface);
      check('muted on background', t.muted, t.background);
      check('muted on surface', t.muted, t.surface);
      check('button text on primary', t.onPrimary, t.primary);
      check('hero text on hero', t.heroText, t.hero);
      check('hero muted on hero', t.heroMuted, t.hero);
      check(
        'active nav text on its pill',
        t.navActiveText,
        t.navActiveBackground,
      );
      check('primary links on surface', t.primary, t.surface, 3.0);
    }
  }
}
