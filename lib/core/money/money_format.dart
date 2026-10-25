import 'package:intl/intl.dart';

import 'currency.dart';

/// Formats integer minor units (cents) as text. No floating point is involved in the
/// amount itself: it is split into whole and fractional parts with integer maths, and
/// intl only groups the whole part and supplies the locale's decimal separator.
class MoneyFormatter {
  MoneyFormatter(this.currency, {String? locale})
    : _locale = locale ?? Intl.getCurrentLocale(),
      _grouping = NumberFormat.decimalPattern(locale);

  final CurrencyInfo currency;
  final String _locale;
  final NumberFormat _grouping;

  String get decimalSeparator => _grouping.symbols.DECIMAL_SEP;

  /// `S$1,842.50`, or `-S$48.20` when [cents] is negative.
  String format(int cents, {bool signed = false}) {
    final factor = currency.minorFactor;
    final abs = cents.abs();
    final whole = abs ~/ factor;
    final fraction = abs % factor;
    final body = StringBuffer(_grouping.format(whole));
    if (currency.minorDigits > 0) {
      body
        ..write(decimalSeparator)
        ..write(fraction.toString().padLeft(currency.minorDigits, '0'));
    }
    return '${_sign(cents, signed)}${currency.prefix}$body';
  }

  /// Whole units only, rounded half away from zero: `S$1,842`.
  String formatWhole(int cents, {bool signed = false}) {
    final factor = currency.minorFactor;
    final rounded = (cents.abs() + factor ~/ 2) ~/ factor;
    return '${_sign(cents, signed)}${currency.prefix}${_grouping.format(rounded)}';
  }

  /// A plain number with the currency's decimals and no symbol, for the keypad display.
  String formatPlain(int cents) {
    final factor = currency.minorFactor;
    final abs = cents.abs();
    final whole = abs ~/ factor;
    final fraction = abs % factor;
    final text = StringBuffer(whole.toString());
    if (currency.minorDigits > 0) {
      text
        ..write(decimalSeparator)
        ..write(fraction.toString().padLeft(currency.minorDigits, '0'));
    }
    return '${cents < 0 ? '-' : ''}$text';
  }

  String _sign(int cents, bool signed) {
    if (cents < 0) return '-';
    if (signed && cents > 0) return '+';
    return '';
  }

  String get locale => _locale;
}
