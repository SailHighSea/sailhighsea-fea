import 'currency.dart';

/// Turns what a person typed ("12", "12.5", "1,250.00") into integer minor units, or `null`
/// when it is not a plain amount. Integer maths only: the text is split at the decimal point,
/// never parsed as a double.
int? parseMoneyInput(
  String text,
  CurrencyInfo currency, {
  String decimal = '.',
}) {
  var cleaned = text.trim().replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) return null;
  // Thousands separators: drop the grouping character that is not the decimal one.
  final group = decimal == '.' ? ',' : '.';
  cleaned = cleaned.replaceAll(group, '');
  final parts = cleaned.split(decimal);
  if (parts.length > 2) return null;
  final whole = parts[0].isEmpty ? '0' : parts[0];
  var fraction = parts.length == 2 ? parts[1] : '';
  if (!RegExp(r'^\d+$').hasMatch(whole)) return null;
  if (fraction.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fraction)) return null;
  if (fraction.length > currency.minorDigits) return null;
  fraction = fraction.padRight(currency.minorDigits, '0');
  if (whole.length > 9) return null;
  final factor = currency.minorFactor;
  final cents =
      int.parse(whole) * factor + (fraction.isEmpty ? 0 : int.parse(fraction));
  return cents;
}
