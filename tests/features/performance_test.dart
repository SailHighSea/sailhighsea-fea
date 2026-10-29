import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/theme/appearance_provider.dart';
import 'package:family_expenses/core/widgets/glass.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

Future<void> _many(AppDatabase db) async {
  final repo = ExpenseRepository(db, clock: () => DateTime.utc(2026, 10, 20));
  for (var i = 0; i < 130; i++) {
    await repo.add(
      amountCents: 100 + i,
      categoryId: 'default-food',
      spentOn: DateTime(2026, 10, 1 + i % 20),
      note: 'Shop $i',
      createdBy: 'You',
    );
  }
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('a long month is drawn in steps of 60, with a button for more', (
    tester,
  ) async {
    await pumpApp(
      tester,
      size: const Size(390, 844),
      location: '/expenses',
      seedAsync: _many,
    );
    await settle(tester);
    // Only the first page of rows exists; the count line still says 130.
    expect(find.textContaining('130 expenses'), findsOneWidget);
    expect(find.byType(Dismissible), findsNWidgets(60));
    expect(find.byKey(const ValueKey('show-more')), findsOneWidget);
    expect(find.text('Show 60 more (70 left)'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('show-more')));
    await tapKey(tester, 'show-more');
    expect(find.byType(Dismissible), findsNWidgets(120));
    expect(find.text('Show 10 more (10 left)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('show-more')));
    await tapKey(tester, 'show-more');
    expect(find.byType(Dismissible), findsNWidgets(130));
    expect(find.byKey(const ValueKey('show-more')), findsNothing);
  });

  testWidgets('a short list has no "show more"', (tester) async {
    await pumpApp(
      tester,
      size: const Size(390, 844),
      location: '/expenses',
      seedAsync: (db) async {
        final repo = ExpenseRepository(
          db,
          clock: () => DateTime.utc(2026, 10, 20),
        );
        await repo.add(
          amountCents: 500,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 20),
          note: 'One',
          createdBy: 'You',
        );
      },
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('show-more')), findsNothing);
  });

  group('light effects', () {
    testWidgets('are off by default, switch on in Appearance and persist', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 900),
        location: '/appearance',
      );
      expect(c.read(appearanceProvider).lightEffects, isFalse);
      final row = find.text('Light effects (smoother on older devices)');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(c.read(appearanceProvider).lightEffects, isTrue);
      expect(
        c.read(sharedPreferencesProvider).getBool('appearance.lightEffects'),
        isTrue,
      );
    });

    testWidgets('turn the glass blur and soft shadows off', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'appearance.look': 'glass'},
      );
      expect(find.byType(BackdropFilter), findsWidgets);
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'appearance.look': 'glass', 'appearance.lightEffects': true},
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        GlassScope.lightOf(tester.element(find.byType(Scaffold).first)),
        isTrue,
      );
    });
  });
}
