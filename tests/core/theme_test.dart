// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:math' as math;

import 'package:family_expenses/core/theme/app_theme.dart';
import 'package:family_expenses/core/theme/appearance_provider.dart';
import 'package:family_expenses/core/theme/appearance_settings.dart';
import 'package:family_expenses/core/theme/color_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('Forest tokens match docs/SPEC.md section 2', () {
    test('Light', () {
      final t = tokensFor(ColorThemeId.forest, ThemeVariant.light);
      expect(t.background, const Color(0xFFF4F6F5));
      expect(t.surface, const Color(0xFFFFFFFF));
      expect(t.border, const Color(0xFFE3E8E5));
      expect(t.text, const Color(0xFF0F1F1A));
      expect(t.muted, const Color(0xFF55645D));
      expect(t.primary, const Color(0xFF0B6E4F));
      expect(t.hero, const Color(0xFF0B3D2E));
      expect(t.heroTrack, const Color(0xFF1F5A47));
      expect(t.heroMuted, const Color(0xFFBFD8CC));
      expect(t.neutralBar, const Color(0xFFB9D9CB));
      expect(t.navRail, const Color(0xFFFFFFFF));
      expect(t.sidebar, const Color(0xFF0B3D2E));
      expect(t.navActiveBackground, const Color(0xFFDCEFE6));
      expect(t.navActiveText, const Color(0xFF0B3D2E));
    });

    test('Dark', () {
      final t = tokensFor(ColorThemeId.forest, ThemeVariant.dark);
      expect(t.background, const Color(0xFF0E1512));
      expect(t.surface, const Color(0xFF17211C));
      expect(t.border, const Color(0xFF26332C));
      expect(t.text, const Color(0xFFE8F0EC));
      expect(t.muted, const Color(0xFF9DB0A6));
      expect(t.primary, const Color(0xFF4CC38A));
      expect(t.hero, const Color(0xFF123F31));
      expect(t.heroTrack, const Color(0xFF2A6150));
      expect(t.neutralBar, const Color(0xFF2F5B4A));
      expect(t.sidebar, const Color(0xFF123F31));
      expect(t.navActiveBackground, const Color(0xFF1F3A30));
    });

    test('Pure black', () {
      final t = tokensFor(ColorThemeId.forest, ThemeVariant.pure);
      expect(t.background, const Color(0xFF000000));
      expect(t.surface, const Color(0xFF0A0F0D));
      expect(t.border, const Color(0xFF1F2B26));
      expect(t.text, const Color(0xFFF2F7F4));
      expect(t.primary, const Color(0xFF4CC38A));
      expect(t.hero, const Color(0xFF0B2E23));
      expect(t.heroBorder, const Color(0xFF14463A));
      expect(t.neutralBar, const Color(0xFF2A5646));
      expect(t.navRail, const Color(0xFF000000));
      expect(t.sidebar, const Color(0xFF000000));
      expect(t.navActiveBackground, const Color(0xFF0F2A21));
    });

    test('shared colours', () {
      final t = tokensFor(ColorThemeId.forest, ThemeVariant.light);
      expect(t.amber, const Color(0xFFF2B84B));
      expect(t.amberBar, const Color(0xFFE0A020));
      expect(t.blue, const Color(0xFF6FB3D9));
      expect(t.purple, const Color(0xFF8A7FB8));
      expect(t.grey, const Color(0xFF9AA8A1));
    });
  });

  group('every colour theme has Light, Dark and Pure black variants', () {
    for (final theme in ColorThemeId.values) {
      for (final variant in ThemeVariant.values) {
        test('${theme.name} ${variant.name} is readable', () {
          final t = tokensFor(theme, variant);
          expect(
            contrast(t.text, t.background),
            greaterThan(7),
            reason: 'body text on page',
          );
          expect(
            contrast(t.text, t.surface),
            greaterThan(7),
            reason: 'body text on cards',
          );
          expect(
            contrast(t.muted, t.surface),
            greaterThan(4.5),
            reason: 'muted text on cards',
          );
          expect(
            contrast(t.onPrimary, t.primary),
            greaterThan(4.5),
            reason: 'button label',
          );
          expect(
            contrast(t.heroText, t.hero),
            greaterThan(7),
            reason: 'hero text',
          );
          expect(
            contrast(t.heroMuted, t.hero),
            greaterThan(4.5),
            reason: 'hero muted text',
          );
          expect(
            contrast(t.amberText, t.surface),
            greaterThan(4.5),
            reason: 'bill amount text',
          );
        });
      }
    }

    test('themes tint the page and cards too, not only the accent', () {
      for (final v in [ThemeVariant.dark, ThemeVariant.pure]) {
        final forest = tokensFor(ColorThemeId.forest, v);
        final rose = tokensFor(ColorThemeId.rose, v);
        expect(forest.hero, isNot(rose.hero));
        expect(forest.surface, isNot(rose.surface), reason: '$v');
        expect(forest.border, isNot(rose.border), reason: '$v');
      }
      // Dark: the card is the theme's hue (rose is red-leaning), not forest's green-grey.
      final dark = tokensFor(ColorThemeId.rose, ThemeVariant.dark);
      expect(dark.surface.r, greaterThan(dark.surface.g));
      final forest = tokensFor(ColorThemeId.forest, ThemeVariant.dark);
      expect(forest.surface.g, greaterThan(forest.surface.r));
      // Pure black stays black.
      expect(
        tokensFor(ColorThemeId.rose, ThemeVariant.pure).background,
        const Color(0xFF000000),
      );
    });
  });

  group('colour-blind charts', () {
    test('use a different palette that is still distinct per category', () {
      final normal = tokensFor(ColorThemeId.forest, ThemeVariant.light);
      final safe = tokensFor(
        ColorThemeId.forest,
        ThemeVariant.light,
        colorBlind: true,
      );
      expect(safe.categoryColor('food'), isNot(normal.categoryColor('food')));
      final colours = {
        for (final k in [
          'food',
          'bills',
          'transport',
          'fun',
          'health',
          'other',
        ])
          safe.categoryColor(k),
      };
      expect(colours.length, 6);
    });

    test('unknown category keys fall back to grey', () {
      final t = tokensFor(ColorThemeId.forest, ThemeVariant.light);
      expect(t.categoryColor('nonsense'), t.grey);
    });
  });

  test('Pure black selects the pure variant for the dark slot', () {
    expect(darkVariantFor(AppearanceMode.pureBlack), ThemeVariant.pure);
    expect(darkVariantFor(AppearanceMode.dark), ThemeVariant.dark);
    expect(darkVariantFor(AppearanceMode.system), ThemeVariant.dark);
    expect(themeModeFor(AppearanceMode.system), ThemeMode.system);
    expect(themeModeFor(AppearanceMode.light), ThemeMode.light);
    expect(themeModeFor(AppearanceMode.pureBlack), ThemeMode.dark);
  });

  group('appearance persistence', () {
    Future<ProviderContainer> containerWith(Map<String, Object> initial) async {
      SharedPreferences.setMockInitialValues(initial);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('defaults', () async {
      final c = await containerWith({});
      expect(c.read(appearanceProvider), const AppearanceSettings());
      expect(c.read(appearanceProvider).currencyCode, 'SGD');
    });

    test('choices are saved and restored by a new container', () async {
      final c = await containerWith({});
      final controller = c.read(appearanceProvider.notifier);
      await controller.setMode(AppearanceMode.pureBlack);
      await controller.setColorTheme(ColorThemeId.sunset);
      await controller.setLargerText(true);
      await controller.setColorBlindCharts(true);
      await controller.setCurrency('EUR');

      final prefs = await SharedPreferences.getInstance();
      final restored = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(restored.dispose);
      final s = restored.read(appearanceProvider);
      expect(s.mode, AppearanceMode.pureBlack);
      expect(s.colorTheme, ColorThemeId.sunset);
      expect(s.largerText, isTrue);
      expect(s.colorBlindCharts, isTrue);
      expect(s.currencyCode, 'EUR');
    });

    test('unknown stored values fall back to defaults', () async {
      final c = await containerWith({
        'appearance.mode': 'sepia',
        'appearance.colorTheme': 'neon',
      });
      expect(c.read(appearanceProvider).mode, AppearanceMode.system);
      expect(c.read(appearanceProvider).colorTheme, ColorThemeId.forest);
    });
  });
}
