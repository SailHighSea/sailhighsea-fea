import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/time.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/expenses/expense_list_providers.dart';
import 'package:family_expenses/features/overview/domain/overview_calculations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

Future<void> _seed(AppDatabase db) async {
  final repo = ExpenseRepository(db, clock: () => DateTime.utc(2026, 10, 20));
  for (final e in [
    (4820, DateTime(2026, 10, 20), 'Groceries'),
    (1200, DateTime(2026, 10, 12), 'Lunch'),
    (900, DateTime(2026, 10, 5), 'Bus'),
  ]) {
    await repo.add(
      amountCents: e.$1,
      categoryId: 'default-food',
      spentOn: e.$2,
      note: e.$3,
      createdBy: 'You',
    );
  }
}

void main() {
  setUpAll(loadTestFonts);
  swipeMonthTests();

  group('Settings tab', () {
    testWidgets('the phone has four tabs, and Settings lists the extras', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(390, 844));
      for (final label in ['Home', 'Budgets', 'Insights', 'Settings']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(
        find.byTooltip('Menu: family, goals, bills, appearance'),
        findsNothing,
      );
      await tester.tap(find.text('Settings').first);
      await settle(tester);
      for (final k in [
        'settings-family',
        'settings-goals',
        'settings-bills',
        'settings-appearance',
        'settings-data',
        'settings-import',
      ]) {
        expect(key(k), findsOneWidget, reason: k);
      }
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('an item opens its page', (tester) async {
      await pumpApp(tester, size: const Size(390, 844), location: '/settings');
      await tapKey(tester, 'settings-goals');
      expect(find.text('Savings goals'), findsWidgets);
    });

    testWidgets('fits at large text', (tester) async {
      await pumpApp(
        tester,
        size: const Size(360, 800),
        textScale: 2,
        location: '/settings',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Expenses header', () {
    for (final size in const {
      'phone': Size(360, 800),
      'phone small, large text': Size(320, 640),
    }.entries) {
      testWidgets('Select and Add do not overlap on ${size.key}', (
        tester,
      ) async {
        await pumpApp(
          tester,
          size: size.value,
          textScale: size.key.contains('large') ? 1.6 : 1,
          location: '/expenses',
          seedAsync: _seed,
        );
        final select = tester.getRect(key('select-start'));
        final add = tester.getRect(find.text('+ Add'));
        expect(select.overlaps(add), isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('category chips wrap instead of being cut off', (tester) async {
      await pumpApp(
        tester,
        size: const Size(320, 640),
        location: '/expenses',
        seedAsync: _seed,
      );
      expect(find.byType(Wrap), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Select similar', () {
    testWidgets('the row menu selects every expense from the same shop', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/expenses',
        seedAsync: (db) async {
          final repo = ExpenseRepository(
            db,
            clock: () => DateTime.utc(2026, 10, 20),
          );
          for (final n in [
            'LULU HYPERMARKET 12',
            'lulu hypermarket 99',
            'Bus',
          ]) {
            await repo.add(
              amountCents: 1000,
              categoryId: 'default-food',
              spentOn: DateTime(2026, 10, 20),
              note: n,
              createdBy: 'You',
            );
          }
        },
      );
      expect(c, isNotNull);
      await tester.tap(find.byTooltip('More actions for Bus'));
      await settle(tester);
      expect(find.text('Select similar'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await settle(tester);
      await tester.tap(find.byTooltip('More actions for LULU HYPERMARKET 12'));
      await settle(tester);
      await tester.tap(find.text('Select similar'));
      await settle(tester);
      expect(find.text('2 selected'), findsOneWidget);
    });
  });

  group('Date range', () {
    testWidgets('a range lists only those days, and Clear goes back', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/expenses',
        seedAsync: _seed,
      );
      expect(find.text('Choose a date range'), findsOneWidget);
      expect(find.text('Bus'), findsOneWidget);
      c
          .read(expenseRangeProvider.notifier)
          .set(
            DateTimeRange(
              start: DateTime(2026, 10, 10),
              end: DateTime(2026, 10, 21),
            ),
          );
      await settle(tester);
      expect(key('range-bar'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Bus'), findsNothing);
      await tapKey(tester, 'range-clear');
      expect(key('range-bar'), findsNothing);
      expect(find.text('Bus'), findsOneWidget);
    });
  });

  group('Who spent it', () {
    final cats = defaultCategoryRows();
    test('splits each category by person and sorts by size', () {
      final out = buildCategoriesByPerson(
        month: DateTime(2026, 10),
        currentUserId: 'me',
        categories: cats,
        expenses: [
          expenseRow(spentOn: '2026-10-02', cents: 3000, createdBy: 'me'),
          expenseRow(spentOn: '2026-10-03', cents: 1000, createdBy: 'maya'),
          expenseRow(spentOn: '2026-10-04', cents: 500, createdBy: 'You'),
          expenseRow(
            spentOn: '2026-10-04',
            cents: 9000,
            category: 'default-fun',
            createdBy: 'maya',
          ),
          expenseRow(spentOn: '2026-09-30', cents: 7777, createdBy: 'me'),
          expenseRow(
            spentOn: '2026-10-05',
            cents: 4242,
            createdBy: 'me',
            deletedAt: DateTime(2026, 10, 6),
          ),
        ],
      );
      expect(out.map((c) => c.totalCents), [9000, 4500]);
      expect(out[1].byPerson, {'me': 3500, 'maya': 1000});
      expect(out[0].byPerson, {'maya': 9000});
    });

    testWidgets('the organiser sees the card on Home with everyone listed', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: const Size(390, 844),
      );
      await tester.scrollUntilVisible(
        key('category-by-person'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Who spent it'), findsOneWidget);
      expect(find.text('Maya'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('someone who sees only their own spending has no card', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        ownOnly: {viewerUser},
        location: '/home',
        size: const Size(390, 844),
      );
      expect(key('category-by-person'), findsNothing);
    });

    testWidgets('a solo person has no card', (tester) async {
      await pumpApp(tester, size: const Size(390, 844));
      expect(key('category-by-person'), findsNothing);
    });
  });
}

void swipeMonthTests() {
  group('Swipe the Home card to change month', () {
    testWidgets('left goes to the next month, right to the previous', (
      tester,
    ) async {
      final c = await pumpApp(tester, size: const Size(390, 844));
      final start = c.read(selectedMonthProvider);
      await tester.fling(key('hero-swipe'), const Offset(-300, 0), 1200);
      await settle(tester);
      expect(
        c.read(selectedMonthProvider),
        DateTime(start.year, start.month + 1),
      );
      await tester.fling(key('hero-swipe'), const Offset(300, 0), 1200);
      await tester.fling(key('hero-swipe'), const Offset(300, 0), 1200);
      await settle(tester);
      expect(
        c.read(selectedMonthProvider),
        DateTime(start.year, start.month - 1),
      );
    });
  });
}
