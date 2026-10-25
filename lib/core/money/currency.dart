import 'package:flutter/foundation.dart';

/// A currency the household can use. Amounts are always stored as integer minor units
/// (cents for most currencies); [minorDigits] says how many digits the minor unit has.
@immutable
class CurrencyInfo {
  const CurrencyInfo(this.code, this.symbol, this.name, {this.minorDigits = 2});

  final String code;
  final String symbol;
  final String name;
  final int minorDigits;

  /// 10 ^ [minorDigits], computed with integers only.
  int get minorFactor {
    var factor = 1;
    for (var i = 0; i < minorDigits; i++) {
      factor *= 10;
    }
    return factor;
  }
}

/// Single household currency for v1 (PLAN.md open decision 5); Singapore dollar by default.
const defaultCurrencyCode = 'SGD';

const supportedCurrencies = <CurrencyInfo>[
  CurrencyInfo('SGD', r'S$', 'Singapore dollar'),
  CurrencyInfo('USD', r'$', 'US dollar'),
  CurrencyInfo('EUR', '€', 'Euro'),
  CurrencyInfo('GBP', '£', 'Pound sterling'),
  CurrencyInfo('AUD', r'A$', 'Australian dollar'),
  CurrencyInfo('CAD', r'C$', 'Canadian dollar'),
  CurrencyInfo('MYR', 'RM', 'Malaysian ringgit'),
  CurrencyInfo('INR', '₹', 'Indian rupee'),
  CurrencyInfo('JPY', '¥', 'Japanese yen', minorDigits: 0),
];

CurrencyInfo currencyByCode(String code) => supportedCurrencies.firstWhere(
  (c) => c.code == code,
  orElse: () => supportedCurrencies.first,
);
