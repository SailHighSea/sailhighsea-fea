import '../../core/money/currency.dart';
import '../../core/money/money_input.dart';

/// One expense read from a spreadsheet row.
class ImportRow {
  const ImportRow({
    required this.line,
    required this.date,
    required this.description,
    required this.cents,
  });

  /// Line number in the source (1 is the first line, the header if there is one).
  final int line;

  /// `2026-10-23`.
  final String date;
  final String description;
  final int cents;

  /// Used to spot rows that are already in the app.
  String get key => '$date|$cents|${description.trim().toLowerCase()}';
}

class ImportProblem {
  const ImportProblem(this.line, this.message);
  final int line;
  final String message;
}

class ImportParse {
  const ImportParse(this.rows, this.problems);
  final List<ImportRow> rows;
  final List<ImportProblem> problems;
}

/// Splits CSV (RFC 4180: quotes, doubled quotes, line breaks inside quotes). The delimiter is
/// found from the first line: comma, semicolon or tab.
List<List<String>> parseCsv(String text) {
  var t = text;
  if (t.startsWith('﻿')) t = t.substring(1);
  final firstLine = t.split(RegExp(r'\r?\n')).first;
  final delimiter = [',', ';', '\t']
      .map((d) => (d, d.allMatches(firstLine).length))
      .reduce((a, b) => b.$2 > a.$2 ? b : a)
      .$1;
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    endCell();
    if (!(row.length == 1 && row.first.trim().isEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < t.length; i++) {
    final ch = t[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"' && cell.isEmpty) {
      quoted = true;
    } else if (ch == delimiter) {
      endCell();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < t.length && t[i + 1] == '\n') i++;
      endRow();
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12, //
};

/// `2026-10-23`, `23/10/2026` (day first), `23-10-26`, `23 Oct 2026`, `Oct 23, 2026`; null if not
/// a real date or in the future.
String? parseImportDate(String raw, {required DateTime today}) {
  final t = raw.trim();
  DateTime? make(int y, int m, int d) {
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    if (date.month != m || date.day != d) return null;
    if (date.isAfter(DateTime(today.year, today.month, today.day))) return null;
    if (date.year < 1990) return null;
    return date;
  }

  DateTime? date;
  final iso = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T].*)?$')
      .firstMatch(t);
  final dmy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})(?:[ T].*)?$')
      .firstMatch(t);
  final named = RegExp(
    r'^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?,?\s+(\d{2}|\d{4})$',
  ).firstMatch(t);
  final us = RegExp(r'^([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})$')
      .firstMatch(t);
  if (iso != null) {
    date = make(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  } else if (dmy != null) {
    // Day first, the way most countries write it.
    date = make(int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!));
  } else if (named != null && _months[named[2]!.toLowerCase()] != null) {
    date = make(
      int.parse(named[3]!),
      _months[named[2]!.toLowerCase()]!,
      int.parse(named[1]!),
    );
  } else if (us != null && _months[us[1]!.toLowerCase()] != null) {
    date = make(
      int.parse(us[3]!),
      _months[us[1]!.toLowerCase()]!,
      int.parse(us[2]!),
    );
  }
  if (date == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// Turns spreadsheet rows into expenses. Columns: Date, Description, Currency, Amount, found from
/// the header row by name in any order; with no header they are taken in that order. Rows that
/// cannot be used are reported with their line number and skipped, never guessed.
ImportParse parseImportRows(
  List<List<String>> rows, {
  required CurrencyInfo currency,
  required DateTime today,
  String decimal = '.',
}) {
  if (rows.isEmpty) return const ImportParse([], []);
  int? find(List<String> header, List<String> names) {
    for (var i = 0; i < header.length; i++) {
      if (names.contains(header[i].trim().toLowerCase())) return i;
    }
    return null;
  }

  final head = rows.first;
  final di = find(head, ['date', 'day']);
  final ai = find(head, ['amount', 'amt', 'total', 'price', 'cost']);
  final hasHeader = di != null && ai != null;
  final desc = hasHeader
      ? (find(head, [
              'description',
              'details',
              'note',
              'notes',
              'memo',
              'name',
              'item',
            ]) ??
            -1)
      : 1;
  final cur = hasHeader ? (find(head, ['currency', 'ccy']) ?? -1) : 2;
  final dateCol = hasHeader ? di : 0;
  final amountCol = hasHeader ? ai : 3;

  final out = <ImportRow>[];
  final problems = <ImportProblem>[];
  for (var i = hasHeader ? 1 : 0; i < rows.length; i++) {
    final r = rows[i];
    final line = i + 1;
    String at(int c) => c >= 0 && c < r.length ? r[c].trim() : '';
    if (r.every((c) => c.trim().isEmpty)) continue;

    final date = parseImportDate(at(dateCol), today: today);
    if (date == null) {
      problems.add(
        ImportProblem(
          line,
          at(dateCol).isEmpty
              ? 'No date'
              : 'Date "${at(dateCol)}" is not a valid past date',
        ),
      );
      continue;
    }
    final code = at(cur).toUpperCase();
    if (code.isNotEmpty && code != currency.code) {
      problems.add(
        ImportProblem(
          line,
          'Currency $code is not ${currency.code}; amounts are not converted',
        ),
      );
      continue;
    }
    var amountText = at(amountCol);
    final negative =
        amountText.startsWith('-') ||
        (amountText.startsWith('(') && amountText.endsWith(')'));
    amountText = amountText
        .replaceAll(RegExp(r'[()\-+]'), '')
        .replaceAll(currency.symbol, '')
        .replaceAll(currency.code, '');
    // European style (`1.234,56` or `48,20`): a comma followed by one or two digits at the end is
    // the decimal point; without this `48,20` would be read as 4820.
    final euro = RegExp(r'^\d[\d. ]*,\d{1,2}$').hasMatch(amountText.trim());
    if (euro) {
      amountText = amountText
          .trim()
          .replaceAll(RegExp(r'[. ]'), '')
          .replaceAll(',', '.');
    }
    final cents = parseMoneyInput(
      amountText,
      currency,
      decimal: euro ? '.' : decimal,
    );
    if (cents == null) {
      problems.add(
        ImportProblem(
          line,
          amountText.isEmpty
              ? 'No amount'
              : 'Amount "${at(amountCol)}" is not a number',
        ),
      );
      continue;
    }
    if (cents <= 0 || negative) {
      problems.add(
        ImportProblem(line, 'Refunds and zero amounts are not imported'),
      );
      continue;
    }
    out.add(
      ImportRow(line: line, date: date, description: at(desc), cents: cents),
    );
  }
  return ImportParse(out, problems);
}

/// The sheet id from a Google Sheets link (`.../spreadsheets/d/<id>/edit`) or the id itself.
String? sheetIdFromInput(String input) {
  final t = input.trim();
  final m = RegExp(r'/spreadsheets/d/([A-Za-z0-9_-]+)').firstMatch(t);
  if (m != null) return m[1];
  return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(t) ? t : null;
}
