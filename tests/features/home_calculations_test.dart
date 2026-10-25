import 'package:family_expenses/features/home/home_calculations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

void main() {
  final categories = defaultCategoryRows();
  final oct = DateTime(2026, 10);
  final now = DateTime(2026, 10, 23, 14);
  const budget = 250000;

  test('month total, today, week and safe per day for the current month', () {
    final expenses = [
      expenseRow(spentOn: '2026-10-05', cents: 100000),
      expenseRow(spentOn: '2026-10-20', cents: 50000),
      expenseRow(spentOn: '2026-10-22', cents: 20000),
      expenseRow(spentOn: '2026-10-23', cents: 14200),
    ];
    final s = buildHomeSummary(
      month: oct,
      now: now,
      budgetCents: budget,
      expenses: expenses,
      categories: categories,
    );
    expect(s.spentCents, 184200);
    expect(s.budgetCents, 250000);
    expect(s.remainingCents, 65800);
    expect(s.usedPercent, 74);
    expect(s.todayCents, 14200);
    // Last 7 days: Oct 17 to Oct 23 -> 50000 + 20000 + 14200.
    expect(s.weekCents, 84200);
    // 65800 left over 8 days (24th to 31st) = 8225.
    expect(s.safePerDayCents, 8225);
    // Budget over 31 days: 8064.5 rounds half up to 8065.
    expect(s.paceCents, 8065);
  });

  test('safe per day is never negative when over budget', () {
    final s = buildHomeSummary(
      month: oct,
      now: now,
      budgetCents: 10000,
      expenses: [expenseRow(spentOn: '2026-10-10', cents: 30000)],
      categories: categories,
    );
    expect(s.remainingCents, -20000);
    expect(s.safePerDayCents, 0);
    expect(s.usedFraction, 1);
    expect(s.usedPercent, 300);
  });

  test(
    'on the last day of the month the whole remainder is the safe amount',
    () {
      final s = buildHomeSummary(
        month: oct,
        now: DateTime(2026, 10, 31),
        budgetCents: 100000,
        expenses: [expenseRow(spentOn: '2026-10-10', cents: 40000)],
        categories: categories,
      );
      expect(s.safePerDayCents, 60000);
    },
  );

  test('soft-deleted expenses are ignored everywhere', () {
    final s = buildHomeSummary(
      month: oct,
      now: now,
      budgetCents: budget,
      expenses: [
        expenseRow(spentOn: '2026-10-23', cents: 1000, id: 'keep'),
        expenseRow(
          spentOn: '2026-10-23',
          cents: 9999,
          id: 'gone',
          deletedAt: DateTime(2026, 10, 23),
        ),
      ],
      categories: categories,
    );
    expect(s.spentCents, 1000);
    expect(s.todayCents, 1000);
    expect(s.recent.map((r) => r.id), ['keep']);
  });

  test('last 7 days labels end with Today and highlight it', () {
    final s = buildHomeSummary(
      month: oct,
      now: now,
      budgetCents: budget,
      expenses: const [],
      categories: categories,
    );
    expect(s.last7.map((b) => b.label), [
      'Sat',
      'Sun',
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Today',
    ]);
    expect(s.last7.where((b) => b.highlight).length, 1);
    expect(s.last7.last.highlight, isTrue);
  });

  test('the 7-day chart reaches back into the previous month', () {
    final s = buildHomeSummary(
      month: oct,
      now: DateTime(2026, 10, 3),
      budgetCents: budget,
      expenses: [
        expenseRow(spentOn: '2026-09-29', cents: 700),
        expenseRow(spentOn: '2026-10-02', cents: 300),
      ],
      categories: categories,
    );
    // Bars are Sep 27, 28, 29, 30, Oct 1, 2, 3.
    expect(s.last7[2].cents, 700);
    expect(s.last7[5].cents, 300);
    expect(s.last7.map((b) => b.cents).reduce((a, b) => a + b), 1000);
    // Only October counts towards the month total.
    expect(s.spentCents, 300);
    expect(homeRangeStart(oct, DateTime(2026, 10, 3)), DateTime(2026, 9, 27));
    expect(homeRangeEnd(oct), DateTime(2026, 10, 31));
  });

  test('daily bars run from day 1 to today', () {
    final s = buildHomeSummary(
      month: oct,
      now: now,
      budgetCents: budget,
      expenses: [expenseRow(spentOn: '2026-10-02', cents: 500)],
      categories: categories,
    );
    expect(s.monthDaily.length, 23);
    expect(s.monthDaily[1].cents, 500);
    expect(s.monthDaily.first.label, '1');
  });

  test('a past month is measured to its last day and has no safe per day', () {
    final sept = DateTime(2026, 9);
    final s = buildHomeSummary(
      month: sept,
      now: now,
      budgetCents: budget,
      expenses: [
        expenseRow(spentOn: '2026-09-30', cents: 4000),
        expenseRow(spentOn: '2026-09-10', cents: 1000),
      ],
      categories: categories,
    );
    expect(s.spentCents, 5000);
    expect(s.todayCents, 4000, reason: 'the reference day is Sep 30');
    expect(s.safePerDayCents, 0);
    expect(s.monthDaily.length, 30);
    expect(
      s.last7.any((b) => b.highlight),
      isFalse,
      reason: 'there is no "Today" in a past month',
    );
  });

  test('a future month starts empty', () {
    final s = buildHomeSummary(
      month: DateTime(2026, 12),
      now: now,
      budgetCents: budget,
      expenses: const [],
      categories: categories,
    );
    expect(s.spentCents, 0);
    expect(s.monthDaily, isEmpty);
    expect(s.categories, isEmpty);
    expect(
      s.safePerDayCents,
      8065,
      reason: '250000 over 31 days, no days used yet: 250000/31',
    );
  });

  group('top categories', () {
    test('four or fewer categories are shown as they are, largest first', () {
      final s = buildHomeSummary(
        month: oct,
        now: now,
        budgetCents: budget,
        expenses: [
          expenseRow(
            spentOn: '2026-10-01',
            cents: 100,
            category: 'default-bills',
          ),
          expenseRow(
            spentOn: '2026-10-01',
            cents: 300,
            category: 'default-food',
          ),
          expenseRow(
            spentOn: '2026-10-02',
            cents: 200,
            category: 'default-transport',
          ),
        ],
        categories: categories,
      );
      expect(s.categories.map((c) => c.name), ['Food', 'Transport', 'Bills']);
      expect(s.categories.map((c) => c.cents), [300, 200, 100]);
    });

    test(
      'more than four are folded into Other so the bar adds up to the total',
      () {
        final s = buildHomeSummary(
          month: oct,
          now: now,
          budgetCents: budget,
          expenses: [
            expenseRow(
              spentOn: '2026-10-01',
              cents: 500,
              category: 'default-food',
            ),
            expenseRow(
              spentOn: '2026-10-01',
              cents: 400,
              category: 'default-bills',
            ),
            expenseRow(
              spentOn: '2026-10-01',
              cents: 300,
              category: 'default-transport',
            ),
            expenseRow(
              spentOn: '2026-10-01',
              cents: 200,
              category: 'default-fun',
            ),
            expenseRow(
              spentOn: '2026-10-01',
              cents: 100,
              category: 'default-health',
            ),
            expenseRow(
              spentOn: '2026-10-01',
              cents: 50,
              category: 'default-other',
            ),
          ],
          categories: categories,
        );
        expect(s.categories.map((c) => c.name), [
          'Food',
          'Bills',
          'Transport',
          'Other',
        ]);
        expect(s.categories.last.cents, 350, reason: 'Fun + Health + Other');
        expect(s.categories.fold<int>(0, (a, c) => a + c.cents), s.spentCents);
      },
    );

    test('an expense in an unknown category counts as Other', () {
      final s = buildHomeSummary(
        month: oct,
        now: now,
        budgetCents: budget,
        expenses: [
          expenseRow(
            spentOn: '2026-10-01',
            cents: 700,
            category: 'deleted-cat',
          ),
        ],
        categories: categories,
      );
      expect(s.categories.single.name, 'Other');
    });
  });

  group('recent', () {
    test('newest day first, at most four, notes fall back to the category', () {
      final s = buildHomeSummary(
        month: oct,
        now: now,
        budgetCents: budget,
        expenses: [
          for (var d = 1; d <= 6; d++)
            expenseRow(
              spentOn: '2026-10-0$d',
              cents: d * 100,
              note: d == 6 ? '' : 'n$d',
            ),
        ],
        categories: categories,
      );
      expect(s.recent.length, 4);
      expect(
        s.recent.first.note,
        'Food',
        reason: 'empty note shows the category',
      );
      expect(s.recent.map((r) => r.cents), [600, 500, 400, 300]);
    });

    test('who added it: this device is "You", others by name', () {
      final s = buildHomeSummary(
        month: oct,
        now: now,
        budgetCents: budget,
        expenses: [
          expenseRow(
            spentOn: '2026-10-03',
            cents: 100,
            createdBy: 'Maya',
            id: 'a',
          ),
          expenseRow(
            spentOn: '2026-10-02',
            cents: 100,
            createdBy: 'You',
            id: 'b',
          ),
          expenseRow(spentOn: '2026-10-01', cents: 100, id: 'c'),
        ],
        categories: categories,
      );
      expect(s.recent.map((r) => r.addedBy), ['Maya', 'You', 'You']);
    });
  });

  test('no budget means no pace, no safe amount and 0 percent', () {
    final s = buildHomeSummary(
      month: oct,
      now: now,
      budgetCents: 0,
      expenses: [expenseRow(spentOn: '2026-10-10', cents: 100)],
      categories: categories,
    );
    expect(s.paceCents, 0);
    expect(s.safePerDayCents, 0);
    expect(s.usedPercent, 0);
    expect(s.usedFraction, 0);
  });
}
