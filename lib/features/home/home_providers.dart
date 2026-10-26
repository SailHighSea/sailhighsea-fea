import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/time.dart';
import '../bills/bill_providers.dart';
import '../bills/domain/bill_calculations.dart';
import '../budgets/budget_providers.dart';
import '../goals/domain/goal_calculations.dart';
import '../goals/goal_providers.dart';
import '../expenses/expense_providers.dart';
import '../auth/auth_providers.dart';
import '../family/member_providers.dart';
import '../overview/overview_providers.dart';
import 'home_calculations.dart';
import 'home_data.dart';

/// Expenses the Home screen needs for the selected month, including the days before the
/// month start that the 7-day chart can reach.
final homeExpensesProvider = StreamProvider<List<ExpenseRow>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final now = ref.watch(clockProvider)();
  final person = ref.watch(activeMemberFilterProvider);
  final me = ref.watch(currentUserIdProvider);
  return ref
      .watch(expenseRepositoryProvider)
      .watchRange(homeRangeStart(month, now), homeRangeEnd(month))
      .map((rows) => forMember(rows, person, me));
});

/// The previous month, for the "against last month" comparison.
final homePreviousExpensesProvider = StreamProvider<List<ExpenseRow>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final person = ref.watch(activeMemberFilterProvider);
  final me = ref.watch(currentUserIdProvider);
  final prev = DateTime(month.year, month.month - 1);
  return ref
      .watch(expenseRepositoryProvider)
      .watchRange(prev, DateTime(prev.year, prev.month, daysInMonth(prev)))
      .map((rows) => forMember(rows, person, me));
});

/// What Home shows for the selected month, computed from the local database.
/// The next bill and the featured goal come from the bills and goals the household set up.
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
      budgetCents: ref.watch(
        overallBudgetProvider(ref.watch(selectedMonthProvider)),
      ),
      expenses: expenses.requireValue,
      categories: categories.requireValue,
      addedByLabel: ref.watch(addedByLabelProvider),
      nextBill: _nextBill(ref.watch(upcomingBillsProvider).value ?? const []),
      goal: _goal(ref.watch(goalViewsProvider).value ?? const []),
      previousExpenses:
          ref.watch(homePreviousExpensesProvider).value ?? const [],
    ),
  );
});

UpcomingBill? _nextBill(List<BillView> bills) {
  if (bills.isEmpty) return null;
  final first = bills.first;
  final last = dueBy(bills)!;
  return UpcomingBill(
    name: first.bill.name,
    amountCents: first.amountCents,
    daysUntil: first.daysUntil < 0 ? 0 : first.daysUntil,
    billCount: bills.length,
    totalDueCents: totalDue(bills),
    dueByLabel: dayMonthLabel(last),
  );
}

GoalProgress? _goal(List<GoalView> goals) {
  final g = featuredGoal(goals);
  if (g == null) return null;
  return GoalProgress(
    name: g.goal.name,
    savedCents: g.savedCents,
    targetCents: g.targetCents,
    monthlyCents: g.goal.monthlyCents,
    doneByLabel: g.reached
        ? 'now'
        : monthYearLabel(g.projectedFinish ?? g.dueOn) ?? 'later',
  );
}
