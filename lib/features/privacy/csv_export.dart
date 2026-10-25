import '../../core/money/currency.dart';

/// One row of the export, already resolved to display values.
class CsvExpense {
  const CsvExpense({
    required this.date,
    required this.cents,
    required this.category,
    required this.note,
    required this.addedBy,
  });

  /// `2026-10-23`.
  final String date;
  final int cents;
  final String category;
  final String note;
  final String addedBy;
}

/// `48.20` for 4820 cents, with integer maths only (no floats, no grouping, always a dot) so any
/// spreadsheet reads it as a number.
String plainAmount(int cents, CurrencyInfo currency) {
  final factor = currency.minorFactor;
  final abs = cents.abs();
  final whole = abs ~/ factor;
  final sign = cents < 0 ? '-' : '';
  if (currency.minorDigits == 0) return '$sign$whole';
  final fraction = (abs % factor).toString().padLeft(currency.minorDigits, '0');
  return '$sign$whole.$fraction';
}

/// A text cell that cannot run as a formula when opened in a spreadsheet: a leading `=`, `+`,
/// `-`, `@`, tab or carriage return gets a quote in front (OWASP "CSV injection").
String safeCell(String text) {
  final trimmed = text.replaceAll(
    RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'),
    '',
  );
  if (trimmed.isEmpty) return trimmed;
  return '=+-@\t\r'.contains(trimmed[0]) ? "'$trimmed" : trimmed;
}

String _quote(String s) =>
    RegExp(r'[",\r\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;

/// RFC 4180 CSV (CRLF line ends) with a header row. Dates are `YYYY-MM-DD`.
String buildExpensesCsv(List<CsvExpense> rows, CurrencyInfo currency) {
  final b = StringBuffer('Date,Amount,Currency,Category,Note,Added by\r\n');
  for (final r in rows) {
    b
      ..write(_quote(r.date))
      ..write(',')
      ..write(plainAmount(r.cents, currency))
      ..write(',')
      ..write(currency.code)
      ..write(',')
      ..write(_quote(safeCell(r.category)))
      ..write(',')
      ..write(_quote(safeCell(r.note)))
      ..write(',')
      ..write(_quote(safeCell(r.addedBy)))
      ..write('\r\n');
  }
  return b.toString();
}
