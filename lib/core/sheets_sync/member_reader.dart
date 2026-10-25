import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../google/google_api.dart';
import '../../features/expenses/data/category_repository.dart';
import 'sheet_layout.dart';

/// Prefix of the `created_by` value for expenses imported from a member's sheet.
const memberUserPrefix = 'g:';
String memberUserId(String email) => '$memberUserPrefix${email.toLowerCase()}';

enum PullOutcome { unchanged, imported, accessRemoved }

class PullResult {
  const PullResult(
    this.outcome, {
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
  });
  final PullOutcome outcome;
  final int added;
  final int updated;
  final int removed;
}

/// The organiser's app reading one paired member's sheet and merging it into the local database.
/// The rows belong to the member (`created_by`), are never marked dirty and are never pushed, and
/// the UI treats them as read-only.
class MemberReader {
  MemberReader(
    this._db,
    this._sheets,
    this._categories, {
    required this.householdId,
    this.pageSize = 500,
  });

  final AppDatabase _db;
  final SheetsApi _sheets;
  final CategoryRepository _categories;
  final String householdId;
  final int pageSize;

  Future<PullResult> pull(SheetPairRow pair, {bool force = false}) async {
    if (pair.status == 'unpaired') {
      return const PullResult(PullOutcome.unchanged);
    }
    final String revision;
    try {
      revision =
          '${revisionOf(await _sheets.read(pair.sheetId, '${Tabs.meta}!A1:B4'))}';
    } on SheetAccessError {
      await _setStatus(pair, 'accessRemoved');
      return const PullResult(PullOutcome.accessRemoved);
    }
    if (!force &&
        pair.status == 'active' &&
        revision == pair.lastRevision &&
        revision != '0') {
      await _touch(pair, revision);
      return const PullResult(PullOutcome.unchanged);
    }
    var added = 0, updated = 0, removed = 0;
    try {
      final categoryIds = <String, String>{};
      Future<String> categoryFor(String name) async {
        final key = name.trim().toLowerCase();
        return categoryIds[key] ??= (name.trim().isEmpty
            ? otherCategoryId
            : (await _categories.add(name)).id);
      }

      for (var start = 2; ; start += pageSize) {
        final rows = await _sheets.read(
          pair.sheetId,
          '${Tabs.expenses}!A$start:K${start + pageSize - 1}',
        );
        for (final raw in rows) {
          final e = SheetExpense.fromRow(raw);
          if (e == null) continue;
          final existing = await (_db.select(
            _db.expenses,
          )..where((x) => x.id.equals(e.id))).getSingleOrNull();
          // Never overwrite an expense that belongs to someone else with a clashing id.
          if (existing != null &&
              existing.createdBy != memberUserId(pair.memberEmail)) {
            continue;
          }
          if (existing != null && !e.updated.isAfter(existing.updatedAt)) {
            continue;
          }
          final categoryId = await categoryFor(e.category);
          await _db
              .into(_db.expenses)
              .insertOnConflictUpdate(
                ExpensesCompanion(
                  id: Value(e.id),
                  householdId: Value(householdId),
                  amountCents: Value(e.cents),
                  categoryId: Value(categoryId),
                  note: Value(e.note),
                  spentOn: Value(e.date),
                  createdBy: Value(memberUserId(pair.memberEmail)),
                  receiptPath: Value(e.receipt.isEmpty ? null : e.receipt),
                  updatedAt: Value(e.updated),
                  deletedAt: Value(e.deleted ? e.updated : null),
                  dirty: const Value(false),
                ),
              );
          if (existing == null) {
            added++;
          } else if (e.deleted) {
            removed++;
          } else {
            updated++;
          }
        }
        if (rows.length < pageSize) break;
      }
    } on SheetAccessError {
      await _setStatus(pair, 'accessRemoved');
      return const PullResult(PullOutcome.accessRemoved);
    }
    await _touch(pair, revision);
    return PullResult(
      PullOutcome.imported,
      added: added,
      updated: updated,
      removed: removed,
    );
  }

  Future<void> _touch(SheetPairRow pair, String revision) =>
      (_db.update(
        _db.sheetPairs,
      )..where((p) => p.memberEmail.equals(pair.memberEmail))).write(
        SheetPairsCompanion(
          status: const Value('active'),
          lastRevision: Value(revision),
          lastSyncedAt: Value(DateTime.now()),
        ),
      );

  Future<void> _setStatus(SheetPairRow pair, String status) =>
      (_db.update(_db.sheetPairs)
            ..where((p) => p.memberEmail.equals(pair.memberEmail)))
          .write(SheetPairsCompanion(status: Value(status)));
}
