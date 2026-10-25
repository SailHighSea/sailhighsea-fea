import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/ids.dart';
import '../../../core/db/tables.dart' show localHouseholdId;
import 'day_format.dart';

/// Reads and writes expenses in the local database (the UI never touches Drift directly).
/// Writes mark the row `dirty` and bump `updated_at`; deletes are soft (rule 5).
class ExpenseRepository {
  ExpenseRepository(
    this._db, {
    DateTime Function()? clock,
    this.householdId = localHouseholdId,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;

  /// Only this household's expenses are read and written.
  final String householdId;
  final DateTime Function() _clock;

  /// Live expenses with `spentOn` from [from] to [to], both inclusive, newest first.
  Stream<List<ExpenseRow>> watchRange(DateTime from, DateTime to) {
    final query = _db.select(_db.expenses)
      ..where(
        (e) =>
            e.householdId.equals(householdId) &
            e.deletedAt.isNull() &
            e.spentOn.isBiggerOrEqualValue(formatDay(from)) &
            e.spentOn.isSmallerOrEqualValue(formatDay(to)),
      )
      ..orderBy([
        (e) => OrderingTerm.desc(e.spentOn),
        (e) => OrderingTerm.desc(e.updatedAt),
      ]);
    return query.watch();
  }

  /// Live expenses in the calendar month of [month].
  Stream<List<ExpenseRow>> watchMonth(DateTime month) => watchRange(
    DateTime(month.year, month.month),
    DateTime(month.year, month.month + 1, 0),
  );

  Future<ExpenseRow?> getById(String id) => (_db.select(
    _db.expenses,
  )..where((e) => e.id.equals(id) & e.deletedAt.isNull())).getSingleOrNull();

  /// Adds an expense and returns its id.
  Future<String> add({
    required int amountCents,
    required String categoryId,
    required DateTime spentOn,
    String note = '',
    String? createdBy,
    String? receiptPath,
  }) async {
    _checkAmount(amountCents);
    final id = newId();
    await _db
        .into(_db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: id,
            householdId: Value(householdId),
            amountCents: amountCents,
            categoryId: categoryId,
            note: Value(note.trim()),
            spentOn: formatDay(spentOn),
            createdBy: Value(createdBy),
            receiptPath: Value(receiptPath),
            updatedAt: _clock(),
          ),
        );
    return id;
  }

  Future<void> update(
    String id, {
    required int amountCents,
    required String categoryId,
    required DateTime spentOn,
    String note = '',
  }) async {
    _checkAmount(amountCents);
    await (_db.update(_db.expenses)..where((e) => e.id.equals(id))).write(
      ExpensesCompanion(
        amountCents: Value(amountCents),
        categoryId: Value(categoryId),
        note: Value(note.trim()),
        spentOn: Value(formatDay(spentOn)),
        updatedAt: Value(_clock()),
        dirty: const Value(true),
      ),
    );
  }

  /// Soft delete: the row stays so the delete can sync and be undone.
  Future<void> softDelete(String id) =>
      (_db.update(_db.expenses)..where((e) => e.id.equals(id))).write(
        ExpensesCompanion(
          deletedAt: Value(_clock()),
          updatedAt: Value(_clock()),
          dirty: const Value(true),
        ),
      );

  /// Undo for [softDelete].
  Future<void> restore(String id) =>
      (_db.update(_db.expenses)..where((e) => e.id.equals(id))).write(
        ExpensesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(_clock()),
          dirty: const Value(true),
        ),
      );

  void _checkAmount(int cents) {
    if (cents <= 0) {
      throw ArgumentError.value(
        cents,
        'amountCents',
        'must be greater than zero',
      );
    }
  }
}
