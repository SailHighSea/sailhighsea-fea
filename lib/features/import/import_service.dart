import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/ids.dart';
import '../../core/db/tables.dart' show localHouseholdId;
import '../../core/google/google_api.dart';
import '../../core/money/currency.dart';
import 'import_parser.dart';

/// What an import would do, before anything is saved.
class ImportPreview {
  const ImportPreview({
    required this.ready,
    required this.duplicates,
    required this.problems,
  });

  /// New expenses.
  final List<ImportRow> ready;

  /// Rows already in the app (same date, amount and description): skipped, so importing the same
  /// sheet twice does not double anything.
  final List<ImportRow> duplicates;
  final List<ImportProblem> problems;

  int get totalCents => ready.fold(0, (a, r) => a + r.cents);
}

class ImportService {
  ImportService(
    this._db, {
    required this.currency,
    required this.today,
    this.householdId = localHouseholdId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final CurrencyInfo currency;
  final DateTime today;
  final String householdId;
  final DateTime Function() _clock;

  /// From the text of a CSV file.
  Future<ImportPreview> previewCsv(String text, {String decimal = '.'}) =>
      previewRows(parseCsv(text), decimal: decimal);

  /// From the rows of a Google Sheet's first tab.
  Future<ImportPreview> previewSheet(SheetsApi sheets, String sheetId) async {
    final tab = await sheets.firstTabTitle(sheetId);
    final rows = await sheets.read(
      sheetId,
      "'${tab.replaceAll("'", "''")}'!A1:Z5000",
    );
    return previewRows(rows);
  }

  Future<ImportPreview> previewRows(
    List<List<String>> rows, {
    String decimal = '.',
  }) async {
    final parsed = parseImportRows(
      rows,
      currency: currency,
      today: today,
      decimal: decimal,
    );
    final existing = <String, int>{};
    for (final e
        in await (_db.select(_db.expenses)..where(
              (x) => x.deletedAt.isNull() & x.householdId.equals(householdId),
            ))
            .get()) {
      final key =
          '${e.spentOn}|${e.amountCents}|${e.note.trim().toLowerCase()}';
      existing[key] = (existing[key] ?? 0) + 1;
    }
    final ready = <ImportRow>[];
    final dupes = <ImportRow>[];
    for (final r in parsed.rows) {
      final left = existing[r.key] ?? 0;
      if (left > 0) {
        existing[r.key] = left - 1;
        dupes.add(r);
      } else {
        ready.add(r);
      }
    }
    return ImportPreview(
      ready: ready,
      duplicates: dupes,
      problems: parsed.problems,
    );
  }

  /// Saves the ready rows as expenses in "Other" (they can be recategorised afterwards).
  Future<int> import(ImportPreview preview, {String? createdBy}) async {
    final now = _clock();
    await _db.batch((b) {
      b.insertAll(_db.expenses, [
        for (final r in preview.ready)
          ExpensesCompanion.insert(
            id: newId(),
            householdId: Value(householdId),
            amountCents: r.cents,
            categoryId: otherCategoryId,
            note: Value(r.description),
            spentOn: r.date,
            createdBy: Value(createdBy ?? 'You'),
            updatedAt: now,
          ),
      ]);
    });
    return preview.ready.length;
  }
}

/// Opens a file chooser and returns the chosen file's text; null when cancelled. Hardware-style
/// platform code, so it is behind a provider (tests replace it).
typedef ImportFilePicker = Future<String?> Function();

final importFilePickerProvider = Provider<ImportFilePicker>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Spreadsheet (CSV)',
          extensions: ['csv', 'tsv', 'txt'],
          mimeTypes: ['text/csv', 'text/plain', 'text/tab-separated-values'],
        ),
      ],
    );
    return file?.readAsString();
  },
);
