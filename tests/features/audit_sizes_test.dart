import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/phase5_data.dart';
import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

/// Phase 6 audit: every screen at 360, 600, 840, 1024, 1280 and 1920 wide. No overflow, no
/// exception, every tap target at least 44, and every tap target has a spoken label.
const _sizes = <String, Size>{
  '360': Size(360, 740),
  '600': Size(600, 900),
  '840': Size(840, 900),
  '1024': Size(1024, 720),
  '1280': Size(1280, 800),
  '1920': Size(1920, 1080),
};

const _routes = [
  '/home',
  '/budgets',
  '/insights',
  '/goals',
  '/bills',
  '/appearance',
  '/expenses',
  '/add',
];

void main() {
  setUpAll(loadTestFonts);

  for (final route in _routes) {
    for (final size in _sizes.entries) {
      testWidgets('$route at ${size.key}', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpApp(
          tester,
          size: size.value,
          location: route,
          seedAsync: seedPhase5,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'no overflow or error');
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      });
    }
  }

  for (final route in ['/family', '/home', '/insights']) {
    for (final size in _sizes.entries) {
      testWidgets('signed in $route at ${size.key}', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpAsMember(
          tester,
          me: ownerUser,
          location: route,
          size: size.value,
        );
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantics.dispose();
      });
    }
  }
}
