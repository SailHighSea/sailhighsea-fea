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
}

DateTime _parseTime(Object? value) =>
    DateTime.parse(value! as String).toLocal();

DateTime? _parseTimeOrNull(Object? value) =>
    value == null ? null : _parseTime(value);

String _plainMoney(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

class ExpensesSync extends SyncedTable {
  const ExpensesSync();

  @override
  String get name => 'expenses';

  @override
  Future<List<PendingChange>> pending(
    AppDatabase db,
    String householdId,
    String userId,
  ) async {
    final rows =
        await (db.select(db.expenses)
              ..where(
                (e) => e.householdId.equals(householdId) & e.dirty.equals(true),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.updatedAt)]))
            .get();
    return [
      for (final e in rows)
        PendingChange(
          id: e.id,
          snapshot: e,
          summary:
              '${e.note.isEmpty ? 'Expense' : e.note}, ${_plainMoney(e.amountCents)}',
          json: {
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
        ),
    ];
  }

  @override
  Future<int> pendingCount(AppDatabase db, String householdId) async {
    final count = db.expenses.id.count();
    final query = db.selectOnly(db.expenses)
      ..addColumns([count])
      ..where(
        db.expenses.householdId.equals(householdId) &
            db.expenses.dirty.equals(true),
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
    final ids = [for (final r in rows) r['id'] as String];
    final local = {
      for (final e in await (db.select(
        db.expenses,
      )..where((e) => e.id.isIn(ids))).get())
        e.id: e,
    };
    await db.batch((batch) {
      for (final r in rows) {
        final existing = local[r['id']];
        // A waiting change in this household stays. A row of another household (the local
        // defaults seeded before sign-in) is not part of this queue and is replaced.
        if (existing != null &&
            existing.dirty &&
            existing.householdId == r['household_id'] &&
            !force) {
          continue;
        }
        final row = _companion(r);
        batch.insert(db.expenses, row, onConflict: DoUpdate((_) => row));
      }
    });
  }

  ExpensesCompanion _companion(RemoteRow r) => ExpensesCompanion.insert(
    id: r['id'] as String,
    householdId: Value(r['household_id'] as String),
    amountCents: r['amount_cents'] as int,
    categoryId: r['category_id'] as String,
    note: Value(r['note'] as String? ?? ''),
    spentOn: (r['spent_on'] as String).substring(0, 10),
    createdBy: Value(r['created_by'] as String?),
    receiptPath: Value(r['receipt_path'] as String?),
    updatedAt: _parseTime(r['updated_at']),
    deletedAt: Value(_parseTimeOrNull(r['deleted_at'])),
    dirty: const Value(false),
  );

  @override
  Future<void> acknowledge(
    AppDatabase db,
    PendingChange change,
    RemoteRow row,
  ) => db.transaction(() async {
    final current = await (db.select(
      db.expenses,
    )..where((e) => e.id.equals(change.id))).getSingleOrNull();
    // Edited again while the push ran: leave it dirty so the newer edit is pushed next.
    if (current == null || current != change.snapshot) return;
    await db.into(db.expenses).insertOnConflictUpdate(_companion(row));
  });

  @override
  Future<void> discard(AppDatabase db, PendingChange change) =>
      (db.delete(db.expenses)..where((e) => e.id.equals(change.id))).go();
}

class CategoriesSync extends SyncedTable {
  const CategoriesSync();

  @override
  String get name => 'categories';

  @override
  Future<List<PendingChange>> pending(
    AppDatabase db,
    String householdId,
    String userId,
  ) async {
    final rows =
        await (db.select(db.categories)
              ..where(
                (c) => c.householdId.equals(householdId) & c.dirty.equals(true),
              )
              ..orderBy([(c) => OrderingTerm.asc(c.updatedAt)]))
            .get();
    return [
      for (final c in rows)
        PendingChange(
          id: c.id,
          snapshot: c,
          summary: 'Category ${c.name}',
          json: {
            'id': c.id,
            'household_id': c.householdId,
            'name': c.name,
            'color': c.color,
            'icon': c.icon,
            'sort': c.sort,
            'deleted_at': c.deletedAt?.toUtc().toIso8601String(),
          },
        ),
    ];
  }

  @override
  Future<int> pendingCount(AppDatabase db, String householdId) async {
    final count = db.categories.id.count();
    final query = db.selectOnly(db.categories)
      ..addColumns([count])
      ..where(
        db.categories.householdId.equals(householdId) &
            db.categories.dirty.equals(true),
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
    final ids = [for (final r in rows) r['id'] as String];
    final local = {
      for (final c in await (db.select(
        db.categories,
      )..where((c) => c.id.isIn(ids))).get())
        c.id: c,
    };
    await db.batch((batch) {
      for (final r in rows) {
        final existing = local[r['id']];
        // A waiting change in this household stays. A row of another household (the local
        // defaults seeded before sign-in) is not part of this queue and is replaced.
        if (existing != null &&
            existing.dirty &&
            existing.householdId == r['household_id'] &&
            !force) {
          continue;
        }
        final row = _companion(r);
        batch.insert(db.categories, row, onConflict: DoUpdate((_) => row));
      }
    });
  }

  CategoriesCompanion _companion(RemoteRow r) => CategoriesCompanion.insert(
    id: r['id'] as String,
    householdId: Value(r['household_id'] as String),
    name: r['name'] as String,
    color: r['color'] as String,
    icon: Value(r['icon'] as String?),
    sort: Value(r['sort'] as int? ?? 0),
    updatedAt: _parseTime(r['updated_at']),
    deletedAt: Value(_parseTimeOrNull(r['deleted_at'])),
    dirty: const Value(false),
  );

  @override
  Future<void> acknowledge(
    AppDatabase db,
    PendingChange change,
    RemoteRow row,
  ) => db.transaction(() async {
    final current = await (db.select(
      db.categories,
    )..where((c) => c.id.equals(change.id))).getSingleOrNull();
    if (current == null || current != change.snapshot) return;
    await db.into(db.categories).insertOnConflictUpdate(_companion(row));
  });

  @override
  Future<void> discard(AppDatabase db, PendingChange change) async {
    // Expenses may already point at it; keep it hidden rather than break them.
    await (db.update(
      db.categories,
    )..where((c) => c.id.equals(change.id))).write(
      CategoriesCompanion(
        deletedAt: Value(DateTime.now()),
        dirty: const Value(false),
      ),
    );
  }
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool _isUserId(String? value) => value != null && _uuid.hasMatch(value);

/// Order matters: categories first, because expenses point at them.
const syncedTables = <SyncedTable>[CategoriesSync(), ExpensesSync()];
