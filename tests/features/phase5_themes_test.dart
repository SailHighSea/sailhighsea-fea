import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/phase5_data.dart';
import '../helpers/test_app.dart';

/// Rule 3: a screen looks the same in every theme; only colours change. Each Phase 5 screen
/// is built in Light, Dark and Pure black and the visible text and the shape of the widget
/// tree (sizes of every box) must be identical.
void main() {
  setUpAll(loadTestFonts);

  const sizes = {
    'phone': Size(390, 844),
    'tablet': Size(1024, 720),
    'desktop': Size(1280, 800),
  };
  const modes = ['light', 'dark', 'pureBlack'];
  const routes = ['budgets', 'insights', 'goals', 'bills'];

  /// Every visible string and the size and position of every Text, in tree order.
  String signature(WidgetTester tester) {
    final out = StringBuffer();
    for (final element in find.byType(Text).evaluate()) {
      final text =
          (element.widget as Text).data ??
          (element.widget as Text).textSpan?.toPlainText() ??
          '';
      final box = element.renderObject as RenderBox;
      final pos = box.localToGlobal(Offset.zero);
      out.writeln(
        '$text @${pos.dx.round()},${pos.dy.round()} ${box.size.width.round()}x${box.size.height.round()}',
      );
    }
    return out.toString();
  }

  for (final route in routes) {
    for (final size in sizes.entries) {
      testWidgets('$route is the same in every theme at ${size.key} width', (
        tester,
      ) async {
        final seen = <String, String>{};
        for (final mode in modes) {
          await pumpApp(
            tester,
            size: size.value,
            location: '/$route',
            seedAsync: seedPhase5,
            prefs: {'appearance.mode': mode},
          );
          seen[mode] = signature(tester);
          expect(tester.takeException(), isNull, reason: '$route $mode');
          // Fresh app for the next theme.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        }
        expect(
          seen['dark'],
          seen['light'],
          reason: '$route: Dark differs from Light',
        );
        expect(
          seen['pureBlack'],
          seen['light'],
          reason: '$route: Pure black differs from Light',
        );
        expect(seen['light'], isNotEmpty);
      });
    }
  }

  testWidgets(
    'the colour-blind chart option changes colours but not the layout',
    (tester) async {
      final seen = <bool, String>{};
      for (final colorBlind in [false, true]) {
        await pumpApp(
          tester,
          size: sizes['desktop']!,
          location: '/insights',
          seedAsync: seedPhase5,
          prefs: {'appearance.colorBlindCharts': colorBlind},
        );
        seen[colorBlind] = signature(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
      expect(seen[true], seen[false]);
    },
  );
}
