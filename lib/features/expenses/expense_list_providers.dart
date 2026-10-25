import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/time.dart';
import '../auth/auth_providers.dart';
import '../overview/overview_providers.dart';
import 'expense_providers.dart';

@immutable
class ExpenseFilter {
  const ExpenseFilter({this.query = '', this.categoryId});

  final String query;

  /// Null shows every category.
  final String? categoryId;

  ExpenseFilter copyWith({
    String? query,
    String? categoryId,
    bool clearCategory = false,
  }) => ExpenseFilter(
    query: query ?? this.query,
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
  );
}

class ExpenseFilterController extends Notifier<ExpenseFilter> {
  @override
  ExpenseFilter build() => const ExpenseFilter();

  void setQuery(String query) => state = state.copyWith(query: query);
  void setCategory(String? id) => state = id == null
      ? state.copyWith(clearCategory: true)
      : state.copyWith(categoryId: id);
}

final expenseFilterProvider =
    NotifierProvider<ExpenseFilterController, ExpenseFilter>(
      ExpenseFilterController.new,
    );

/// Expenses of the selected month, filtered by category and by a search over note,
/// category name and who added them.
final filteredExpensesProvider = Provider<AsyncValue<List<ExpenseRow>>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final expenses = ref.watch(monthExpensesProvider(month));
  final categories =
      ref.watch(categoriesProvider).value ?? const <CategoryRow>[];
  final filter = ref.watch(expenseFilterProvider);
  final person = ref.watch(activeMemberFilterProvider);
  final me = ref.watch(currentUserIdProvider);
  return expenses.whenData(
    (rows) => filterExpenses(forMember(rows, person, me), categories, filter),
  );
});

List<ExpenseRow> filterExpenses(
  List<ExpenseRow> rows,
  List<CategoryRow> categories,
  ExpenseFilter filter,
) {
  final names = {for (final c in categories) c.id: c.name.toLowerCase()};
  final q = filter.query.trim().toLowerCase();
  return [
    for (final e in rows)
      if ((filter.categoryId == null || e.categoryId == filter.categoryId) &&
          (q.isEmpty ||
              e.note.toLowerCase().contains(q) ||
              (names[e.categoryId] ?? '').contains(q) ||
              (e.createdBy ?? '').toLowerCase().contains(q)))
        e,
  ];
}

/// Ctrl or Cmd + F asks the expense list to focus its search box (also when the list was not
/// open yet). The list clears the request once it has focused the box.
class SearchFocusRequest extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;
  void clear() => state = false;
}

final searchFocusRequestProvider = NotifierProvider<SearchFocusRequest, bool>(
  SearchFocusRequest.new,
);
