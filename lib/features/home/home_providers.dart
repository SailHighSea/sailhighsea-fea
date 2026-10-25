import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/time.dart';
import '../budgets/budget_providers.dart';
import '../expenses/expense_providers.dart';
import '../family/member_providers.dart';
import 'home_calculations.dart';
import 'home_data.dart';

/// Expenses the Home screen needs for the selected month, including the days before the
/// month start that the 7-day chart can reach.
final homeExpensesProvider = StreamProvider<List<ExpenseRow>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final now = ref.watch(clockProvider)();
  return ref
      .watch(expenseRepositoryProvider)
      .watchRange(homeRangeStart(month, now), homeRangeEnd(month));
});

/// What Home shows for the selected month, computed from the local database.
/// Bills and goals arrive in Phase 5, so those two cards show their empty states.
final homeSummaryProvider = Provider<AsyncValue<HomeSummary>>((ref) {
  final expenses = ref.watch(homeExpensesProvider);
  final categories = ref.watch(categoriesProvider);
  if (expenses.hasError) {
    return AsyncError(expenses.error!, expenses.stackTrace ?? StackTrace.empty);
  }
  if (categories.hasError) {
    return AsyncError(
      categories.error!,
      categories.stackTrace ?? StackTrace.empty,
    );
  }
  if (!expenses.hasValue || !categories.hasValue) return const AsyncLoading();
  return AsyncData(
    buildHomeSummary(
      month: ref.watch(selectedMonthProvider),
      now: ref.watch(clockProvider)(),
      budgetCents: ref.watch(monthlyBudgetCentsProvider),
      expenses: expenses.requireValue,
      categories: categories.requireValue,
      currentUser: ref.watch(currentUserNameProvider),
    ),
  );
});
