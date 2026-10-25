import 'package:family_expenses/core/money/currency.dart';
import 'package:family_expenses/features/privacy/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sgd = currencyByCode('SGD');
  final jpy = currencyByCode('JPY');

  test('amounts are exact, plain decimals', () {
    expect(plainAmount(4820, sgd), '48.20');
    expect(plainAmount(5, sgd), '0.05');
    expect(plainAmount(100000000, sgd), '1000000.00');
    expect(plainAmount(-1250, sgd), '-12.50');
    expect(plainAmount(1999, jpy), '1999');
  });

  test('header, one row per expense, CRLF line ends', () {
    final csv = buildExpensesCsv([
      const CsvExpense(
        date: '2026-10-23',
        cents: 4820,
        category: 'Food',
        note: 'Groceries',
        addedBy: 'You',
      ),
    ], sgd);
    expect(
      csv,
      'Date,Amount,Currency,Category,Note,Added by\r\n2026-10-23,48.20,SGD,Food,Groceries,You\r\n',
    );
  });

  test('commas, quotes and new lines are quoted', () {
    final csv = buildExpensesCsv([
      const CsvExpense(
        date: '2026-10-23',
        cents: 100,
        category: 'Food',
        note: 'Milk, "fresh"\nand eggs',
        addedBy: 'Maya',
      ),
    ], sgd);
    expect(csv, contains('"Milk, ""fresh""\nand eggs"'));
  });

  test('text that would run as a formula is neutralised', () {
    for (final bad in ['=SUM(A1)', '+1', '-1', '@cmd', '\tx']) {
      expect(safeCell(bad), startsWith("'"), reason: bad);
    }
    expect(safeCell('Lunch'), 'Lunch');
    expect(safeCell(''), '');
    final csv = buildExpensesCsv([
      const CsvExpense(
        date: '2026-10-23',
        cents: 100,
        category: 'Food',
        note: '=HYPERLINK("http://x")',
        addedBy: 'You',
      ),
    ], sgd);
    expect(csv, contains("'=HYPERLINK"));
  });

  test('no expenses: just the header', () {
    expect(
      buildExpensesCsv(const [], sgd),
      'Date,Amount,Currency,Category,Note,Added by\r\n',
    );
  });
}
