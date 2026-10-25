import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// Home in Light, Dark and Pure black at phone (390), tablet (1024) and desktop (1280)
/// widths. Compare against design/screenshots: Main, Tablet, Desktop, HomeDark,
/// TabHomeDark, DeskHomeDark, HomePure, TabHomePure, DeskHomePure.
void main() {
  setUpAll(loadTestFonts);

  const sizes = {
    'phone': Size(390, 844),
    'tablet': Size(1024, 720),
    'desktop': Size(1280, 800),
  };
  const modes = {'light': 'light', 'dark': 'dark', 'pure': 'pureBlack'};

  for (final mode in modes.entries) {
    for (final size in sizes.entries) {
      testWidgets('Home ${mode.key} ${size.key}', (tester) async {
        await pumpApp(
          tester,
          size: size.value,
          sampleHome: true,
          prefs: {'appearance.mode': mode.value},
        );
        await expectLater(
          find.byType(WidgetsApp),
          matchesGoldenFile('home_${mode.key}_${size.key}.png'),
        );
      });
    }
  }
}
