import 'package:flutter/foundation.dart';

/// What the keypad has typed so far, kept as text so "48." and "48.20" display as typed.
/// Everything becomes integer cents through integer maths only (rule 4).
@immutable
class AmountEntry {
  const AmountEntry({this.whole = '', this.fraction, this.minorDigits = 2});

  /// Starts from an existing amount, for editing.
  factory AmountEntry.fromCents(int cents, {int minorDigits = 2}) {
    var factor = 1;
    for (var i = 0; i < minorDigits; i++) {
      factor *= 10;
    }
    final abs = cents.abs();
    return AmountEntry(
      whole: (abs ~/ factor).toString(),
      fraction: minorDigits > 0
          ? (abs % factor).toString().padLeft(minorDigits, '0')
          : null,
      minorDigits: minorDigits,
    );
  }

  static const maxWholeDigits = 9;

  final String whole;

  /// Digits after the decimal point; null until the point is pressed.
  final String? fraction;
  final int minorDigits;

  bool get isEmpty => whole.isEmpty && fraction == null;

  /// The amount in minor units (cents).
  int get cents {
    var factor = 1;
    for (var i = 0; i < minorDigits; i++) {
      factor *= 10;
    }
    final wholePart = whole.isEmpty ? 0 : int.parse(whole);
    final frac = fraction ?? '';
    final fractionPart = frac.isEmpty
        ? 0
        : int.parse(frac.padRight(minorDigits, '0'));
    return wholePart * factor + fractionPart;
  }

  /// Text for the big amount display, using [decimalSeparator].
  String display(String decimalSeparator) {
    final w = whole.isEmpty ? '0' : whole;
    if (fraction == null) return w;
    return '$w$decimalSeparator$fraction';
  }

  AmountEntry digit(String d) {
    assert(d.length == 1 && '0123456789'.contains(d));
    final f = fraction;
    if (f != null) {
      if (f.length >= minorDigits) return this;
      return _copy(fraction: f + d);
    }
    if (whole.length >= maxWholeDigits) return this;
    if (whole == '0' || whole.isEmpty) {
      return _copy(whole: d == '0' ? '0' : d);
    }
    return _copy(whole: whole + d);
  }

  AmountEntry decimal() {
    if (minorDigits == 0 || fraction != null) return this;
    return _copy(whole: whole.isEmpty ? '0' : whole, fraction: '');
  }

  AmountEntry backspace() {
    final f = fraction;
    if (f != null) {
      return f.isEmpty
          ? _copy(clearFraction: true)
          : _copy(fraction: f.substring(0, f.length - 1));
    }
    if (whole.isEmpty) return this;
    return _copy(whole: whole.substring(0, whole.length - 1));
  }

  AmountEntry _copy({
    String? whole,
    String? fraction,
    bool clearFraction = false,
  }) => AmountEntry(
    whole: whole ?? this.whole,
    fraction: clearFraction ? null : (fraction ?? this.fraction),
    minorDigits: minorDigits,
  );

  @override
  bool operator ==(Object other) =>
      other is AmountEntry &&
      other.whole == whole &&
      other.fraction == fraction &&
      other.minorDigits == minorDigits;

  @override
  int get hashCode => Object.hash(whole, fraction, minorDigits);
}
