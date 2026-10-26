import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../google/google_api.dart';
import 'sheet_layout.dart';

/// Writes this person's own expenses to their own Google Sheet. This app is the only writer of
/// that sheet, so there are no conflicts: a push is "make the sheet say what the database says".
///
/// Idempotent: rows are found by `expense_id`, so pushing twice (or again after a failure half-way)
/// never duplicates a row.
class MemberWriter {
  MemberWriter(
    this._db,
    this._sheets, {
    required this.currencyCode,
    required this.householdId,
    DateTime Function()? clock,
    this.batchSize = 200,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final SheetsApi _sheets;
  final String currencyCode;
  final String householdId;
  final DateTime Function() _clock;
  final int batchSize;

  /// Creates the sheet with its tabs and headers. Returns its id.
  Future<String> createSheet(String ownerName) async {
    final id = await _sheets.createSpreadsheet(
      'FET Family Expenses - ${ownerName.isEmpty ? 'me' : ownerName}',
      Tabs.memberSheetTabs,
    );
    await _sheets.writeRanges(id, {
      '${Tabs.expenses}!A1:K1': [Headers.expenses],
      '${Tabs.categories}!A1:B1': [Headers.categories],
      '${Tabs.suggestions}!A1:I1': [Headers.suggestions],
      '${Tabs.pairing}!A1:F1': [Headers.pairing],
      '${Tabs.meta}!A1:B4': metaRows(0, _clock()),
    });
    return id;
  }

  /// Pushes dirty expenses, the categories, and (through [extra]) other tabs. Returns how many
  /// expense rows were written.
  Future<int> push(String sheetId, {Future<void> Function()? extra}) async {
    final dirty =
        await (_db.select(_db.expenses)..where(
              (e) => e.dirty.equals(true) & e.householdId.equals(householdId),
            ))
            .get();
    var written = 0;
    if (dirty.isNotEmpty) {
      final categoryNames = {
        for (final c in await _db.select(_db.categories).get()) c.id: c.name,
      };
      final existing = await _rowNumbers(sheetId);
      for (var i = 0; i < dirty.length; i += batchSize) {
        final batch = dirty.sublist(i, (i + batchSize).clamp(0, dirty.length));
        final updates = <String, List<List<String>>>{};
        final appends = <List<String>>[];
        for (final e in batch) {
          final row = _toSheet(e, categoryNames).toRow();
          final at = existing[e.id];
          if (at != null) {
            updates['${Tabs.expenses}!A$at:K$at'] = [row];
          } else {
            appends.add(row);
          }
        }
        await _sheets.writeRanges(sheetId, updates);
        await _sheets.appendRows(sheetId, Tabs.expenses, appends);
        // Only rows that did not change meanwhile are marked as pushed.
        for (final e in batch) {
          await (_db.update(_db.expenses)..where(
                (x) => x.id.equals(e.id) & x.updatedAt.equals(e.updatedAt),
              ))
              .write(const ExpensesCompanion(dirty: Value(false)));
        }
        written += batch.length;
      }
    }
    await _writeCategories(sheetId);
    if (extra != null) await extra();
    await bumpRevision(sheetId);
    return written;
  }

  SheetExpense _toSheet(ExpenseRow e, Map<String, String> names) =>
      SheetExpense(
        id: e.id,
        date: e.spentOn,
        cents: e.amountCents,
        currency: currencyCode,
        category: names[e.categoryId] ?? 'Other',
        note: e.note,
        receipt: e.receiptPath ?? '',
        created: e.updatedAt,
        updated: e.updatedAt,
        deleted: e.deletedAt != null,
      );

  Future<Map<String, int>> _rowNumbers(String sheetId) async {
    final rows = await _sheets.read(sheetId, '${Tabs.expenses}!A2:A');
    final map = <String, int>{};
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isNotEmpty) map.putIfAbsent(rows[i][0], () => i + 2);
    }
    return map;
  }

  Future<void> _writeCategories(String sheetId) async {
    final cats =
        await (_db.select(_db.categories)
              ..where((c) => c.deletedAt.isNull())
              ..orderBy([(c) => OrderingTerm.asc(c.sort)]))
            .get();
    await _sheets.clear(sheetId, '${Tabs.categories}!A2:B');
    await _sheets.writeRanges(sheetId, {
      if (cats.isNotEmpty)
        '${Tabs.categories}!A2:B${cats.length + 1}': [
          for (final c in cats) [c.id, c.name],
        ],
    });
  }

  /// Rewrites the Meta tab with revision + 1, so a reader can tell the sheet changed.
  Future<void> bumpRevision(String sheetId) async {
    final meta = await _sheets.read(sheetId, '${Tabs.meta}!A1:B4');
    await _sheets.writeRanges(sheetId, {
      '${Tabs.meta}!A1:B4': metaRows(revisionOf(meta) + 1, _clock()),
    });
  }
}
