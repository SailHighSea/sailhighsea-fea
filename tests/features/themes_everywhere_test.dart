import 'dart:convert';

import 'package:family_expenses/core/theme/personal_look.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// The new themes, backgrounds and header must hold up on every screen at every size.
void main() {
  setUpAll(loadTestFonts);

  final look = jsonEncode({
    'page': const BackgroundStyle(
      kind: BackgroundKind.picture,
      picturePath: 'asset:assets/backgrounds/sunset.png',
      pictureLuminance: 0.334,
    ).toJson(),
    'card': const BackgroundStyle(
      kind: BackgroundKind.gradient,
      gradient: 3,
    ).toJson(),
  });

  const routes = [
    '/home',
    '/expenses',
    '/budgets',
    '/goals',
    '/insights',
    '/bills',
    '/family',
    '/categories',
    '/appearance',
    '/personalise',
    '/data',
    '/about',
    '/settings',
  ];
  const sizes = {
    'phone': Size(390, 844),
    'phone small': Size(320, 640),
    'tablet': Size(840, 900),
    'laptop': Size(1024, 720),
    'desktop': Size(1280, 800),
  };

  for (final size in sizes.entries) {
    for (final route in routes) {
      testWidgets(
        '$route on ${size.key} with a rose theme, picture and gradient header',
        (tester) async {
          await pumpApp(
            tester,
            size: size.value,
            location: route,
            prefs: {
              'appearance.colorTheme': 'rose',
              'appearance.homeHeader': 'gradient',
              'personal.look': look,
            },
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final theme in const [
    'lavender',
    'lagoon',
    'indigo',
    'mocha',
    'citrus',
    'sunset',
    'graphite',
    'ocean',
  ]) {
    for (final mode in ['light', 'dark', 'pureBlack']) {
      testWidgets('Home and Budgets in $theme, $mode', (tester) async {
        await pumpApp(
          tester,
          size: const Size(390, 844),
          prefs: {'appearance.colorTheme': theme, 'appearance.mode': mode},
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
