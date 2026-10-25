import 'dart:convert';

import '../money/currency.dart';

/// Tab names and column order of the two kinds of sheet (docs/phases/phase-8-google-sheets-mode.md).
/// The sheets are a mirror of the app: anything typed into them is overwritten on the next sync.
abstract final class Tabs {
  // Member sheet
  static const expenses = 'Expenses';
  static const categories = 'Categories';
  static const suggestions = 'Suggestions';
  static const pairing = 'Pairing';
  static const meta = 'Meta';
  static const memberSheetTabs = [
    expenses,
    categories,
    suggestions,
    pairing,
    meta,
  ];

  // Household sheet
  static const members = 'Members';
  static const budgets = 'Budgets';
  static const goals = 'Goals';
  static const bills = 'Bills';
  static const decisions = 'Decisions';
  static const householdSheetTabs = [
    members,
    budgets,
    goals,
    bills,
    categories,
    decisions,
    meta,
  ];
}

abstract final class Headers {
  static const expenses = [
    'expense_id', 'date', 'amount', 'currency', 'category', 'note', 'receipt',
    'created', 'updated', 'deleted', 'amount_cents', //
  ];
  static const categories = ['category_id', 'name'];
  static const suggestions = [
    'suggestion_id', 'kind', 'action', 'target_id', 'payload_json', 'note',
    'status', 'created', 'updated', //
  ];
  static const pairing = [
    'household_sheet_id', 'organiser_email', 'member_email', 'member_name',
    'pair_value', 'paired_at', //
  ];
  static const members = ['email', 'name', 'sheet_id', 'status', 'paired_at'];
  static const record = ['id', 'updated', 'json'];
  static const decisions = [
    'suggestion_id',
    'member_email',
    'status',
    'decided_at',
  ];
}

const metaNote =
    'Family Expenses writes this sheet. It is a mirror of the app: changes typed here are overwritten on the next sync.';

/// Rows of the Meta tab: a note, then the revision counter the other side checks to see whether
/// anything changed without reading the whole sheet.
List<List<String>> metaRows(int revision, DateTime now) => [
  [metaNote],
  ['revision', '$revision'],
  ['schema', '1'],
  ['updated', now.toUtc().toIso8601String()],
];

/// Revision from `Meta!A1:B4`; 0 when missing.
int revisionOf(List<List<String>> meta) {
  for (final row in meta) {
    if (row.length >= 2 && row[0] == 'revision') {
      return int.tryParse(row[1]) ?? 0;
    }
  }
  return 0;
}

/// `4820` -> `48.20`, integer maths only.
String decimalOf(int cents, CurrencyInfo currency) {
  final f = currency.minorFactor;
  final abs = cents.abs();
  final sign = cents < 0 ? '-' : '';
  if (currency.minorDigits == 0) return '$sign${abs ~/ f}';
  return '$sign${abs ~/ f}.${(abs % f).toString().padLeft(currency.minorDigits, '0')}';
}

/// A sheet row for one expense, from plain values (kept free of Drift so it is easy to test).
class SheetExpense {
  const SheetExpense({
    required this.id,
    required this.date,
    required this.cents,
    required this.currency,
    required this.category,
    required this.note,
    required this.receipt,
    required this.created,
    required this.updated,
    required this.deleted,
  });

  final String id;

  /// `2026-10-23`.
  final String date;
  final int cents;
  final String currency;
  final String category;
  final String note;
  final String receipt;
  final DateTime created;
  final DateTime updated;
  final bool deleted;

  List<String> toRow() => [
    id,
    date,
    decimalOf(cents, currencyByCode(currency)),
    currency,
    // Text that starts like a formula is neutralised for people who open the sheet.
    _safe(category),
    _safe(note),
    receipt,
    created.toUtc().toIso8601String(),
    updated.toUtc().toIso8601String(),
    deleted ? '1' : '',
    '$cents',
  ];

  /// Null when the row is not a usable expense (hand-edited, short, or garbage).
  static SheetExpense? fromRow(List<String> r) {
    String at(int i) => i < r.length ? r[i] : '';
    final id = at(0).trim();
    final cents = int.tryParse(at(10).trim());
    final updated = DateTime.tryParse(at(8));
    final created = DateTime.tryParse(at(7)) ?? updated;
    if (id.isEmpty || cents == null || cents <= 0 || cents > 100000000000) {
      return null;
    }
    if (updated == null || created == null) return null;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(at(1))) return null;
    return SheetExpense(
      id: id,
      date: at(1),
      cents: cents,
      currency: at(3).isEmpty ? 'SGD' : at(3),
      category: _unsafe(at(4)),
      note: _unsafe(at(5)),
      receipt: at(6),
      created: created,
      updated: updated,
      deleted: at(9) == '1',
    );
  }
}

String _safe(String s) => s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;
String _unsafe(String s) =>
    s.startsWith("'") && s.length > 1 && '=+-@\t\r'.contains(s[1])
    ? s.substring(1)
    : s;

/// One record of the household sheet (a budget, goal or bill): id, updated, and the row as JSON.
List<String> recordRow(
  String id,
  DateTime updated,
  Map<String, Object?> json,
) => [id, updated.toUtc().toIso8601String(), jsonEncode(json)];

/// First column of a tab as letters for a column count: 11 -> `K`.
String colLetter(int count) => String.fromCharCode(64 + count);
