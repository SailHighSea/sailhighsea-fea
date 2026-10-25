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
  const ImportParse(this.rows, this.problems, {this.incomeSkipped = 0});
  final List<ImportRow> rows;
  final List<ImportProblem> problems;

  /// Money in (credits, deposits, salary): not an expense, left out.
  final int incomeSkipped;
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

/// Currencies mentioned in a sheet: from a currency column, codes (`SGD 12.50`) and symbols
/// (`S$`, `€`) in the amounts. `$` alone is ambiguous (US, Singapore, Australian... dollar).
class CurrencyDetection {
  const CurrencyDetection(this.codes, {this.ambiguousDollar = false});
  final Set<String> codes;
  final bool ambiguousDollar;

  /// Nothing reliable found: the person has to say.
  bool get unknown => codes.isEmpty;
}

const _symbols = <String, String>{
  'S\$': 'SGD', 'US\$': 'USD', 'A\$': 'AUD', 'C\$': 'CAD', 'RM': 'MYR',
  '€': 'EUR', '£': 'GBP', '₹': 'INR', '¥': 'JPY', //
};

String? _currencyIn(String cell) {
  final t = cell.trim();
  for (final c in supportedCurrencies) {
    if (RegExp('\\b${c.code}\\b', caseSensitive: false).hasMatch(t)) {
      return c.code;
    }
  }
  for (final e in _symbols.entries) {
    if (t.contains(e.key)) return e.value;
  }
  return null;
}

class _Columns {
  const _Columns({
    this.header = false,
    this.date = 0,
    this.desc = 1,
    this.cur = 2,
    this.amount = 3,
    this.debit = -1,
    this.credit = -1,
  });
  final bool header;
  final int date, desc, cur, amount, debit, credit;
}

int? _find(List<String> head, List<String> names) {
  for (var i = 0; i < head.length; i++) {
    if (names.contains(head[i].trim().toLowerCase())) return i;
  }
  return null;
}

_Columns _columns(List<String> head) {
  final di = _find(head, [
    'date',
    'day',
    'transaction date',
    'txn date',
    'trans date',
    'posting date',
    'posted date',
    'value date',
    'booking date',
  ]);
  final ai = _find(head, [
    'amount',
    'amt',
    'total',
    'price',
    'cost',
    'value',
    'transaction amount',
  ]);
  final debit = _find(head, [
    'debit',
    'debit amount',
    'withdrawal',
    'withdrawals',
    'paid out',
    'money out',
    'spent',
  ]);
  final credit = _find(head, [
    'credit',
    'credit amount',
    'deposit',
    'deposits',
    'paid in',
    'money in',
  ]);
  if (di == null || (ai == null && debit == null)) return const _Columns();
  return _Columns(
    header: true,
    date: di,
    desc:
        _find(head, [
          'description',
          'details',
          'note',
          'notes',
          'memo',
          'name',
          'item',
          'particulars',
          'narration',
          'transaction',
          'transaction details',
          'payee',
          'merchant',
          'reference',
          'remarks',
        ]) ??
        -1,
    cur: _find(head, ['currency', 'ccy', 'cur']) ?? -1,
    amount: ai ?? -1,
    debit: debit ?? -1,
    credit: credit ?? -1,
  );
}

/// Which currencies the rows mention (see [CurrencyDetection]).
CurrencyDetection detectCurrencies(List<List<String>> rows) {
  if (rows.isEmpty) return const CurrencyDetection({});
  final c = _columns(rows.first);
  final codes = <String>{};
  var dollar = false;
  for (var i = c.header ? 1 : 0; i < rows.length; i++) {
    final r = rows[i];
    String at(int k) => k >= 0 && k < r.length ? r[k] : '';
    final fromCol = _currencyIn(at(c.cur));
    if (fromCol != null) codes.add(fromCol);
    for (final k in [c.amount, c.debit, c.credit]) {
      final cell = at(k);
      final code = _currencyIn(cell);
      if (code != null) {
        codes.add(code);
      } else if (cell.contains(r'$')) {
        dollar = true;
      }
    }
  }
  return CurrencyDetection(codes, ambiguousDollar: dollar && codes.isEmpty);
}

/// Turns spreadsheet or statement rows into expenses. Columns are found from the header row by
/// name, in any order (Date, Description, Currency, Amount, or Debit and Credit); with no header
/// they are Date, Description, Currency, Amount. Money in (credits, deposits) is not an expense
/// and is counted separately. Rows that cannot be used are reported with their line number and
/// skipped, never guessed.
ImportParse parseImportRows(
  List<List<String>> rows, {
  required CurrencyInfo currency,
  required DateTime today,
  String decimal = '.',
}) {
  if (rows.isEmpty) return const ImportParse([], []);
  final c = _columns(rows.first);

  // Bank exports often write spending as negative numbers. If most amounts are negative, the
  // negatives are the expenses and the positives are money in; otherwise negatives are refunds.
  var neg = 0, pos = 0;
  if (c.amount >= 0) {
    for (var i = c.header ? 1 : 0; i < rows.length; i++) {
      final t = c.amount < rows[i].length ? rows[i][c.amount].trim() : '';
      if (t.startsWith('-') || (t.startsWith('(') && t.endsWith(')'))) {
        neg++;
      } else if (RegExp(r'\d').hasMatch(t)) {
        pos++;
      }
    }
  }
  final negativeIsSpending = neg > pos;

  final out = <ImportRow>[];
  final problems = <ImportProblem>[];
  var income = 0;
  for (var i = c.header ? 1 : 0; i < rows.length; i++) {
    final r = rows[i];
    final line = i + 1;
    String at(int k) => k >= 0 && k < r.length ? r[k].trim() : '';
    if (r.every((x) => x.trim().isEmpty)) continue;

    final date = parseImportDate(at(c.date), today: today);
    if (date == null) {
      problems.add(
        ImportProblem(
          line,
          at(c.date).isEmpty
              ? 'No date'
              : 'Date "${at(c.date)}" is not a valid past date',
        ),
      );
      continue;
    }

    var amountText = at(c.amount);
    var isIncome = false;
    var negative = false;
    if (c.debit >= 0 && at(c.debit).isNotEmpty) {
      amountText = at(c.debit);
    } else if (c.debit >= 0 && c.credit >= 0 && at(c.credit).isNotEmpty) {
      income++;
      continue;
    } else if (c.amount >= 0) {
      negative =
          amountText.startsWith('-') ||
          (amountText.startsWith('(') && amountText.endsWith(')'));
      if (RegExp(r'\b(CR)\b', caseSensitive: false).hasMatch(amountText)) {
        isIncome = true;
      }
      if (negativeIsSpending) {
        if (!negative && RegExp(r'\d').hasMatch(amountText)) isIncome = true;
        negative = false;
      }
    }
    if (isIncome) {
      income++;
      continue;
    }

    // The row's own currency: a currency column or a code or symbol in the amount.
    final code =
        (at(c.cur).isNotEmpty ? at(c.cur).toUpperCase() : null) ??
        _currencyIn(amountText);
    final rowCode = code != null && code.length == 3
        ? code
        : _currencyIn(amountText);
    if (rowCode != null && rowCode != currency.code) {
      problems.add(
        ImportProblem(
          line,
          'Currency $rowCode is not ${currency.code}; amounts are not converted',
        ),
      );
      continue;
    }
    amountText = amountText
        .replaceAll(RegExp(r'[A-Za-z$€£₹¥]'), '')
        .replaceAll(RegExp(r'[()\-+]'), '')
        .trim();
    // European style (`1.234,56` or `48,20`): a comma followed by one or two digits at the end is
    // the decimal point; without this `48,20` would be read as 4820.
    final euro = RegExp(r'^\d[\d. ]*,\d{1,2}$').hasMatch(amountText);
    if (euro) {
      amountText = amountText
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
              : 'Amount "${at(c.amount)}" is not a number',
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
      ImportRow(line: line, date: date, description: at(c.desc), cents: cents),
    );
  }
  return ImportParse(out, problems, incomeSkipped: income);
}

/// The sheet id from a Google Sheets link (`.../spreadsheets/d/<id>/edit`) or the id itself.
String? sheetIdFromInput(String input) {
  final t = input.trim();
  final m = RegExp(r'/spreadsheets/d/([A-Za-z0-9_-]+)').firstMatch(t);
  if (m != null) return m[1];
  return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(t) ? t : null;
}
