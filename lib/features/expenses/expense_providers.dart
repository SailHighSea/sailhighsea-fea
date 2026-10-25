import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/time.dart';
import 'data/category_repository.dart';
import 'data/expense_repository.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Live, ordered list of categories.
final categoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);

/// Live expenses of one calendar month.
final monthExpensesProvider = StreamProvider.family<List<ExpenseRow>, DateTime>(
  (ref, month) => ref.watch(expenseRepositoryProvider).watchMonth(month),
);
