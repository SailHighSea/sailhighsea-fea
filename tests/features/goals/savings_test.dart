import 'dart:async';

import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/features/backup/backup_service.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/goals/data/goal_repository.dart';
import 'package:family_expenses/features/goals/data/savings_repository.dart';
import 'package:family_expenses/features/goals/domain/goal_calculations.dart';
import 'package:family_expenses/features/goals/domain/savings_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/pump_member.dart';
import '../../helpers/test_app.dart';

IncomeRow _income(String month, int cents) => IncomeRow(
  month: month,
  amountCents: cents,
  updatedAt: DateTime(2026, 10, 1),
);

GoalRow _goal(String id, int target, int saved, int monthly) => GoalRow(
  id: id,
  householdId: 'h',
  name: id,
  targetCents: target,
  savedCents: saved,
  monthlyCents: monthly,
  dueOn: null,
  updatedAt: DateTime(2026),
  deletedAt: null,
  dirty: false,
);

BillRow _bill(String id, int cents, String due, {String? paid}) => BillRow(
  id: id,
  householdId: 'h',
  name: id,
  amountCents: cents,
  dueDay: int.parse(due.substring(8)),
  repeat: 'monthly',
  nextDueOn: due,
  lastPaidOn: paid,
  updatedAt: DateTime(2026),
  deletedAt: null,
  dirty: false,
);

/// Runs something that uses the app's own database while its screens watch it (awaiting it
/// inside `runAsync` can stall Drift's streams).
Future<T> _appRun<T>(WidgetTester tester, Future<T> Function() f) async {
  T? result;
  Object? error;
  var done = false;
  unawaited(
    f().then(
      (v) {
        result = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 100 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  if (error != null) throw error!;
  return result as T;
}

void main() {
  setUpAll(loadTestFonts);
  final now = DateTime(2026, 10, 23, 12);
  final october = DateTime(2026, 10);

  SavingsPlan plan({
    List<IncomeRow>? income,
    List<GoalRow>? goals,
    List<BillRow>? bills,
    List<ExpenseRow>? expenses,
    List<SavingsBalanceRow>? balances,
    DateTime? month,
  }) => buildSavingsPlan(
    month: month ?? october,
    now: now,
    income: income ?? [_income('2026-01', 420000)],
    balances: balances ?? const [],
    goals: buildGoalViews(
      goals: goals ?? const [],
      contributions: const [],
      now: now,
    ),
    bills: bills ?? const [],
    expenses: expenses ?? const [],
  );

  group('income for a month', () {
    test('the latest entry at or before the month applies', () {
      final rows = [_income('2026-01', 400000), _income('2026-08', 450000)];
      expect(incomeFor(DateTime(2025, 12), rows), isNull);
      expect(incomeFor(DateTime(2026, 7), rows), 400000);
      expect(incomeFor(DateTime(2026, 8), rows), 450000);
      expect(incomeFor(DateTime(2026, 10), rows), 450000);
    });
  });

  group('the plan', () {
    test('left = income - spent - bills due - monthly goal amounts', () {
      final p = plan(
        goals: [
          _goal('a', 1000000, 620000, 50000),
          _goal('b', 300000, 185000, 25000),
        ],
        bills: [_bill('rent', 39600, '2026-10-28')],
        expenses: [
          expenseRow(spentOn: '2026-10-02', cents: 120000),
          expenseRow(spentOn: '2026-10-20', cents: 64200),
          expenseRow(spentOn: '2026-09-30', cents: 999999),
        ],
      );
      expect(p.incomeCents, 420000);
      expect(p.spentCents, 184200);
      expect(p.billsDueCents, 39600);
      expect(p.goalsMonthlyCents, 75000);
      expect(p.leftCents, 420000 - 184200 - 39600 - 75000);
      expect(p.status, PlanStatus.fits);
      expect(p.ratePercent, 56);
      expect(p.goalsPercent, 18);
    });

    test('a goal that is reached asks for nothing more', () {
      final p = plan(goals: [_goal('done', 100000, 100000, 50000)]);
      expect(p.goalsMonthlyCents, 0);
    });

    test('paid and past-month bills are not counted as due', () {
      expect(
        plan(
          bills: [
            _bill('paid-once', 1000, '2026-10-28', paid: '2026-10-01'),
            _bill('next-month', 2000, '2026-11-03'),
          ],
        ).billsDueCents,
        // The monthly bill that was paid still comes due again; only this month's date counts.
        1000,
      );
      expect(
        plan(
          month: DateTime(2026, 9),
          bills: [_bill('sep', 5000, '2026-09-20')],
        ).billsDueCents,
        0,
        reason: 'a finished month has no bills still to come',
      );
    });

    test('goals that ask for more than is left are flagged', () {
      final p = plan(
        goals: [_goal('a', 9000000, 0, 300000)],
        expenses: [expenseRow(spentOn: '2026-10-02', cents: 200000)],
      );
      expect(p.availableForGoalsCents, 220000);
      expect(p.status, PlanStatus.short);
      expect(p.leftCents, -80000);
    });

    test('no income means no plan numbers and a prompt', () {
      final p = plan(income: const []);
      expect(p.hasIncome, isFalse);
      expect(p.status, PlanStatus.noIncome);
      expect(p.ratePercent, isNull);
    });

    test(
      'six months of savings rate, oldest first, blank before income starts',
      () {
        final p = plan(
          income: [_income('2026-07', 400000)],
          expenses: [
            expenseRow(spentOn: '2026-07-10', cents: 200000),
            expenseRow(spentOn: '2026-09-10', cents: 100000),
          ],
        );
        expect(p.history.map((r) => r.month.month), [5, 6, 7, 8, 9, 10]);
        expect(p.history.map((r) => r.percent), [null, null, 50, 100, 75, 100]);
      },
    );

    test('savings are split into goals and not in a goal', () {
      final p = plan(
        goals: [_goal('a', 1000000, 620000, 0), _goal('b', 300000, 185000, 0)],
        balances: [
          SavingsBalanceRow(
            asOn: '2026-09-01',
            amountCents: 1000000,
            updatedAt: DateTime(2026, 9, 1),
          ),
          SavingsBalanceRow(
            asOn: '2026-10-20',
            amountCents: 1430000,
            updatedAt: DateTime(2026, 10, 20),
          ),
        ],
      );
      expect(p.totalSavingsCents, 1430000);
      expect(p.inGoalsCents, 805000);
      expect(p.notInGoalsCents, 625000);
    });

    test('a total below what is in goals shows nothing outside goals', () {
      final p = plan(
        goals: [_goal('a', 1000000, 620000, 0)],
        balances: [
          SavingsBalanceRow(
            asOn: '2026-10-20',
            amountCents: 100000,
            updatedAt: DateTime(2026, 10, 20),
          ),
        ],
      );
      expect(p.notInGoalsCents, 0);
    });
  });

  group('stored on this device', () {
    test(
      'income replaces within a month; the total keeps a row per day',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final repo = SavingsRepository(db, clock: () => now);
        await repo.setIncome(october, 400000);
        await repo.setIncome(october, 420000);
        await repo.setIncome(DateTime(2026, 11), 450000);
        expect(await db.select(db.incomeEntries).get(), hasLength(2));
        await repo.setTotal(1000000);
        await repo.setTotal(1430000);
        final totals = await db.select(db.savingsBalances).get();
        expect(totals.single.amountCents, 1430000, reason: 'same day replaces');
      },
    );

    test('they are in the backup and come back from it', () async {
      final a = AppDatabase(NativeDatabase.memory());
      final b = AppDatabase(NativeDatabase.memory());
      addTearDown(a.close);
      addTearDown(b.close);
      final repo = SavingsRepository(a, clock: () => now);
      await repo.setIncome(october, 420000);
      await repo.setTotal(1430000);
      final text = await BackupService(a, currencyCode: 'SGD').export();
      await BackupService(b, currencyCode: 'SGD').restore(text);
      expect(
        (await b.select(b.incomeEntries).get()).single.amountCents,
        420000,
      );
      expect(
        (await b.select(b.savingsBalances).get()).single.amountCents,
        1430000,
      );
    });
  });

  group('on the Goals page', () {
    Future<ProviderContainer> open(
      WidgetTester tester, {
      Size size = const Size(390, 844),
    }) => pumpApp(
      tester,
      size: size,
      location: '/goals',
      seedAsync: (db) async {
        final goals = GoalRepository(db, clock: () => now);
        await goals.add(
          name: 'Emergency fund',
          targetCents: 1000000,
          savedCents: 620000,
          monthlyCents: 50000,
        );
        final expenses = ExpenseRepository(db, clock: () => now);
        await expenses.add(
          amountCents: 184200,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 5),
          note: 'Month so far',
          createdBy: 'You',
        );
      },
    );

    testWidgets('without income it asks for it, then shows what is left', (
      tester,
    ) async {
      final c = await open(tester);
      expect(key('income-empty'), findsOneWidget);
      await tapKey(tester, 'income-set');
      await tester.enterText(key('income-amount'), '4200');
      await tester.enterText(key('income-total'), '14300');
      await tapKey(tester, 'income-save');
      await settle(tester);
      expect(key('income-empty'), findsNothing);
      expect(find.text('Left to save this month'), findsOneWidget);
      expect(key('savings-flow'), findsOneWidget);
      final bar = find.descendant(
        of: key('savings-flow'),
        matching: find.byType(ColoredBox),
      );
      expect(bar, findsWidgets);
      expect(
        tester.getSize(bar.first).height,
        16,
        reason: 'the split bar is drawn, not collapsed',
      );
      expect(key('savings-total'), findsOneWidget);
      expect(key('savings-rate'), findsOneWidget);
      final db = c.read(databaseProvider);
      final rows = await tester.runAsync(
        () => db.select(db.incomeEntries).get(),
      );
      expect(rows!.single.amountCents, 420000);
    });

    testWidgets('an empty save asks for something', (tester) async {
      await open(tester);
      await tapKey(tester, 'income-set');
      await tapKey(tester, 'income-save');
      expect(key('income-error'), findsOneWidget);
    });

    for (final size in const {
      'phone': Size(390, 844),
      'phone small, large text': Size(320, 640),
      'tablet': Size(840, 900),
      'desktop': Size(1280, 800),
    }.entries) {
      testWidgets('fits on ${size.key}', (tester) async {
        final c = await open(tester, size: size.value);
        final db = c.read(databaseProvider);
        await _appRun(tester, () async {
          final repo = SavingsRepository(db, clock: () => now);
          await repo.setIncome(october, 420000);
          await repo.setTotal(1430000);
        });
        await settle(tester);
        expect(find.text('Left to save this month'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }

    testWidgets('a view-only member sees the numbers but has no edit button', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/goals',
        size: const Size(390, 844),
      );
      expect(key('income-set'), findsNothing);
      expect(key('income-edit'), findsNothing);
    });
  });
}
