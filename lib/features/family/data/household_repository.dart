import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables.dart';
import 'household_remote.dart';

/// The local copy of the household and its members. The UI reads this, so names and roles
/// work offline; [replaceFromRemote] refreshes it from the server (Phase 4 keeps it live).
class HouseholdRepository {
  HouseholdRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// The household [userId] is a member of, if any.
  Stream<HouseholdRow?> watchMine(String userId) {
    final query = _db.select(_db.households).join([
      innerJoin(
        _db.members,
        _db.members.householdId.equalsExp(_db.households.id),
      ),
    ])..where(_db.members.userId.equals(userId));
    return query.watch().map(
      (rows) => rows.isEmpty ? null : rows.first.readTable(_db.households),
    );
  }

  /// [userId]'s own membership row.
  Stream<MemberRow?> watchMember(String userId) => (_db.select(
    _db.members,
  )..where((m) => m.userId.equals(userId))).watchSingleOrNull();

  /// Members of [householdId], owner first, then by join date.
  Stream<List<MemberRow>> watchMembers(String householdId) {
    final query = _db.select(_db.members)
      ..where((m) => m.householdId.equals(householdId))
      ..orderBy([(m) => OrderingTerm.asc(m.joinedAt)]);
    return query.watch().map(
      (rows) => [
        ...rows.where((m) => m.role == 'owner'),
        ...rows.where((m) => m.role != 'owner'),
      ],
    );
  }

  /// Makes the local copy match the server's answer for this household.
  Future<void> replaceFromRemote(RemoteHousehold remote) =>
      _db.transaction(() async {
        final now = _clock();
        await _db
            .into(_db.households)
            .insertOnConflictUpdate(
              HouseholdsCompanion.insert(
                id: remote.id,
                name: remote.name,
                currency: Value(remote.currency),
                ownerId: remote.ownerId,
                updatedAt: now,
              ),
            );
        await (_db.delete(_db.members)..where(
              (m) =>
                  m.householdId.equals(remote.id) &
                  m.userId.isNotIn([for (final r in remote.members) r.userId]),
            ))
            .go();
        for (final m in remote.members) {
          await _db
              .into(_db.members)
              .insertOnConflictUpdate(
                MembersCompanion.insert(
                  householdId: remote.id,
                  userId: m.userId,
                  role: m.role.dbValue,
                  displayName: m.displayName,
                  joinedAt: m.joinedAt,
                  visibility: Value(m.visibility.dbValue),
                ),
              );
        }
      });

  /// An own-only member must not keep other people's expenses: they may have been pulled
  /// before the setting changed. Removes every expense of [householdId] that someone else
  /// added (the server no longer sends them either).
  Future<void> purgeOthersExpenses({
    required String householdId,
    required String userId,
  }) async {
    await (_db.delete(_db.expenses)..where(
          (e) =>
              e.householdId.equals(householdId) &
              e.createdBy.isNotNull() &
              e.createdBy.isNotIn([userId, 'You']),
        ))
        .go();
  }

  /// Forgets a household (the person left, was removed, or it was deleted).
  Future<void> forget(String householdId) => _db.transaction(() async {
    await (_db.delete(
      _db.members,
    )..where((m) => m.householdId.equals(householdId))).go();
    await (_db.delete(
      _db.households,
    )..where((h) => h.id.equals(householdId))).go();
  });

  /// Moves what was entered before sign-in into the new household so nothing is lost.
  ///
  /// [everything] is true when the person created the household: all local categories and
  /// expenses become theirs and are marked dirty so sync pushes them. When they joined an
  /// existing household instead, only the default categories are re-keyed (their ids match
  /// the server's); expenses and custom categories stay on the device under `local`.
  Future<void> adoptLocalData({
    required String householdId,
    required String userId,
    required bool everything,
  }) => _db.transaction(() async {
    final now = _clock();
    if (everything) {
      await (_db.update(
        _db.categories,
      )..where((c) => c.householdId.equals(localHouseholdId))).write(
        CategoriesCompanion(
          householdId: Value(householdId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await (_db.update(
        _db.expenses,
      )..where((e) => e.householdId.equals(localHouseholdId))).write(
        ExpensesCompanion(
          householdId: Value(householdId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      // Budgets, goals and bills set up before sign-in come along too.
      await (_db.update(
        _db.budgets,
      )..where((b) => b.householdId.equals(localHouseholdId))).write(
        BudgetsCompanion(
          householdId: Value(householdId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await (_db.update(
        _db.goals,
      )..where((g) => g.householdId.equals(localHouseholdId))).write(
        GoalsCompanion(
          householdId: Value(householdId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await (_db.update(
        _db.goalContributions,
      )..where((c) => c.householdId.equals(localHouseholdId))).write(
        GoalContributionsCompanion(
          householdId: Value(householdId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await (_db.update(
        _db.bills,
      )..where((b) => b.householdId.equals(localHouseholdId))).write(
        BillsCompanion(
          householdId: Value(householdId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
    } else {
      await (_db.update(_db.categories)..where(
            (c) =>
                c.householdId.equals(localHouseholdId) & c.id.like('default-%'),
          ))
          .write(CategoriesCompanion(householdId: Value(householdId)));
    }
    // Entries made before there was an account were stored as "You".
    await (_db.update(_db.expenses)..where(
          (e) =>
              e.householdId.equals(householdId) &
              (e.createdBy.isNull() | e.createdBy.equals('You')),
        ))
        .write(ExpensesCompanion(createdBy: Value(userId)));
    await (_db.update(_db.goalContributions)..where(
          (c) =>
              c.householdId.equals(householdId) &
              (c.addedBy.isNull() | c.addedBy.equals('You')),
        ))
        .write(GoalContributionsCompanion(addedBy: Value(userId)));
  });
}
