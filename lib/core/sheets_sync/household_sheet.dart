import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../google/google_api.dart';
import 'sheet_layout.dart';

/// The organiser's household sheet: who is paired, and the budgets, goals, bills and categories the
/// whole household uses. Members' apps read it; only the organiser's app writes it.
class HouseholdWriter {
  HouseholdWriter(this._db, this._sheets, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final SheetsApi _sheets;
  final DateTime Function() _clock;

  Future<String> create(String householdName) async {
    final id = await _sheets.createSpreadsheet(
      'Family Household - ${householdName.isEmpty ? 'family' : householdName}',
      Tabs.householdSheetTabs,
    );
    await _sheets.writeRanges(id, {
      '${Tabs.members}!A1:E1': [Headers.members],
      '${Tabs.budgets}!A1:C1': [Headers.record],
      '${Tabs.goals}!A1:C1': [Headers.record],
      '${Tabs.bills}!A1:C1': [Headers.record],
      '${Tabs.categories}!A1:C1': [Headers.record],
      '${Tabs.decisions}!A1:D1': [Headers.decisions],
      '${Tabs.meta}!A1:B4': metaRows(0, _clock()),
    });
    return id;
  }

  /// Everything the sheet will say, as rows per tab.
  Future<Map<String, List<List<String>>>> snapshot() async {
    final pairs = await _db.select(_db.sheetPairs).get();
    final budgets = await (_db.select(
      _db.budgets,
    )..where((b) => b.deletedAt.isNull() & b.userId.isNull())).get();
    final goals = await (_db.select(
      _db.goals,
    )..where((g) => g.deletedAt.isNull())).get();
    final bills = await (_db.select(
      _db.bills,
    )..where((b) => b.deletedAt.isNull())).get();
    final categories = await (_db.select(
      _db.categories,
    )..where((c) => c.deletedAt.isNull())).get();
    final suggestions = await (_db.select(
      _db.suggestions,
    )..where((s) => s.status.isIn(const ['approved', 'declined']))).get();
    List<List<String>> sorted(List<List<String>> rows) =>
        rows..sort((a, b) => a[0].compareTo(b[0]));
    return {
      Tabs.members: sorted([
        for (final p in pairs)
          [
            p.memberEmail,
            p.name,
            p.sheetId,
            p.status,
            p.pairedAt.toUtc().toIso8601String(),
          ],
      ]),
      Tabs.budgets: sorted([
        for (final b in budgets) recordRow(b.id, b.updatedAt, b.toJson()),
      ]),
      Tabs.goals: sorted([
        for (final g in goals) recordRow(g.id, g.updatedAt, g.toJson()),
      ]),
      Tabs.bills: sorted([
        for (final b in bills) recordRow(b.id, b.updatedAt, b.toJson()),
      ]),
      Tabs.categories: sorted([
        for (final c in categories) recordRow(c.id, c.updatedAt, c.toJson()),
      ]),
      Tabs.decisions: sorted([
        for (final s in suggestions)
          [
            s.id,
            s.memberEmail,
            s.status,
            s.updatedAt.toUtc().toIso8601String(),
          ],
      ]),
    };
  }

  static String digest(Map<String, List<List<String>>> snap) =>
      sha256.convert(utf8.encode(jsonEncode(snap))).toString();

  /// Writes the household sheet when anything changed since [lastDigest]. Returns the new digest
  /// (or [lastDigest] when nothing was written).
  Future<String> push(
    String sheetId, {
    required String lastDigest,
    bool force = false,
  }) async {
    final snap = await snapshot();
    final d = digest(snap);
    if (!force && d == lastDigest) return lastDigest;
    const widths = {
      Tabs.members: 'E',
      Tabs.budgets: 'C',
      Tabs.goals: 'C',
      Tabs.bills: 'C',
      Tabs.categories: 'C',
      Tabs.decisions: 'D',
    };
    for (final e in snap.entries) {
      final w = widths[e.key]!;
      await _sheets.clear(sheetId, '${e.key}!A2:$w');
      if (e.value.isNotEmpty) {
        await _sheets.writeRanges(sheetId, {
          '${e.key}!A2:$w${e.value.length + 1}': e.value,
        });
      }
    }
    final meta = await _sheets.read(sheetId, '${Tabs.meta}!A1:B4');
    await _sheets.writeRanges(sheetId, {
      '${Tabs.meta}!A1:B4': metaRows(revisionOf(meta) + 1, _clock()),
    });
    return d;
  }
}

/// A member's app keeping a read-only copy of the household sheet.
class HouseholdReader {
  HouseholdReader(this._db, this._sheets);

  final AppDatabase _db;
  final SheetsApi _sheets;

  /// Replaces the local budgets, goals, bills and household categories with the sheet's, and
  /// applies the organiser's decisions on this member's suggestions. Returns the sheet's revision.
  Future<int> pull(String sheetId, {required int lastRevision}) async {
    final revision = revisionOf(
      await _sheets.read(sheetId, '${Tabs.meta}!A1:B4'),
    );
    if (revision == lastRevision && revision != 0) return revision;

    List<Map<String, Object?>> records(List<List<String>> rows) => [
      for (final r in rows)
        if (r.length >= 3)
          if (_decode(r[2]) case final Map<String, Object?> m) m,
    ];
    final budgets = records(
      await _sheets.read(sheetId, '${Tabs.budgets}!A2:C'),
    );
    final goals = records(await _sheets.read(sheetId, '${Tabs.goals}!A2:C'));
    final bills = records(await _sheets.read(sheetId, '${Tabs.bills}!A2:C'));
    final categories = records(
      await _sheets.read(sheetId, '${Tabs.categories}!A2:C'),
    );
    final decisions = await _sheets.read(sheetId, '${Tabs.decisions}!A2:D');

    await _db.transaction(() async {
      await _replace<BudgetRow>(
        _db.budgets,
        budgets,
        BudgetRow.fromJson,
        (r) => r.id,
      );
      await _replace<GoalRow>(_db.goals, goals, GoalRow.fromJson, (r) => r.id);
      await _replace<BillRow>(_db.bills, bills, BillRow.fromJson, (r) => r.id);
      for (final c in categories) {
        final row = CategoryRow.fromJson(c);
        await _db
            .into(_db.categories)
            .insertOnConflictUpdate(row.copyWith(dirty: false));
      }
      for (final d in decisions) {
        if (d.length < 3) continue;
        await (_db.update(
          _db.suggestions,
        )..where((s) => s.id.equals(d[0]) & s.status.equals('pending'))).write(
          SuggestionsCompanion(
            status: Value(d[2]),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
    return revision;
  }

  Map<String, Object?>? _decode(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Upserts the sheet's rows (never dirty: members do not push these) and soft-deletes local rows
  /// the sheet no longer has.
  Future<void> _replace<R extends DataClass>(
    TableInfo<Table, R> table,
    List<Map<String, Object?>> json,
    R Function(Map<String, dynamic>) fromJson,
    String Function(R) idOf,
  ) async {
    final incoming = <String>{};
    for (final j in json) {
      final row = fromJson(Map<String, dynamic>.from(j));
      incoming.add(idOf(row));
      await _db.into(table).insertOnConflictUpdate(_clean(row));
    }
    final now = DateTime.now();
    final all = await _db.select(table).get();
    for (final r in all) {
      if (!incoming.contains(idOf(r))) {
        await _db.customUpdate(
          'UPDATE ${table.actualTableName} SET deleted_at = ?, dirty = 0 WHERE id = ? AND deleted_at IS NULL',
          variables: [Variable<DateTime>(now), Variable<String>(idOf(r))],
          updates: {table},
        );
      }
    }
  }

  Insertable<R> _clean<R extends DataClass>(R row) {
    final dynamic d = row;
    // Rows from the sheet are the organiser's copy: not dirty, so nothing here is ever pushed.
    return d.copyWith(dirty: false) as Insertable<R>;
  }
}
