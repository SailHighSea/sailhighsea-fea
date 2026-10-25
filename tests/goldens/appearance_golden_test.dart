import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// The Appearance page gained a "Privacy and data" card in Phase 7, so the old images no longer
/// match. They must be recreated on Windows (text is drawn differently on each OS), so these run
/// only when `APPEARANCE_GOLDENS=1` is set:
///   refresh:  APPEARANCE_GOLDENS=1 flutter test --update-goldens tests/goldens/appearance_golden_test.dart
///   check:    APPEARANCE_GOLDENS=1 flutter test tests/goldens/appearance_golden_test.dart
///
/// Appearance at phone, tablet and desktop widths. Compare with design/screenshots:
/// Themes, TabAppearance, DeskAppearance.
void main() {
  setUpAll(loadTestFonts);

  const sizes = {
    'phone': Size(390, 844),
    'tablet': Size(1024, 720),
    'desktop': Size(1280, 800),
  };

  for (final size in sizes.entries) {
    testWidgets('Appearance ${size.key}', (tester) async {
      await pumpApp(tester, size: size.value, location: '/appearance');
      await expectLater(
        find.byType(WidgetsApp),
        matchesGoldenFile('appearance_${size.key}.png'),
      );
    }, skip: Platform.environment['APPEARANCE_GOLDENS'] != '1');
  }
}
