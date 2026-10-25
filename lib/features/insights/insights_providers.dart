import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/money/money_provider.dart';
import '../../core/time.dart';
import '../budgets/budget_providers.dart';
import '../expenses/expense_providers.dart';
import '../family/member_providers.dart';
import 'domain/insights_calculations.dart';

class InsightsPeriodNotifier extends Notifier<InsightsPeriod> {
  @override
  InsightsPeriod build() => InsightsPeriod.month;

  void select(InsightsPeriod period) => state = period;
}

final insightsPeriodProvider =
    NotifierProvider<InsightsPeriodNotifier, InsightsPeriod>(
      InsightsPeriodNotifier.new,
    );

final insightsExpensesProvider = StreamProvider<List<ExpenseRow>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final period = ref.watch(insightsPeriodProvider);
  final range = insightsRange(period, month, ref.watch(clockProvider)());
  return ref.watch(expenseRepositoryProvider).watchRange(range.from, range.to);
});

/// What Insights shows, for the selected month and period.
final insightsProvider = Provider<AsyncValue<InsightsData>>((ref) {
  final expenses = ref.watch(insightsExpensesProvider);
  final categories = ref.watch(categoriesProvider);
  final budgets = ref.watch(budgetsSummaryProvider);
  final failure = [expenses, categories, budgets].where((a) => a.hasError);
  if (failure.isNotEmpty) {
    return AsyncError(
      failure.first.error!,
      failure.first.stackTrace ?? StackTrace.empty,
    );
  }
  if (!expenses.hasValue || !categories.hasValue || !budgets.hasValue) {
    return const AsyncLoading();
  }
  final money = ref.watch(moneyFormatterProvider);
  return AsyncData(
    buildInsights(
      period: ref.watch(insightsPeriodProvider),
      month: ref.watch(selectedMonthProvider),
      now: ref.watch(clockProvider)(),
      expenses: expenses.requireValue,
      categories: categories.requireValue,
      overallBudgetCents: budgets.requireValue.overallCents,
      budgetLines: budgets.requireValue.lines,
      memberName: ref.watch(addedByLabelProvider),
      money: money.formatWhole,
    ),
  );
});
