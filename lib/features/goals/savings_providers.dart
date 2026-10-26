import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/time.dart';
import '../bills/bill_providers.dart';
import '../expenses/expense_providers.dart';
import 'data/savings_repository.dart';
import 'domain/savings_plan.dart';
import 'goal_providers.dart';

final savingsRepositoryProvider = Provider<SavingsRepository>(
  (ref) => SavingsRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

final incomeRowsProvider = StreamProvider<List<IncomeRow>>(
  (ref) => ref.watch(savingsRepositoryProvider).watchIncome(),
);

final savingsBalanceRowsProvider = StreamProvider<List<SavingsBalanceRow>>(
  (ref) => ref.watch(savingsRepositoryProvider).watchBalances(),
);

final _savingsExpensesProvider = StreamProvider<List<ExpenseRow>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref
      .watch(expenseRepositoryProvider)
      .watchRange(
        savingsRangeStart(month),
        DateTime(month.year, month.month, daysInMonth(month)),
      );
});

/// The selected month's income, spending, bills, goals and savings.
final savingsPlanProvider = Provider<AsyncValue<SavingsPlan>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final income = ref.watch(incomeRowsProvider);
  final balances = ref.watch(savingsBalanceRowsProvider);
  final goals = ref.watch(goalViewsProvider);
  final bills = ref.watch(billRowsProvider);
  final expenses = ref.watch(_savingsExpensesProvider);
  for (final a in [income, balances, goals, bills, expenses]) {
    if (a.hasError) {
      return AsyncError(a.error!, a.stackTrace ?? StackTrace.empty);
    }
  }
  if (!income.hasValue ||
      !balances.hasValue ||
      !goals.hasValue ||
      !bills.hasValue ||
      !expenses.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    buildSavingsPlan(
      month: month,
      now: ref.watch(clockProvider)(),
      income: income.requireValue,
      balances: balances.requireValue,
      goals: goals.requireValue,
      bills: bills.requireValue,
      expenses: expenses.requireValue,
    ),
  );
});
