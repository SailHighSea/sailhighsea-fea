import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'sync_backend.dart';

/// A local change waiting to be pushed.
class PendingChange {
  const PendingChange({
    required this.id,
    required this.json,
    required this.summary,
    required this.snapshot,
  });

  final String id;

  /// What is sent to the server (no `updated_at`: the server stamps it).
  final RemoteRow json;

  /// "Lunch, 12.50": shown when the server refuses the change.
  final String summary;

  /// The local row as it was read; compared again before it is marked as pushed so an edit
  /// made while the push was running is not lost.
  final Object snapshot;
}

/// How one local table maps to its server table. Everything is keyed by `id` within a
/// household.
abstract class SyncedTable {
  const SyncedTable();

  String get name;

  /// Local tables that, when they change, may mean there is something to push.
  List<ResultSetImplementation<dynamic, dynamic>> watched(AppDatabase db);

  /// Dirty rows of [householdId], oldest edit first.
  Future<List<PendingChange>> pending(
    AppDatabase db,
    String householdId,
    String userId,
  );

  Future<int> pendingCount(AppDatabase db, String householdId);

  /// Stores rows from the server. A row with a local change still waiting is left alone: the
  /// local change is pushed next and wins (last write wins by arrival at the server).
  /// With [force] the server version replaces local changes too (used after a refusal).
  Future<void> applyRemote(
    AppDatabase db,
    List<RemoteRow> rows, {
    bool force = false,
  });

  /// The push worked: store the server's version and mark the row clean, unless it changed
  /// again in the meantime.
  Future<void> acknowledge(AppDatabase db, PendingChange change, RemoteRow row);

  /// The server refused the change and has no such row: remove it locally.
  Future<void> discard(AppDatabase db, PendingChange change);

  /// Stop retrying a change (the server refused it) without touching its content.
  Future<void> markClean(AppDatabase db, PendingChange change);
}

DateTime parseServerTime(Object? value) =>
    DateTime.parse(value! as String).toLocal();

DateTime? parseServerTimeOrNull(Object? value) =>
    value == null ? null : parseServerTime(value);

String _plainMoney(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

String moneyText(int cents) => _plainMoney(cents);

/// One synced table described by a few functions. Everything else (queries, conflict rules,
/// acknowledging a push) is shared.
class DriftSyncedTable<T extends Table, D extends DataClass>
    extends SyncedTable {
  DriftSyncedTable({
    required this.name,
    required this.table,
    required this.idColumn,
    required this.householdColumn,
    required this.dirtyColumn,
    required this.updatedColumn,
    required this.idOf,
    required this.householdOf,
    required this.dirtyOf,
    required this.toJson,
    required this.summary,
    required this.fromRemote,
    required this.cleanMarker,
    this.onDiscard,
  });

  @override
  final String name;

  final TableInfo<T, D> Function(AppDatabase db) table;
  final GeneratedColumn<String> Function(T t) idColumn;
  final GeneratedColumn<String> Function(T t) householdColumn;
  final GeneratedColumn<bool> Function(T t) dirtyColumn;
  final GeneratedColumn<DateTime> Function(T t) updatedColumn;
  final String Function(D row) idOf;
  final String Function(D row) householdOf;
  final bool Function(D row) dirtyOf;
  final RemoteRow Function(D row, String userId) toJson;
  final String Function(D row) summary;
  final Insertable<D> Function(RemoteRow remote) fromRemote;

  /// A companion that only sets `dirty` to false.
  final Insertable<D> Function() cleanMarker;
  final Future<void> Function(AppDatabase db, PendingChange change)? onDiscard;

  @override
  List<ResultSetImplementation<dynamic, dynamic>> watched(AppDatabase db) => [
    table(db),
  ];

  @override
  Future<List<PendingChange>> pending(
    AppDatabase db,
    String householdId,
    String userId,
  ) async {
    final t = table(db);
    final rows =
        await (db.select(t)
              ..where(
                (r) =>
                    householdColumn(r).equals(householdId) &
                    dirtyColumn(r).equals(true),
              )
              ..orderBy([(r) => OrderingTerm.asc(updatedColumn(r))]))
            .get();
    return [
      for (final r in rows)
        PendingChange(
          id: idOf(r),
          snapshot: r,
          summary: summary(r),
          json: toJson(r, userId),
        ),
    ];
  }

  @override
  Future<int> pendingCount(AppDatabase db, String householdId) async {
    final t = table(db);
    final count = idColumn(t.asDslTable).count();
    final query = db.selectOnly(t)
      ..addColumns([count])
      ..where(
        householdColumn(t.asDslTable).equals(householdId) &
            dirtyColumn(t.asDslTable).equals(true),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  @override
  Future<void> applyRemote(
    AppDatabase db,
    List<RemoteRow> rows, {
    bool force = false,
  }) async {
    if (rows.isEmpty) return;
    final t = table(db);
    final ids = [for (final r in rows) r['id'] as String];
    final local = {
      for (final r in await (db.select(
        t,
      )..where((r) => idColumn(r).isIn(ids))).get())
        idOf(r): r,
    };
    await db.batch((batch) {
      for (final r in rows) {
        final existing = local[r['id']];
        // A waiting change in this household stays. A row of another household (the local
        // defaults seeded before sign-in) is not part of this queue and is replaced.
        if (existing != null &&
            dirtyOf(existing) &&
            householdOf(existing) == r['household_id'] &&
            !force) {
          continue;
        }
        final row = fromRemote(r);
        batch.insert(t, row, onConflict: DoUpdate((_) => row));
      }
    });
  }

  @override
  Future<void> acknowledge(
    AppDatabase db,
    PendingChange change,
    RemoteRow row,
  ) => db.transaction(() async {
    final t = table(db);
    final current = await (db.select(
      t,
    )..where((r) => idColumn(r).equals(change.id))).getSingleOrNull();
    // Edited again while the push ran: leave it dirty so the newer edit is pushed next.
    if (current == null || current != change.snapshot) return;
    await db.into(t).insertOnConflictUpdate(fromRemote(row));
  });

  @override
  Future<void> discard(AppDatabase db, PendingChange change) async {
    final handler = onDiscard;
    if (handler != null) return handler(db, change);
    final t = table(db);
    await (db.delete(t)..where((r) => idColumn(r).equals(change.id))).go();
  }

  @override
  Future<void> markClean(AppDatabase db, PendingChange change) async {
    final t = table(db);
    await (db.update(
      t,
    )..where((r) => idColumn(r).equals(change.id))).write(cleanMarker());
  }
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool _isUserId(String? value) => value != null && _uuid.hasMatch(value);

String? _day(String? value) => value?.substring(0, 10);

class ExpensesSync extends DriftSyncedTable<$ExpensesTable, ExpenseRow> {
  ExpensesSync()
    : super(
        name: 'expenses',
        table: (db) => db.expenses,
        idColumn: (t) => t.id,
        householdColumn: (t) => t.householdId,
        dirtyColumn: (t) => t.dirty,
        updatedColumn: (t) => t.updatedAt,
        idOf: (r) => r.id,
        householdOf: (r) => r.householdId,
        dirtyOf: (r) => r.dirty,
        summary: (e) =>
            '${e.note.isEmpty ? 'Expense' : e.note}, ${_plainMoney(e.amountCents)}',
        toJson: (e, userId) => {
          'id': e.id,
          'household_id': e.householdId,
          'amount_cents': e.amountCents,
          'category_id': e.categoryId,
          'note': e.note,
          'spent_on': e.spentOn,
          // Entries made before sign-in carry a name or nothing; they are the signed-in
          // person's.
          'created_by': _isUserId(e.createdBy) ? e.createdBy : userId,
          'receipt_path': e.receiptPath,
          'deleted_at': e.deletedAt?.toUtc().toIso8601String(),
        },
        fromRemote: (r) => ExpensesCompanion.insert(
          id: r['id'] as String,
          householdId: Value(r['household_id'] as String),
          amountCents: r['amount_cents'] as int,
          categoryId: r['category_id'] as String,
          note: Value(r['note'] as String? ?? ''),
          spentOn: _day(r['spent_on'] as String)!,
          createdBy: Value(r['created_by'] as String?),
          receiptPath: Value(r['receipt_path'] as String?),
          updatedAt: parseServerTime(r['updated_at']),
          deletedAt: Value(parseServerTimeOrNull(r['deleted_at'])),
          dirty: const Value(false),
        ),
        cleanMarker: () => const ExpensesCompanion(dirty: Value(false)),
      );
}

class CategoriesSync extends DriftSyncedTable<$CategoriesTable, CategoryRow> {
  CategoriesSync()
    : super(
        name: 'categories',
        table: (db) => db.categories,
        idColumn: (t) => t.id,
        householdColumn: (t) => t.householdId,
        dirtyColumn: (t) => t.dirty,
        updatedColumn: (t) => t.updatedAt,
        idOf: (r) => r.id,
        householdOf: (r) => r.householdId,
        dirtyOf: (r) => r.dirty,
        summary: (c) => 'Category ${c.name}',
        toJson: (c, userId) => {
          'id': c.id,
          'household_id': c.householdId,
          'name': c.name,
          'color': c.color,
          'icon': c.icon,
          'sort': c.sort,
          'deleted_at': c.deletedAt?.toUtc().toIso8601String(),
        },
        fromRemote: (r) => CategoriesCompanion.insert(
          id: r['id'] as String,
          householdId: Value(r['household_id'] as String),
          name: r['name'] as String,
          color: r['color'] as String,
          icon: Value(r['icon'] as String?),
          sort: Value(r['sort'] as int? ?? 0),
          updatedAt: parseServerTime(r['updated_at']),
          deletedAt: Value(parseServerTimeOrNull(r['deleted_at'])),
          dirty: const Value(false),
        ),
        cleanMarker: () => const CategoriesCompanion(dirty: Value(false)),
        // Expenses may already point at it; keep it hidden rather than break them.
        onDiscard: (db, change) async {
          await (db.update(
            db.categories,
          )..where((c) => c.id.equals(change.id))).write(
            CategoriesCompanion(
              deletedAt: Value(DateTime.now()),
              dirty: const Value(false),
            ),
          );
        },
      );
}

class BudgetsSync extends DriftSyncedTable<$BudgetsTable, BudgetRow> {
  BudgetsSync()
    : super(
        name: 'budgets',
        table: (db) => db.budgets,
        idColumn: (t) => t.id,
        householdColumn: (t) => t.householdId,
        dirtyColumn: (t) => t.dirty,
        updatedColumn: (t) => t.updatedAt,
        idOf: (r) => r.id,
        householdOf: (r) => r.householdId,
        dirtyOf: (r) => r.dirty,
        summary: (b) => 'Budget ${_plainMoney(b.amountCents)}',
        toJson: (b, userId) => {
          'id': b.id,
          'household_id': b.householdId,
          'month': b.month,
          'category_id': b.categoryId,
          'user_id': b.userId,
          'amount_cents': b.amountCents,
          'deleted_at': b.deletedAt?.toUtc().toIso8601String(),
        },
        fromRemote: (r) => BudgetsCompanion.insert(
          id: r['id'] as String,
          householdId: Value(r['household_id'] as String),
          month: _day(r['month'] as String)!,
          categoryId: Value(r['category_id'] as String?),
          userId: Value(r['user_id'] as String?),
          amountCents: r['amount_cents'] as int,
          updatedAt: parseServerTime(r['updated_at']),
          deletedAt: Value(parseServerTimeOrNull(r['deleted_at'])),
          dirty: const Value(false),
        ),
        cleanMarker: () => const BudgetsCompanion(dirty: Value(false)),
      );
}

class GoalsSync extends DriftSyncedTable<$GoalsTable, GoalRow> {
  GoalsSync()
    : super(
        name: 'goals',
        table: (db) => db.goals,
        idColumn: (t) => t.id,
        householdColumn: (t) => t.householdId,
        dirtyColumn: (t) => t.dirty,
        updatedColumn: (t) => t.updatedAt,
        idOf: (r) => r.id,
        householdOf: (r) => r.householdId,
        dirtyOf: (r) => r.dirty,
        summary: (g) => 'Goal ${g.name}',
        toJson: (g, userId) => {
          'id': g.id,
          'household_id': g.householdId,
          'name': g.name,
          'target_cents': g.targetCents,
          'saved_cents': g.savedCents,
          'monthly_cents': g.monthlyCents,
          'due_on': g.dueOn,
          'deleted_at': g.deletedAt?.toUtc().toIso8601String(),
        },
        fromRemote: (r) => GoalsCompanion.insert(
          id: r['id'] as String,
          householdId: Value(r['household_id'] as String),
          name: r['name'] as String,
          targetCents: r['target_cents'] as int,
          savedCents: Value(r['saved_cents'] as int? ?? 0),
          monthlyCents: Value(r['monthly_cents'] as int? ?? 0),
          dueOn: Value(_day(r['due_on'] as String?)),
          updatedAt: parseServerTime(r['updated_at']),
          deletedAt: Value(parseServerTimeOrNull(r['deleted_at'])),
          dirty: const Value(false),
        ),
        cleanMarker: () => const GoalsCompanion(dirty: Value(false)),
      );
}

class GoalContributionsSync
    extends DriftSyncedTable<$GoalContributionsTable, GoalContributionRow> {
  GoalContributionsSync()
    : super(
        name: 'goal_contributions',
        table: (db) => db.goalContributions,
        idColumn: (t) => t.id,
        householdColumn: (t) => t.householdId,
        dirtyColumn: (t) => t.dirty,
        updatedColumn: (t) => t.updatedAt,
        idOf: (r) => r.id,
        householdOf: (r) => r.householdId,
        dirtyOf: (r) => r.dirty,
        summary: (c) => 'Money added to a goal, ${_plainMoney(c.amountCents)}',
        toJson: (c, userId) => {
          'id': c.id,
          'household_id': c.householdId,
          'goal_id': c.goalId,
          'amount_cents': c.amountCents,
          'contributed_on': c.contributedOn,
          'added_by': _isUserId(c.addedBy) ? c.addedBy : userId,
          'deleted_at': c.deletedAt?.toUtc().toIso8601String(),
        },
        fromRemote: (r) => GoalContributionsCompanion.insert(
          id: r['id'] as String,
          householdId: Value(r['household_id'] as String),
          goalId: r['goal_id'] as String,
          amountCents: r['amount_cents'] as int,
          contributedOn: _day(r['contributed_on'] as String)!,
          addedBy: Value(r['added_by'] as String?),
          updatedAt: parseServerTime(r['updated_at']),
          deletedAt: Value(parseServerTimeOrNull(r['deleted_at'])),
          dirty: const Value(false),
        ),
        cleanMarker: () =>
            const GoalContributionsCompanion(dirty: Value(false)),
      );
}

class BillsSync extends DriftSyncedTable<$BillsTable, BillRow> {
  BillsSync()
    : super(
        name: 'bills',
        table: (db) => db.bills,
        idColumn: (t) => t.id,
        householdColumn: (t) => t.householdId,
        dirtyColumn: (t) => t.dirty,
        updatedColumn: (t) => t.updatedAt,
        idOf: (r) => r.id,
        householdOf: (r) => r.householdId,
        dirtyOf: (r) => r.dirty,
        summary: (b) => 'Bill ${b.name}, ${_plainMoney(b.amountCents)}',
        toJson: (b, userId) => {
          'id': b.id,
          'household_id': b.householdId,
          'name': b.name,
          'amount_cents': b.amountCents,
          'due_day': b.dueDay,
          'repeat': b.repeat,
          'next_due_on': b.nextDueOn,
          'last_paid_on': b.lastPaidOn,
          'deleted_at': b.deletedAt?.toUtc().toIso8601String(),
        },
        fromRemote: (r) => BillsCompanion.insert(
          id: r['id'] as String,
          householdId: Value(r['household_id'] as String),
          name: r['name'] as String,
          amountCents: r['amount_cents'] as int,
          dueDay: r['due_day'] as int,
          repeat: Value(r['repeat'] as String? ?? 'monthly'),
          nextDueOn: _day(r['next_due_on'] as String)!,
          lastPaidOn: Value(_day(r['last_paid_on'] as String?)),
          updatedAt: parseServerTime(r['updated_at']),
          deletedAt: Value(parseServerTimeOrNull(r['deleted_at'])),
          dirty: const Value(false),
        ),
        cleanMarker: () => const BillsCompanion(dirty: Value(false)),
      );
}

/// Order matters: categories before the expenses and budgets that point at them, goals
/// before their contributions.
List<SyncedTable> buildSyncedTables() => [
  CategoriesSync(),
  ExpensesSync(),
  BudgetsSync(),
  GoalsSync(),
  GoalContributionsSync(),
  BillsSync(),
];
