import 'package:family_expenses/core/money/currency.dart';
import 'package:family_expenses/core/money/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sgd = MoneyFormatter(currencyByCode('SGD'), locale: 'en_US');

  group('format (integer cents)', () {
    test('groups thousands and keeps two decimals', () {
      expect(sgd.format(184200), r'S$1,842.00');
      expect(sgd.format(9640), r'S$96.40');
      expect(sgd.format(123456789), r'S$1,234,567.89');
    });

    test('small amounts keep leading zeros', () {
      expect(sgd.format(0), r'S$0.00');
      expect(sgd.format(1), r'S$0.01');
      expect(sgd.format(10), r'S$0.10');
      expect(sgd.format(99), r'S$0.99');
    });

    test('negative amounts put the sign before the symbol', () {
      expect(sgd.format(-4820), r'-S$48.20');
      expect(sgd.format(-5), r'-S$0.05');
    });

    test('signed option shows a plus for positive amounts only', () {
      expect(sgd.format(150, signed: true), r'+S$1.50');
      expect(sgd.format(0, signed: true), r'S$0.00');
    });

    test('integer cents add exactly, with no floating point drift', () {
      // 0.1 + 0.2 != 0.3 in doubles; in cents it is exact.
      expect(sgd.format(10 + 20), r'S$0.30');
      var total = 0;
      for (var i = 0; i < 1000; i++) {
        total += 10;
      }
      expect(sgd.format(total), r'S$100.00');
    });
  });

  group('formatWhole', () {
    test('rounds half away from zero', () {
      expect(sgd.formatWhole(184200), r'S$1,842');
      expect(sgd.formatWhole(9649), r'S$96');
      expect(sgd.formatWhole(9650), r'S$97');
      expect(sgd.formatWhole(-9650), r'-S$97');
      expect(sgd.formatWhole(49), r'S$0');
    });
  });

  group('other currencies', () {
    test('yen has no minor unit', () {
      final jpy = MoneyFormatter(currencyByCode('JPY'), locale: 'en_US');
      expect(jpy.format(1500), '¥1,500');
      expect(jpy.formatWhole(1500), '¥1,500');
    });

    test('euro and unknown codes', () {
      expect(
        MoneyFormatter(currencyByCode('EUR'), locale: 'en_US').format(1999),
        '€19.99',
      );
      expect(currencyByCode('XXX').code, defaultCurrencyCode);
    });

    test('minorFactor is computed with integers', () {
      expect(currencyByCode('SGD').minorFactor, 100);
      expect(currencyByCode('JPY').minorFactor, 1);
    });
  });

  test('formatPlain has no symbol', () {
    expect(sgd.formatPlain(184250), '1842.50');
    expect(sgd.formatPlain(5), '0.05');
  });
}
