import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/time.dart';
import '../auth/auth_providers.dart';
import '../budgets/budget_providers.dart';
import '../budgets/domain/budget_calculations.dart';
import '../expenses/expense_providers.dart';
import '../family/member_providers.dart';
import 'domain/overview_calculations.dart';

/// Whose spending the pages show: `null` is everyone, otherwise one member's user id. It
/// changes the numbers on Home and the expense list, never their layout.
class MemberFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? userId) => state = userId;
}

final memberFilterProvider = NotifierProvider<MemberFilter, String?>(
  MemberFilter.new,
);

/// The filter in force: ignored unless this person may see everyone.
final activeMemberFilterProvider = Provider<String?>((ref) {
  if (!ref.watch(canSeeEveryoneProvider)) return null;
  final selected = ref.watch(memberFilterProvider);
  if (selected == null) return null;
  final members = ref.watch(membersProvider).value ?? const <MemberRow>[];
  return members.any((m) => m.userId == selected) ? selected : null;
});

/// Whether [expense] was added by [userId]. Entries made before accounts ("You" or nothing)
/// belong to the signed-in person [me].
bool addedBy(ExpenseRow expense, String userId, String? me) {
  final by = expense.createdBy;
  if (by == null || by == 'You') return me != null && userId == me;
  return by == userId;
}

/// [expenses] narrowed to [userId] (everything when `null`).
List<ExpenseRow> forMember(
  List<ExpenseRow> expenses,
  String? userId,
  String? me,
) => userId == null
    ? expenses
    : [
        for (final e in expenses)
          if (addedBy(e, userId, me)) e,
      ];

/// Which part of Insights is open: the charts or the "Everyone" overview.
enum InsightsTab { charts, everyone }

class InsightsTabNotifier extends Notifier<InsightsTab> {
  @override
  InsightsTab build() => InsightsTab.charts;

  void select(InsightsTab tab) => state = tab;
}

final insightsTabProvider = NotifierProvider<InsightsTabNotifier, InsightsTab>(
  InsightsTabNotifier.new,
);

final overviewExpensesProvider = StreamProvider<List<ExpenseRow>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final now = ref.watch(clockProvider)();
  return ref
      .watch(expenseRepositoryProvider)
      .watchRange(
        overviewRangeStart(month, now),
        DateTime(month.year, month.month, daysInMonth(month)),
      );
});

/// Per-person spending for the selected month.
final overviewProvider = Provider<AsyncValue<OverviewData>>((ref) {
  final expenses = ref.watch(overviewExpensesProvider);
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
  final month = ref.watch(selectedMonthProvider);
  final rows = ref.watch(budgetRowsProvider).value ?? const <BudgetRow>[];
  return AsyncData(
    buildOverview(
      month: month,
      now: ref.watch(clockProvider)(),
      expenses: expenses.requireValue,
      categories: categories.requireValue,
      members: ref.watch(membersProvider).value ?? const <MemberRow>[],
      currentUserId: ref.watch(currentUserIdProvider),
      budgetCents: ref.watch(overallBudgetProvider(month)),
      allowances: effectiveAllowances(rows, month),
    ),
  );
});
