import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/phase5_data.dart';
import '../helpers/test_app.dart';

/// Pixel goldens for Budgets, Insights, Goals and Bills in Light, Dark and Pure black at
/// phone, tablet and desktop widths (compare with design/screenshots).
///
/// The golden images are made on Windows (like the Home goldens: text is drawn differently on
/// each OS), so these run only when `PHASE5_GOLDENS=1` is set:
///   create or refresh:  PHASE5_GOLDENS=1 flutter test --update-goldens tests/goldens/phase5_golden_test.dart
///   check:              PHASE5_GOLDENS=1 flutter test tests/goldens/phase5_golden_test.dart
/// The structural test in tests/features/phase5_themes_test.dart runs everywhere.
void main() {
  final enabled = Platform.environment['PHASE5_GOLDENS'] == '1';
  setUpAll(loadTestFonts);

  const sizes = {
    'phone': Size(390, 844),
    'tablet': Size(1024, 720),
    'desktop': Size(1280, 800),
  };
  const modes = {'light': 'light', 'dark': 'dark', 'pure': 'pureBlack'};
  const routes = ['budgets', 'insights', 'goals', 'bills'];

  for (final route in routes) {
    for (final mode in modes.entries) {
      for (final size in sizes.entries) {
        testWidgets(
          '${route[0].toUpperCase()}${route.substring(1)} ${mode.key} ${size.key}',
          (tester) async {
            await pumpApp(
              tester,
              size: size.value,
              location: '/$route',
              seedAsync: seedPhase5,
              prefs: {'appearance.mode': mode.value},
            );
            await tester.pump(const Duration(milliseconds: 300));
            await expectLater(
              find.byType(WidgetsApp),
              matchesGoldenFile('${route}_${mode.key}_${size.key}.png'),
            );
          },
          // The images are made on Windows; see the note at the top of the file.
          skip: !enabled,
        );
      }
    }
  }
}
