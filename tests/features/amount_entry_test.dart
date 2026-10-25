import 'package:family_expenses/features/expenses/amount_entry.dart';
import 'package:flutter_test/flutter_test.dart';

AmountEntry type(String keys, {int minorDigits = 2}) {
  var entry = AmountEntry(minorDigits: minorDigits);
  for (final k in keys.split('')) {
    entry = switch (k) {
      '.' => entry.decimal(),
      '<' => entry.backspace(),
      _ => entry.digit(k),
    };
  }
  return entry;
}

void main() {
  test('typing 48.20 gives 4820 cents and displays as typed', () {
    final e = type('48.20');
    expect(e.cents, 4820);
    expect(e.display('.'), '48.20');
  });

  test('whole amounts', () {
    expect(type('5').cents, 500);
    expect(type('1842').cents, 184200);
  });

  test('one decimal digit means tens of cents', () {
    expect(type('3.5').cents, 350);
    expect(type('3.').cents, 300);
    expect(type('3.').display('.'), '3.');
  });

  test('a third decimal digit is ignored', () {
    expect(type('1.234').cents, 123);
    expect(type('1.234').display('.'), '1.23');
  });

  test('a second decimal point is ignored', () {
    expect(type('1.2.3').display('.'), '1.23');
  });

  test('leading zeros are not kept', () {
    expect(type('007').cents, 700);
    expect(type('007').display('.'), '7');
    expect(type('0.5').cents, 50);
  });

  test('decimal point first starts at zero', () {
    expect(type('.5').display('.'), '0.5');
    expect(type('.5').cents, 50);
  });

  test('backspace removes digits, then the point', () {
    expect(type('48.2<').display('.'), '48.');
    expect(type('48.<').display('.'), '48');
    expect(type('48<').display('.'), '4');
    expect(type('4<').isEmpty, isTrue);
    expect(type('<<').isEmpty, isTrue);
  });

  test('empty entry is zero cents and shows 0', () {
    const e = AmountEntry();
    expect(e.cents, 0);
    expect(e.isEmpty, isTrue);
    expect(e.display('.'), '0');
  });

  test('limits the whole part to nine digits', () {
    final e = type('12345678901');
    expect(e.display('.'), '123456789');
    expect(e.cents, 12345678900);
  });

  test('currency without minor units has no decimal point', () {
    final yen = type('1500.', minorDigits: 0);
    expect(yen.cents, 1500);
    expect(yen.display('.'), '1500');
  });

  test('fromCents round trips', () {
    final e = AmountEntry.fromCents(4820);
    expect(e.cents, 4820);
    expect(e.display('.'), '48.20');
    expect(AmountEntry.fromCents(5).display('.'), '0.05');
    expect(AmountEntry.fromCents(100000).cents, 100000);
  });

  test('uses the given decimal separator', () {
    expect(type('1.5').display(','), '1,5');
  });
}
