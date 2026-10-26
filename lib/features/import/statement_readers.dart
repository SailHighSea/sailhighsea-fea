import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/money/currency.dart';
import '../scan/receipt_services.dart' show OcrLine;

/// The first worksheet of an Excel file (`.xlsx`) as rows of text. Dates become `yyyy-MM-dd`
/// (Excel stores them as numbers); numbers keep their exact digits; formulas give their text.
List<List<String>> rowsFromXlsx(Uint8List bytes) {
  final book = Excel.decodeBytes(bytes);
  if (book.tables.isEmpty) return const [];
  final sheet = book.tables.values.first;
  String two(int n) => n.toString().padLeft(2, '0');
  String cell(CellValue? v) => switch (v) {
    null => '',
    TextCellValue() => v.value.toString(),
    IntCellValue() => '${v.value}',
    DoubleCellValue() => _plainDouble(v.value),
    DateCellValue() => '${v.year}-${two(v.month)}-${two(v.day)}',
    DateTimeCellValue() => '${v.year}-${two(v.month)}-${two(v.day)}',
    FormulaCellValue() => v.formula,
    _ => v.toString(),
  };
  return [
    for (final row in sheet.rows) [for (final d in row) cell(d?.value)],
  ].where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

/// A double from a sheet as text without exponent noise (`48.2` stays `48.2`).
String _plainDouble(double d) {
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.round().toString();
  return d.toString();
}

/// Text lines of a PDF (a bank or card statement). Scanned PDFs have no text and give an empty
/// string; the app then says so.
String textFromPdf(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    return PdfTextExtractor(doc).extractText(layoutText: true);
  } finally {
    doc.dispose();
  }
}

/// What was read from a statement.
class StatementRows {
  const StatementRows(this.rows, {this.moneyIn = 0});

  /// `Date, Description, Debit, Credit, Currency` with a header row; expenses are in Debit.
  final List<List<String>> rows;
  final int moneyIn;
}

final _dateStart = RegExp(
  r'^\s*(\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|\d{1,2}\s+[A-Za-z]{3,9}\.?,?(?:\s+\d{2,4})?|[A-Za-z]{3,9}\.?\s+\d{1,2},?(?:\s+\d{4})?)(?=\s|$)',
);
final _money = RegExp(
  r'(?<![\d.,])\(?-?\d{1,3}(?:[ ,.]\d{3})*[.,]\d{2}\)?(?:\s?(?:CR|DR|Cr|Dr))?(?![\d])',
);
final _creditWords = RegExp(
  r'\b(salary|payroll|deposit|interest earned|refund|reversal|cashback|credit interest|transfer in|received|giro in|incoming|dividend)\b',
  caseSensitive: false,
);

/// Reads transaction lines out of statement text: a line that starts with a date and has at
/// least one amount. When a line has several amounts (amount, then running balance) the one before
/// the last is the transaction. A `CR` suffix or words like "salary" mark money in. This is a best
/// guess: the person checks the table before importing.
StatementRows rowsFromStatementText(String text, {int? defaultYear}) {
  final year = defaultYear ?? DateTime.now().year;
  final rows = <List<String>>[
    ['Date', 'Description', 'Debit', 'Credit', 'Currency'],
  ];
  var income = 0;
  final head = text.split(RegExp(r'\r?\n')).take(80).join(' ');
  final statementCurrency = _codeIn(head) ?? '';
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    var line = raw.replaceAll(RegExp(r'\s{2,}'), '  ').trim();
    if (line.isEmpty) continue;
    // Some PDFs run the columns together: "28/07/2626/07/26SHOP..." is two dates and a shop.
    line = line.replaceFirstMapped(
      RegExp(r'^(\d{2}[-/.]\d{2}[-/.]\d{2})(\d{2}[-/.]\d{2}[-/.]\d{2})(?=\S)'),
      (m) => '${m[1]} ${m[2]} ',
    );
    final d = _dateStart.firstMatch(line);
    if (d == null) continue;
    var rest = line.substring(d.end).trim();
    // A second date (posting and value date) right after the first.
    final d2 = _dateStart.firstMatch(rest);
    if (d2 != null && RegExp(r'\d').hasMatch(d2[1]!)) {
      rest = rest.substring(d2.end).trim();
    }
    final amounts = _money.allMatches(rest).toList();
    if (amounts.isEmpty) continue;
    // "USD 117.37  435.95": a foreign amount, then the amount in the statement currency, is
    // two amounts but not a running balance; the transaction is the last one.
    final foreign =
        amounts.length >= 2 &&
        _knownCodeBefore(rest.substring(0, amounts[amounts.length - 2].start));
    final pick = foreign
        ? amounts.last
        : amounts.length >= 2
        ? amounts[amounts.length - 2]
        : amounts.first;
    var description = rest
        .substring(0, amounts.first.start)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_knownCodeBefore(description)) {
      description = description.substring(0, description.length - 3).trim();
    }
    // The bank's reference number at the end ("..., DOHA, 068276") is noise in a description.
    description = description
        .replaceAll(RegExp(r'[ ,]+\d{5,}\s*(CR)?$'), '')
        .replaceAll(RegExp(r'\s+CR$'), '')
        .trim();
    var dateText = d[1]!.trim();
    // A date without a year ("23 Oct") takes the statement year.
    if (!RegExp(r'\d{4}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2}').hasMatch(dateText)) {
      dateText = '$dateText $year';
    }
    final amountText = pick[0]!;
    // "CR" can sit after the amount (`1,000.00 CR`) or before it in its own column.
    final isCredit =
        RegExp(r'(?<![A-Za-z])CR(?![A-Za-z])').hasMatch(rest) ||
        RegExp(r'\bCR\b', caseSensitive: false).hasMatch(amountText) ||
        _creditWords.hasMatch(description);
    final clean = amountText.replaceAll(RegExp(r'\s?(CR|DR|Cr|Dr)$'), '');
    final around = rest.substring(
      (pick.start - 4).clamp(0, rest.length),
      (pick.end + 4).clamp(0, rest.length),
    );
    final cur = foreign
        ? statementCurrency
        : _codeIn(around) ?? statementCurrency;
    if (isCredit) {
      income++;
      continue;
    }
    rows.add([dateText, description, clean, '', cur]);
  }
  return StatementRows(rows, moneyIn: income);
}

/// Whether [text] ends with a known currency code ("... 025389USD").
bool _knownCodeBefore(String text) {
  final m = RegExp(r'([A-Z]{3})\s*$').firstMatch(text.trimRight());
  if (m == null) return false;
  return supportedCurrencies.any((c) => c.code == m[1]);
}

/// Codes that are also ordinary words (ALL, TRY, TOP...) are only trusted when a phrase like
/// "Amount in QAR" or "Currency: USD" names them.
const _wordLikeCodes = {
  'ALL',
  'TRY',
  'TOP',
  'ANG',
  'MOP',
  'SOS',
  'PEN',
  'LAK',
  'BAM',
  'GEL',
  'KES',
  'CUP',
  'LSL',
  'BIF',
};

String? _codeIn(String text) {
  final known = {for (final c in supportedCurrencies) c.code};
  final phrase = RegExp(
    r'(?:amounts?\s+in|currency:?|all\s+amounts\s+in|figures\s+in|balance\s+in|in)\s+\(?([A-Z]{3})\)?\b',
    caseSensitive: false,
  );
  for (final m in phrase.allMatches(text)) {
    final c = m[1]!.toUpperCase();
    if (known.contains(c) && m[0]!.toLowerCase() != 'in $c'.toLowerCase()) {
      return c;
    }
  }
  for (final c in supportedCurrencies) {
    if (_wordLikeCodes.contains(c.code)) continue;
    if (RegExp('\\b${c.code}\\b').hasMatch(text)) return c.code;
  }
  return null;
}

/// Puts a photographed statement back together: lines at about the same height are one row, in
/// left to right order, then the rows are read like statement text.
StatementRows rowsFromOcrLines(List<OcrLine> lines, {int? defaultYear}) {
  if (lines.isEmpty) {
    return const StatementRows([
      ['Date', 'Description', 'Debit', 'Credit', 'Currency'],
    ]);
  }
  final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));
  final heights = sorted.map((l) => l.height).toList()..sort();
  final tolerance = heights[heights.length ~/ 2] * 0.6;
  final rows = <List<OcrLine>>[];
  for (final l in sorted) {
    if (rows.isNotEmpty) {
      final avg =
          rows.last.map((x) => x.centerY).reduce((a, b) => a + b) /
          rows.last.length;
      if ((l.centerY - avg).abs() <= tolerance) {
        rows.last.add(l);
        continue;
      }
    }
    rows.add([l]);
  }
  final text = rows
      .map(
        (r) => ([...r]..sort((a, b) => a.left.compareTo(b.left)))
            .map((l) => l.text.trim())
            .join('  '),
      )
      .join('\n');
  return rowsFromStatementText(text, defaultYear: defaultYear);
}
