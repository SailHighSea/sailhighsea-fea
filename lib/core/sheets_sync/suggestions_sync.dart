import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../google/google_api.dart';
import 'sheet_layout.dart';

/// Suggestions travel in the member's own sheet (`Suggestions` tab). Members write them; the
/// organiser's app reads them. Decisions travel back in the household sheet (`Decisions` tab).
class SuggestionsSync {
  SuggestionsSync(this._db, this._sheets);

  final AppDatabase _db;
  final SheetsApi _sheets;

  /// Member: rewrite the tab from the local suggestions.
  Future<void> pushOwn(String sheetId, String memberEmail) async {
    final mine =
        await (_db.select(_db.suggestions)
              ..where((s) => s.memberEmail.equals(memberEmail))
              ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]))
            .get();
    await _sheets.clear(sheetId, '${Tabs.suggestions}!A2:I');
    if (mine.isEmpty) return;
    await _sheets.writeRanges(sheetId, {
      '${Tabs.suggestions}!A2:I${mine.length + 1}': [
        for (final s in mine)
          [
            s.id,
            s.kind,
            s.action,
            s.targetId ?? '',
            s.payloadJson,
            s.note,
            s.status,
            s.createdAt.toUtc().toIso8601String(),
            s.updatedAt.toUtc().toIso8601String(),
          ],
      ],
    });
  }

  /// Organiser: new suggestions from a member's sheet. A suggestion already known keeps its local
  /// status (the organiser's decision wins over whatever the member's sheet says).
  Future<int> pullFrom(String sheetId, String memberEmail) async {
    final rows = await _sheets.read(sheetId, '${Tabs.suggestions}!A2:I');
    var added = 0;
    for (final r in rows) {
      if (r.length < 5 || r[0].isEmpty) continue;
      if (!const ['budget', 'goal', 'bill'].contains(r[1]) ||
          !const ['add', 'change'].contains(r[2])) {
        continue;
      }
      final exists = await (_db.select(
        _db.suggestions,
      )..where((s) => s.id.equals(r[0]))).getSingleOrNull();
      if (exists != null) continue;
      final created = r.length > 7 ? DateTime.tryParse(r[7]) : null;
      await _db
          .into(_db.suggestions)
          .insert(
            SuggestionsCompanion.insert(
              id: r[0],
              memberEmail: memberEmail,
              kind: r[1],
              action: r[2],
              targetId: Value(r[3].isEmpty ? null : r[3]),
              payloadJson: r[4],
              note: Value(r.length > 5 ? r[5] : ''),
              createdAt: created ?? DateTime.now(),
              updatedAt: created ?? DateTime.now(),
            ),
          );
      added++;
    }
    return added;
  }
}
