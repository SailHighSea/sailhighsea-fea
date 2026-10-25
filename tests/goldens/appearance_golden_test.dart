import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

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
    });
  }
}
