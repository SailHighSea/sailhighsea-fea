import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/time.dart';
import '../expenses/expense_providers.dart';
import '../family/member_providers.dart';
import 'data/budget_repository.dart';
import 'domain/budget_calculations.dart';

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
    householdId: ref.watch(activeHouseholdIdProvider),
  ),
);

/// Every stored budget row of the household (deleted ones too).
final budgetRowsProvider = StreamProvider<List<BudgetRow>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchAll(),
);

/// Budgets and what has been spent against them for the selected month.
final budgetsSummaryProvider = Provider<AsyncValue<BudgetsSummary>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final rows = ref.watch(budgetRowsProvider);
  final expenses = ref.watch(monthExpensesProvider(month));
  final categories = ref.watch(categoriesProvider);
  final failure = [rows, expenses, categories].where((a) => a.hasError);
  if (failure.isNotEmpty) {
    return AsyncError(
      failure.first.error!,
      failure.first.stackTrace ?? StackTrace.empty,
    );
  }
  if (!rows.hasValue || !expenses.hasValue || !categories.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    buildBudgetsSummary(
      month: month,
      now: ref.watch(clockProvider)(),
      budgetRows: rows.requireValue,
      expenses: expenses.requireValue,
      categories: categories.requireValue,
    ),
  );
});

/// The overall monthly budget for [month]: the one set, or the default.
final overallBudgetProvider = Provider.family<int, DateTime>((ref, month) {
  final rows = ref.watch(budgetRowsProvider).value ?? const [];
  return effectiveBudgets(rows, month)[null] ?? defaultMonthlyBudgetCents;
});
