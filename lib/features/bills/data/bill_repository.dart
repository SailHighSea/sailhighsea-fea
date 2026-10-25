import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/ids.dart';
import '../../../core/db/tables.dart' show localHouseholdId;
import '../../expenses/data/day_format.dart';
import '../domain/bill_calculations.dart';

/// Recurring bills in the local database.
class BillRepository {
  BillRepository(
    this._db, {
    DateTime Function()? clock,
    this.householdId = localHouseholdId,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final String householdId;
  final DateTime Function() _clock;

  Stream<List<BillRow>> watchAll() => (_db.select(
    _db.bills,
  )..where((b) => b.householdId.equals(householdId))).watch();

  Future<BillRow?> getById(String id) =>
      (_db.select(_db.bills)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<String> add({
    required String name,
    required int amountCents,
    required DateTime nextDueOn,
    BillRepeat repeat = BillRepeat.monthly,
  }) async {
    _check(name, amountCents);
    final id = newId();
    await _db
        .into(_db.bills)
        .insert(
          BillsCompanion.insert(
            id: id,
            householdId: Value(householdId),
            name: name.trim(),
            amountCents: amountCents,
            dueDay: nextDueOn.day,
            repeat: Value(repeat.dbValue),
            nextDueOn: formatDay(nextDueOn),
            updatedAt: _clock(),
          ),
        );
    return id;
  }

  Future<void> update(
    String id, {
    required String name,
    required int amountCents,
    required DateTime nextDueOn,
    required BillRepeat repeat,
  }) async {
    _check(name, amountCents);
    await (_db.update(_db.bills)..where((b) => b.id.equals(id))).write(
      BillsCompanion(
        name: Value(name.trim()),
        amountCents: Value(amountCents),
        dueDay: Value(nextDueOn.day),
        repeat: Value(repeat.dbValue),
        nextDueOn: Value(formatDay(nextDueOn)),
        updatedAt: Value(_clock()),
        dirty: const Value(true),
      ),
    );
  }

  /// Records the payment and moves the due date to the next period.
  Future<void> markPaid(String id) async {
    final bill = await getById(id);
    if (bill == null) return;
    final paid = markPaidResult(bill, _clock());
    await (_db.update(_db.bills)..where((b) => b.id.equals(id))).write(
      BillsCompanion(
        lastPaidOn: Value(formatDay(paid.lastPaidOn)),
        nextDueOn: Value(formatDay(paid.nextDueOn)),
        updatedAt: Value(_clock()),
        dirty: const Value(true),
      ),
    );
  }

  /// Puts the dates back (Undo after "Mark paid").
  Future<void> setDates(
    String id, {
    required String nextDueOn,
    String? lastPaidOn,
  }) => (_db.update(_db.bills)..where((b) => b.id.equals(id))).write(
    BillsCompanion(
      nextDueOn: Value(nextDueOn),
      lastPaidOn: Value(lastPaidOn),
      updatedAt: Value(_clock()),
      dirty: const Value(true),
    ),
  );

  Future<void> softDelete(String id) async {
    final now = _clock();
    await (_db.update(_db.bills)..where((b) => b.id.equals(id))).write(
      BillsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> restore(String id) =>
      (_db.update(_db.bills)..where((b) => b.id.equals(id))).write(
        BillsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(_clock()),
          dirty: const Value(true),
        ),
      );

  void _check(String name, int cents) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (cents <= 0) {
      throw ArgumentError.value(cents, 'amountCents', 'must be above zero');
    }
  }
}
