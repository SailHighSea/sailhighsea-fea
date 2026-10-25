import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/ids.dart';
import '../../../core/db/tables.dart' show localHouseholdId;
import '../../expenses/data/day_format.dart';

/// Goals and the money added to them, in the local database.
class GoalRepository {
  GoalRepository(
    this._db, {
    DateTime Function()? clock,
    this.householdId = localHouseholdId,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final String householdId;
  final DateTime Function() _clock;

  Stream<List<GoalRow>> watchGoals() => (_db.select(
    _db.goals,
  )..where((g) => g.householdId.equals(householdId))).watch();

  Stream<List<GoalContributionRow>> watchContributions() => (_db.select(
    _db.goalContributions,
  )..where((c) => c.householdId.equals(householdId))).watch();

  Future<String> add({
    required String name,
    required int targetCents,
    int savedCents = 0,
    int monthlyCents = 0,
    DateTime? dueOn,
  }) async {
    _check(name, targetCents, savedCents, monthlyCents);
    final id = newId();
    await _db
        .into(_db.goals)
        .insert(
          GoalsCompanion.insert(
            id: id,
            householdId: Value(householdId),
            name: name.trim(),
            targetCents: targetCents,
            savedCents: Value(savedCents),
            monthlyCents: Value(monthlyCents),
            dueOn: Value(dueOn == null ? null : formatDay(dueOn)),
            updatedAt: _clock(),
          ),
        );
    return id;
  }

  Future<void> update(
    String id, {
    required String name,
    required int targetCents,
    required int savedCents,
    required int monthlyCents,
    DateTime? dueOn,
  }) async {
    _check(name, targetCents, savedCents, monthlyCents);
    await (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
      GoalsCompanion(
        name: Value(name.trim()),
        targetCents: Value(targetCents),
        savedCents: Value(savedCents),
        monthlyCents: Value(monthlyCents),
        dueOn: Value(dueOn == null ? null : formatDay(dueOn)),
        updatedAt: Value(_clock()),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    final now = _clock();
    await (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
      GoalsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> restore(String id) =>
      (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
        GoalsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(_clock()),
          dirty: const Value(true),
        ),
      );

  /// Adds money to a goal. Each addition is its own row, so two people adding at once both
  /// count.
  Future<String> addMoney(
    String goalId, {
    required int cents,
    String? addedBy,
    DateTime? on,
  }) async {
    if (cents <= 0) {
      throw ArgumentError.value(cents, 'cents', 'must be greater than zero');
    }
    final id = newId();
    final now = _clock();
    await _db
        .into(_db.goalContributions)
        .insert(
          GoalContributionsCompanion.insert(
            id: id,
            householdId: Value(householdId),
            goalId: goalId,
            amountCents: cents,
            contributedOn: formatDay(on ?? now),
            addedBy: Value(addedBy),
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> removeContribution(String id) async {
    final now = _clock();
    await (_db.update(
      _db.goalContributions,
    )..where((c) => c.id.equals(id))).write(
      GoalContributionsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }

  void _check(String name, int target, int saved, int monthly) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (target <= 0) {
      throw ArgumentError.value(target, 'targetCents', 'must be above zero');
    }
    if (saved < 0 || monthly < 0) {
      throw ArgumentError('amounts must not be negative');
    }
  }
}
