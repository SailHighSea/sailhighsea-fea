import 'package:drift/drift.dart' show StringExpressionOperators, Value;
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/features/bills/data/bill_repository.dart';
import 'package:family_expenses/features/bills/domain/bill_calculations.dart';
import 'package:family_expenses/features/budgets/data/budget_repository.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/goals/data/goal_repository.dart';

/// The numbers from the Phase 5 mockups, in October 2026 with "today" 2026-10-23.
/// Budgets: Food 800, Transport 300, Bills 600, Fun 300, Health 200 of 2,500 overall.
Future<void> seedPhase5(
  AppDatabase db, {
  String household = 'local',
  DateTime? now,
}) async {
  final clock = now ?? DateTime(2026, 10, 23, 12);
  final expenses = ExpenseRepository(
    db,
    clock: () => clock,
    householdId: household,
  );
  final budgets = BudgetRepository(
    db,
    clock: () => clock,
    householdId: household,
  );
  final goals = GoalRepository(db, clock: () => clock, householdId: household);
  final bills = BillRepository(db, clock: () => clock, householdId: household);
  final oct = DateTime(2026, 10);
  if (household != 'local') {
    // The default categories were seeded under the local household; move them across, as
    // joining or creating a household does.
    await (db.update(db.categories)..where((c) => c.id.like('default-%')))
        .write(CategoriesCompanion(householdId: Value(household)));
  }

  Future<void> spend(
    int cents,
    String category,
    int day,
    String who, {
    String note = '',
  }) => expenses.add(
    amountCents: cents,
    categoryId: category,
    spentOn: DateTime(2026, 10, day),
    note: note,
    createdBy: who,
  );

  // 1,842 in total: Food 612, Bills 520, Transport 284, Fun 210, Other 216.
  await spend(61200, 'default-food', 3, 'You', note: 'Groceries');
  await spend(52000, 'default-bills', 5, 'You', note: 'Rent share');
  await spend(28400, 'default-transport', 8, 'Maya', note: 'Fuel');
  await spend(21000, 'default-fun', 12, 'Maya', note: 'Cinema');
  await spend(21600, 'default-other', 20, 'Sam', note: 'Gift');
  // Earlier months for the trend chart.
  for (final (m, cents) in [
    (5, 221000),
    (6, 198000),
    (7, 234000),
    (8, 205000),
    (9, 219000),
  ]) {
    await expenses.add(
      amountCents: cents,
      categoryId: 'default-food',
      spentOn: DateTime(2026, m, 10),
      createdBy: 'You',
    );
  }

  await budgets.setBudget(oct, null, 250000);
  await budgets.setBudget(oct, 'default-food', 80000);
  await budgets.setBudget(oct, 'default-transport', 30000);
  await budgets.setBudget(oct, 'default-bills', 60000);
  await budgets.setBudget(oct, 'default-fun', 30000);
  await budgets.setBudget(oct, 'default-health', 20000);

  final holiday = await goals.add(
    name: 'Holiday trip',
    targetCents: 300000,
    savedCents: 105000,
    monthlyCents: 15000,
  );
  await goals.addMoney(
    holiday,
    cents: 15000,
    addedBy: 'Maya',
    on: DateTime(2026, 10, 15),
  );
  final fund = await goals.add(
    name: 'Emergency fund',
    targetCents: 600000,
    savedCents: 425000,
    monthlyCents: 25000,
  );
  await goals.addMoney(
    fund,
    cents: 25000,
    addedBy: 'You',
    on: DateTime(2026, 10, 12),
  );
  final laptop = await goals.add(
    name: 'New laptop',
    targetCents: 180000,
    savedCents: 50000,
    monthlyCents: 10000,
  );
  await goals.addMoney(
    laptop,
    cents: 10000,
    addedBy: 'Sam',
    on: DateTime(2026, 10, 5),
  );

  Future<void> bill(String name, int cents, DateTime due) => bills.add(
    name: name,
    amountCents: cents,
    nextDueOn: due,
    repeat: BillRepeat.monthly,
  );
  await bill('Electricity', 9640, DateTime(2026, 10, 28));
  await bill('Internet', 4990, DateTime(2026, 10, 30));
  await bill('Phone plan', 3500, DateTime(2026, 11, 2));
  await bill('Streaming plan', 1998, DateTime(2026, 11, 5));
  await bill('Insurance', 11800, DateTime(2026, 11, 15));
}

/// Gives the seeded expenses real member ids (sampleHousehold: user-you, user-maya, user-sam),
/// so the overview can tell people apart.
Future<void> useMemberIds(AppDatabase db) async {
  for (final (name, id) in [
    ('You', 'user-you'),
    ('Maya', 'user-maya'),
    ('Sam', 'user-sam'),
  ]) {
    await (db.update(db.expenses)..where((e) => e.createdBy.equals(name)))
        .write(ExpensesCompanion(createdBy: Value(id)));
  }
}
