import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/ids.dart';
import '../../core/db/tables.dart' show localHouseholdId;
import '../../core/google/google_api.dart';
import '../../core/money/currency.dart';
import 'category_guess.dart';
import 'import_parser.dart';

/// What an import would do, before anything is saved.
class ImportPreview {
  const ImportPreview({
    required this.ready,
    required this.duplicates,
    required this.problems,
    this.incomeSkipped = 0,
  });

  /// New expenses.
  final List<ImportRow> ready;

  /// Rows already in the app (same date, amount and description): skipped, so importing the same
  /// sheet twice does not double anything.
  final List<ImportRow> duplicates;
  final List<ImportProblem> problems;

  /// Money in (credits, deposits) that was left out because it is not an expense.
  final int incomeSkipped;

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
    CurrencyInfo? currency,
    int extraIncome = 0,
  }) async {
    final parsed = parseImportRows(
      rows,
      currency: currency ?? this.currency,
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
      incomeSkipped: parsed.incomeSkipped + extraIncome,
    );
  }

  /// Decides categories from past expenses and keywords; `null` for a row means "ask".
  Future<CategoryGuesser> loadGuesser() async {
    final categories =
        await (_db.select(_db.categories)..where(
              (c) => c.deletedAt.isNull() & c.householdId.equals(householdId),
            ))
            .get();
    final expenses =
        await (_db.select(_db.expenses)..where(
              (e) => e.deletedAt.isNull() & e.householdId.equals(householdId),
            ))
            .get();
    return CategoryGuesser(
      categories: categories,
      history: CategoryGuesser.historyFrom(expenses),
    );
  }

  /// Saves the chosen rows with their categories.
  Future<int> importDrafts(
    List<ImportDraft> drafts, {
    String? createdBy,
  }) async {
    final chosen = drafts.where((d) => d.include).toList();
    final now = _clock();
    await _db.batch((b) {
      b.insertAll(_db.expenses, [
        for (final d in chosen)
          ExpensesCompanion.insert(
            id: newId(),
            householdId: Value(householdId),
            amountCents: d.row.cents,
            categoryId: d.categoryId ?? otherCategoryId,
            note: Value(d.row.description),
            spentOn: d.row.date,
            createdBy: Value(createdBy ?? 'You'),
            updatedAt: now,
          ),
      ]);
    });
    return chosen.length;
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

/// A file the person chose.
class PickedImport {
  const PickedImport(this.name, this.bytes, {this.path});
  PickedImport.text(this.name, String text)
    : bytes = Uint8List.fromList(utf8.encode(text)),
      path = null;

  /// Where the file is on disk (needed to read a picture).
  final String? path;

  final String name;
  final Uint8List bytes;

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

/// Opens a file chooser (CSV, Excel, PDF); null when cancelled. Platform code, so it is behind a
/// provider (tests replace it).
typedef ImportFilePicker = Future<PickedImport?> Function();

final importFilePickerProvider = Provider<ImportFilePicker>(
  (ref) => () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Spreadsheet or statement',
          extensions: [
            'csv',
            'tsv',
            'txt',
            'xlsx',
            'pdf',
            'png',
            'jpg',
            'jpeg',
            'webp',
          ],
          mimeTypes: [
            'text/csv',
            'text/plain',
            'text/tab-separated-values',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'application/pdf',
            'image/png',
            'image/jpeg',
            'image/webp',
          ],
        ),
      ],
    );
    return file == null
        ? null
        : PickedImport(file.name, await file.readAsBytes(), path: file.path);
  },
);

/// One row in the import table: whether to import it and which category it gets.
class ImportDraft {
  ImportDraft(
    this.row, {
    this.categoryId,
    this.include = true,
    this.reason = 'none',
  });

  final ImportRow row;
  String? categoryId;
  bool include;

  /// How the category was decided: `history`, `keyword`, `none` (ask) or `you`.
  String reason;
}
