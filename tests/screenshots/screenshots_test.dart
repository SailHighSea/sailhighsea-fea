// Makes the pictures used in README.md. Not part of the normal test run:
//   SCREENSHOTS=1 flutter test tests/screenshots
// The pictures are written to docs/screenshots (or SCREENSHOT_DIR).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/features/goals/data/savings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/phase5_data.dart';
import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

final _on = Platform.environment['SCREENSHOTS'] == '1';
final _dir = Platform.environment['SCREENSHOT_DIR'] ?? 'docs/screenshots';
final _now = DateTime(2026, 10, 23, 12);

Future<void> _snap(WidgetTester tester, String name) async {
  await settle(tester);
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    Directory(_dir).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> _seedAll(AppDatabase db) async {
  await seedPhase5(db, now: _now);
  final savings = SavingsRepository(db, clock: () => _now);
  await savings.setIncome(DateTime(2026, 1), 420000);
  await savings.setTotal(1430000);
}

void main() {
  setUpAll(loadTestFonts);

  void shot(
    String name,
    Size size, {
    String location = '/home',
    Map<String, Object> prefs = const {},
    bool sampleHome = false,
    bool member = false,
    double scroll = 0,
  }) {
    testWidgets(name, (tester) async {
      if (member) {
        await pumpAsMember(
          tester,
          me: ownerUser,
          location: location,
          size: size,
          mode: prefs['appearance.mode'] as String? ?? 'light',
        );
      } else {
        await pumpApp(
          tester,
          size: size,
          location: location,
          prefs: prefs,
          sampleHome: sampleHome,
          seedAsync: _seedAll,
        );
      }
      if (scroll > 0) {
        await tester.drag(find.byType(Scrollable).first, Offset(0, -scroll));
        await settle(tester);
      }
      await _snap(tester, name);
    }, skip: !_on);
  }

  const phone = Size(390, 844);
  shot('home-light', phone, sampleHome: true);
  shot(
    'home-dark',
    phone,
    sampleHome: true,
    prefs: {'appearance.mode': 'dark'},
  );
  shot(
    'home-glass',
    phone,
    sampleHome: true,
    prefs: {'appearance.look': 'glass'},
  );
  shot(
    'home-glass-dark',
    phone,
    sampleHome: true,
    prefs: {'appearance.look': 'glass', 'appearance.mode': 'dark'},
  );
  shot(
    'home-rose',
    phone,
    sampleHome: true,
    prefs: {'appearance.mode': 'light', 'appearance.colorTheme': 'rose'},
  );
  shot('home-who-spent-it', phone, member: true, scroll: 1150);
  shot('expenses', phone, location: '/expenses');
  shot('budgets', phone, location: '/budgets');
  shot('insights', phone, location: '/insights');
  shot('goals-and-savings', phone, location: '/goals');
  shot('categories', phone, location: '/categories');
  shot('appearance', const Size(1024, 900), location: '/appearance');
  shot('home-tablet', const Size(1024, 720), sampleHome: true);
  shot('home-desktop', const Size(1280, 800), sampleHome: true);
}
