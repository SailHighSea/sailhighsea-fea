import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables.dart' show localHouseholdId;
import '../domain/budget_calculations.dart';

/// Budgets in the local database. Each (month, category) has one row with a fixed id, so
/// setting the same budget twice, on any device, edits that row.
class BudgetRepository {
  BudgetRepository(
    this._db, {
    DateTime Function()? clock,
    this.householdId = localHouseholdId,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final String householdId;
  final DateTime Function() _clock;

  /// Every row, deleted ones too: a deleted row means "no budget from this month on".
  Stream<List<BudgetRow>> watchAll() => (_db.select(
    _db.budgets,
  )..where((b) => b.householdId.equals(householdId))).watch();

  /// Sets the budget of [categoryId] (`null` = overall) from [month] on. An amount of zero
  /// or less removes it.
  Future<void> setBudget(DateTime month, String? categoryId, int cents) async {
    if (cents <= 0) return remove(month, categoryId);
    await _write(month, categoryId, cents, deleted: false);
  }

  /// No budget for this category from [month] on (earlier months keep theirs).
  Future<void> remove(DateTime month, String? categoryId) async {
    final existing =
        await (_db.select(_db.budgets)
              ..where((b) => b.id.equals(budgetId(month, categoryId))))
            .getSingleOrNull();
    await _write(month, categoryId, existing?.amountCents ?? 1, deleted: true);
  }

  Future<void> _write(
    DateTime month,
    String? categoryId,
    int cents, {
    required bool deleted,
  }) async {
    final now = _clock();
    await _db
        .into(_db.budgets)
        .insertOnConflictUpdate(
          BudgetsCompanion.insert(
            id: budgetId(month, categoryId),
            householdId: Value(householdId),
            month: budgetMonthText(month),
            categoryId: Value(categoryId),
            amountCents: cents,
            updatedAt: now,
            deletedAt: Value(deleted ? now : null),
            dirty: const Value(true),
          ),
        );
  }
}
