import 'package:family_expenses/features/scan/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 23);

  test(
    'reads the total, shop, date and a category from a supermarket receipt',
    () {
      final r = parseReceiptText('''
SUPERMARKET FRESH MART
Tel 6123 4567
23/10/2026 14:02
Milk 2L            4.50
Bread              3.20
Subtotal          44.00
GST                4.20
TOTAL             48.20
Cash              50.00
''', now: now);
      expect(r.cents, 4820);
      expect(r.merchant, 'Supermarket Fresh Mart');
      expect(r.date, DateTime(2026, 10, 23));
      expect(r.categoryHint, 'Food');
    },
  );

  test('the total line wins over a larger tendered amount', () {
    final r = parseReceiptText(
      'Shop\nTotal 12.40\nCash 20.00\nChange 7.60',
      now: now,
    );
    expect(r.cents, 1240);
  });

  test('subtotal and tax lines are not taken as the total', () {
    final r = parseReceiptText(
      'Cafe\nSubtotal 10.00\nTax 0.70\nTotal due 10.70',
      now: now,
    );
    expect(r.cents, 1070);
  });

  test('without a total word the largest amount is used', () {
    final r = parseReceiptText('Corner shop\n3.50\n12.25\n1.00', now: now);
    expect(r.cents, 1225);
  });

  test('thousands separators and comma decimals', () {
    expect(parseReceiptText('Shop\nTotal 1,234.56', now: now).cents, 123456);
    expect(parseReceiptText('Shop\nTotal 1.234,56', now: now).cents, 123456);
    expect(parseReceiptText('Shop\nTotal 48,20', now: now).cents, 4820);
  });

  test('money is whole cents, never a float', () {
    expect(parseReceiptText('Shop\nTotal 0.10', now: now).cents, 10);
    expect(parseReceiptText('Shop\nTotal 19.99', now: now).cents, 1999);
  });

  test('date formats', () {
    DateTime? d(String s) =>
        parseReceiptText('Shop\n$s\nTotal 1.00', now: now).date;
    expect(d('2026-10-05'), DateTime(2026, 10, 5));
    expect(d('05 Oct 2026'), DateTime(2026, 10, 5));
    expect(d('5-10-26'), DateTime(2026, 10, 5));
    expect(d('31/02/2026'), isNull, reason: 'not a real day');
    expect(d('01/01/2031'), isNull, reason: 'in the future');
    expect(d('01/01/2010'), isNull, reason: 'too old to be right');
  });

  test('category hints', () {
    String? c(String shop) =>
        parseReceiptText('$shop\nTotal 5.00', now: now).categoryHint;
    expect(c('Shell Petrol Station'), 'Transport');
    expect(c('City Pharmacy'), 'Health');
    expect(c('Joe Plumbing'), isNull);
  });

  test('empty or unreadable text gives an empty result', () {
    expect(parseReceiptText('', now: now).isEmpty, isTrue);
    expect(parseReceiptText('~~ ## ..', now: now).isEmpty, isTrue);
  });
}
