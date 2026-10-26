import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/home/home_calculations.dart';
import 'package:family_expenses/features/home/home_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

/// October 2026 up to the 23rd, September up to the 23rd (and one big expense on the 28th that must
/// not count against "the same time last month").
Future<void> _seed(AppDatabase db) async {
  final repo = ExpenseRepository(db, clock: () => DateTime.utc(2026, 10, 23));
  Future<void> add(String cat, int cents, DateTime day) =>
      repo.add(amountCents: cents, categoryId: cat, spentOn: day, note: 'x');
  await add('default-food', 84200, DateTime(2026, 10, 5));
  await add('default-bills', 52000, DateTime(2026, 10, 1));
  await add('default-transport', 31000, DateTime(2026, 10, 12));
  await add('default-fun', 18600, DateTime(2026, 10, 20));
  // September
  await add('default-food', 79000, DateTime(2026, 9, 6));
  await add('default-bills', 52000, DateTime(2026, 9, 1));
  await add('default-transport', 24100, DateTime(2026, 9, 14));
  await add('default-fun', 23200, DateTime(2026, 9, 21));
  await add('default-health', 6000, DateTime(2026, 9, 9));
  await add('default-food', 999900, DateTime(2026, 9, 28));
}

void main() {
  setUpAll(loadTestFonts);

  group('the comparison numbers', () {
    List<CategoryRow> cats = const [];
    ExpenseRow row(String cat, int cents, String day) => ExpenseRow(
      id: '$cat$day$cents',
      householdId: 'local',
      amountCents: cents,
      categoryId: cat,
      note: '',
      spentOn: day,
      createdBy: null,
      receiptPath: null,
      updatedAt: DateTime(2026, 10, 1),
      deletedAt: null,
      dirty: false,
    );
    CategoryRow category(String id, String name, String color) => CategoryRow(
      id: id,
      householdId: 'local',
      name: name,
      color: color,
      icon: null,
      sort: 0,
      updatedAt: DateTime(2026, 1, 1),
      deletedAt: null,
      dirty: false,
    );

    setUp(() {
      cats = [
        category('default-food', 'Food', 'food'),
        category('default-fun', 'Fun', 'fun'),
        category('default-other', 'Other', 'other'),
      ];
    });

    HomeSummary build(List<ExpenseRow> now, List<ExpenseRow> before) =>
        buildHomeSummary(
          month: DateTime(2026, 10),
          now: DateTime(2026, 10, 23),
          budgetCents: 250000,
          expenses: now,
          categories: cats,
          previousExpenses: before,
        );

    test('last month counts only up to the same day, and the change is whole percent', () {
      final s = build(
        [row('default-food', 10900, '2026-10-05')],
        [
          row('default-food', 10000, '2026-09-05'),
          row('default-food', 90000, '2026-09-28'),
        ],
      );
      final food = s.comparison.single;
      expect(food.previousCents, 10000, reason: 'the 28th is after the 23rd');
      expect(food.changePercent, 9);
    });

    test('rounding is exact in both directions, with integer maths', () {
      int? p(int now, int before) => CategoryCompare(
        name: 'x',
        colorKey: 'x',
        cents: now,
        previousCents: before,
      ).changePercent;
      expect(p(10900, 10000), 9);
      expect(p(7600, 10000), -24);
      expect(p(10050, 10000), 1, reason: '0.5% rounds up');
      expect(p(9950, 10000), -1, reason: '-0.5% rounds away from zero');
      expect(p(10000, 10000), 0);
      expect(p(500, 0), isNull, reason: 'nothing last month: no percentage');
    });

    test(
      'a category only in one month still shows, largest this month first',
      () {
        final s = build(
          [
            row('default-fun', 5000, '2026-10-02'),
            row('default-food', 9000, '2026-10-03'),
          ],
          [row('default-other', 3000, '2026-09-02')],
        );
        expect(s.comparison.map((c) => c.name), ['Food', 'Fun', 'Other']);
        expect(s.comparison.last.cents, 0);
        expect(s.comparison.last.previousCents, 3000);
      },
    );

    test('a past month is compared up to its own last day; a short month is not overrun', () {
      final s = buildHomeSummary(
        month: DateTime(2026, 3),
        now: DateTime(2026, 10, 23),
        budgetCents: 0,
        expenses: [row('default-food', 1000, '2026-03-31')],
        categories: cats,
        previousExpenses: [row('default-food', 500, '2026-02-28')],
      );
      expect(
        s.comparison.single.previousCents,
        500,
        reason: 'February has 28 days, the cutoff is its last day',
      );
    });

    test(
      'no expenses at all: nothing to compare',
      () => expect(build(const [], const []).comparison, isEmpty),
    );
  });

  group('on Home', () {
    for (final size in const {
      'phone': Size(390, 844),
      'phone small': Size(360, 740),
      'tablet': Size(840, 900),
      'laptop': Size(1024, 720),
      'desktop': Size(1280, 800),
      'wide': Size(1920, 1080),
    }.entries) {
      testWidgets('${size.key}: both cards are there with real numbers', (
        tester,
      ) async {
        await pumpApp(tester, size: size.value, seedAsync: _seed);
        await settle(tester);
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Compared with last month'), findsOneWidget);
        expect(find.text('By category'), findsOneWidget);
        // Food 842 against 790 last month: +7%. Fun 186 against 232: -20%. Transport +29%. Bills same.
        expect(find.text('+7%'), findsOneWidget);
        expect(find.text('−20%'), findsOneWidget);
        expect(find.text('+29%'), findsOneWidget);
        expect(find.text('same'), findsOneWidget);
        expect(find.text('Same time last month'), findsOneWidget);
        // Health is only in September: a row with no spending and a tick; it has no tile.
        expect(find.text('Health'), findsOneWidget);
        expect(find.text('S\$842'), findsWidgets);
      });
    }

    testWidgets(
      'the big expense on 28 September does not change the comparison',
      (tester) async {
        await pumpApp(tester, size: const Size(1280, 800), seedAsync: _seed);
        await settle(tester);
        expect(
          find.text('+7%'),
          findsOneWidget,
          reason: 'it would read -92% if the 28th counted',
        );
      },
    );

    testWidgets(
      'with no spending the cards say so instead of showing empty bars',
      (tester) async {
        await pumpApp(tester, size: const Size(390, 844));
        await settle(tester);
        expect(find.text('No spending to compare yet'), findsOneWidget);
        expect(find.text('No categories to show yet'), findsOneWidget);
      },
    );

    testWidgets('the cards look the same in Light, Dark and Pure black', (
      tester,
    ) async {
      final texts = <String, List<String>>{};
      for (final mode in const ['light', 'dark', 'pureBlack']) {
        await pumpApp(
          tester,
          size: const Size(390, 844),
          seedAsync: _seed,
          prefs: {'appearance.mode': mode},
        );
        await settle(tester);
        texts[mode] = [
          for (final t in tester.widgetList<Text>(find.byType(Text)))
            t.data ?? '',
        ];
      }
      expect(texts['dark'], texts['light']);
      expect(texts['pureBlack'], texts['light']);
    });

    testWidgets('large text and tap targets', (tester) async {
      await pumpApp(
        tester,
        size: const Size(360, 740),
        seedAsync: _seed,
        textScale: 2,
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
