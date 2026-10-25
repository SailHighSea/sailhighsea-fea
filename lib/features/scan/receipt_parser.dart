import 'package:flutter/foundation.dart';

/// What could be read from a receipt. Every field is optional: OCR is a best guess and the person
/// checks it before saving.
@immutable
class ParsedReceipt {
  const ParsedReceipt({
    this.cents,
    this.merchant,
    this.date,
    this.categoryHint,
  });

  /// Integer cents (minor units), never a double.
  final int? cents;
  final String? merchant;
  final DateTime? date;

  /// A category name guessed from the shop, such as `Food`. Matched against the household's
  /// categories by name; null when nothing fits.
  final String? categoryHint;

  bool get isEmpty =>
      cents == null && merchant == null && date == null && categoryHint == null;
}

const _totalWords = [
  'grand total',
  'total due',
  'amount due',
  'balance due',
  'total',
  'amount',
  'to pay',
  'net',
];
const _ignoreTotal = [
  'subtotal',
  'sub total',
  'sub-total',
  'tax',
  'gst',
  'vat',
];

// 1,234.56  1.234,56  48.20  48,20  1 234.56
final _money = RegExp(
  r'(?<![\d.,])(\d{1,3}(?:[ ,.]\d{3})*|\d+)[.,](\d{2})(?![\d])',
);

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12, //
};

const _categoryWords = <String, List<String>>{
  'Food': [
    'supermarket', 'mart', 'grocer', 'bakery', 'cafe', 'coffee', 'restaurant',
    'kitchen', 'food', 'bistro', 'pizza', 'burger', 'fairprice', 'tesco',
    'walmart', 'aldi', 'lidl', 'market', //
  ],
  'Transport': [
    'petrol', 'fuel', 'shell', 'esso', 'taxi', 'grab', 'uber', 'parking',
    'transit', 'railway', 'station', 'airlines', //
  ],
  'Health': ['pharmacy', 'chemist', 'clinic', 'hospital', 'dental', 'guardian'],
  'Home': ['hardware', 'furniture', 'ikea', 'homeware', 'electric', 'water'],
  'Fun': ['cinema', 'movie', 'theatre', 'games', 'toys', 'bookstore'],
};

/// Reads amount, shop, date and a category guess out of recognised receipt text.
///
/// [now] only decides which century a two-digit year belongs to and rejects future dates by
/// falling back to null, so a misread digit does not file an expense next year.
ParsedReceipt parseReceiptText(String text, {required DateTime now}) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const ParsedReceipt();
  final merchant = _merchant(lines);
  return ParsedReceipt(
    cents: _total(lines),
    merchant: merchant,
    date: _date(lines, now),
    categoryHint: _category(merchant, lines),
  );
}

int? _cents(RegExpMatch m) {
  final whole = m.group(1)!.replaceAll(RegExp(r'[ ,.]'), '');
  final n = int.tryParse(whole);
  final fraction = int.tryParse(m.group(2)!);
  if (n == null || fraction == null) return null;
  return n * 100 + fraction;
}

int? _total(List<String> lines) {
  // 1. A line that says total/amount due: take its last amount (the value is on the right).
  for (final word in _totalWords) {
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      if (!lower.contains(word)) continue;
      if (_ignoreTotal.any(lower.contains) && !lower.contains('total due')) {
        continue;
      }
      final matches = _money.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final c = _cents(matches.last);
      if (c != null && c > 0) return c;
    }
  }
  // 2. Otherwise the largest amount on the receipt.
  int? best;
  for (final line in lines) {
    for (final m in _money.allMatches(line)) {
      final c = _cents(m);
      if (c != null && (best == null || c > best)) best = c;
    }
  }
  return best != null && best > 0 ? best : null;
}

String? _merchant(List<String> lines) {
  for (final line in lines.take(6)) {
    final letters = RegExp(r'[A-Za-z]').allMatches(line).length;
    if (letters < 3) continue;
    if (letters < line.length / 2) continue; // mostly digits and symbols
    final lower = line.toLowerCase();
    if (lower.contains('receipt') ||
        lower.contains('invoice') ||
        lower.contains('tel') ||
        lower.contains('www.') ||
        lower.contains('gst reg')) {
      continue;
    }
    return _titleCase(line.replaceAll(RegExp(r'[^\w\s&\x27.-]'), '').trim());
  }
  return null;
}

String _titleCase(String s) => s
    .split(RegExp(r'\s+'))
    .map(
      (w) => w.length > 1 && w == w.toUpperCase()
          ? w[0] + w.substring(1).toLowerCase()
          : w,
    )
    .join(' ');

DateTime? _date(List<String> lines, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final iso = RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b');
  final dmy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\b');
  final named = RegExp(
    r'\b(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?,?\s+(\d{2}|\d{4})\b',
  );
  DateTime? make(int y, int m, int d) {
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    if (date.month != m || date.day != d) return null;
    if (date.isAfter(today)) return null;
    if (date.year < today.year - 5) return null;
    return date;
  }

  for (final line in lines) {
    final a = iso.firstMatch(line);
    if (a != null) {
      final d = make(int.parse(a[1]!), int.parse(a[2]!), int.parse(a[3]!));
      if (d != null) return d;
    }
    final n = named.firstMatch(line);
    if (n != null) {
      final month = _months[n[2]!.toLowerCase()];
      if (month != null) {
        final d = make(int.parse(n[3]!), month, int.parse(n[1]!));
        if (d != null) return d;
      }
    }
    final b = dmy.firstMatch(line);
    if (b != null) {
      // Day first, the way most receipts outside the US print it.
      final d = make(int.parse(b[3]!), int.parse(b[2]!), int.parse(b[1]!));
      if (d != null) return d;
    }
  }
  return null;
}

String? _category(String? merchant, List<String> lines) {
  final haystack = '${merchant ?? ''} ${lines.take(4).join(' ')}'.toLowerCase();
  for (final entry in _categoryWords.entries) {
    if (entry.value.any(haystack.contains)) return entry.key;
  }
  return null;
}
