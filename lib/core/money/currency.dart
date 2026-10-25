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

  /// What goes in front of an amount: the symbol, with a space when it is just letters
  /// (`CHF 12.00`, `QR 5.00` stays tight like `RM5.00`).
  String get prefix =>
      symbol.length >= 3 && RegExp(r'^[A-Za-z]+$').hasMatch(symbol)
      ? '$symbol '
      : symbol;

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

/// The currencies you can choose (ISO 4217). The first ones are the most used and Singapore dollar
/// is the default; the rest follow in alphabetical order. Amounts are always whole minor units, so
/// [CurrencyInfo.minorDigits] matters: yen has none, dinars have three.
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
  CurrencyInfo('QAR', 'QR', 'Qatari riyal'),
  CurrencyInfo('SAR', 'SAR', 'Saudi riyal'),
  CurrencyInfo('AED', 'AED', 'UAE dirham'),
  CurrencyInfo('AFN', 'AFN', 'Afghan afghani'),
  CurrencyInfo('ALL', 'ALL', 'Albanian lek'),
  CurrencyInfo('AMD', 'AMD', 'Armenian dram'),
  CurrencyInfo('ANG', 'ANG', 'Netherlands Antillean guilder'),
  CurrencyInfo('AOA', 'AOA', 'Angolan kwanza'),
  CurrencyInfo('ARS', r'AR$', 'Argentine peso'),
  CurrencyInfo('AWG', 'AWG', 'Aruban florin'),
  CurrencyInfo('AZN', '₼', 'Azerbaijani manat'),
  CurrencyInfo('BAM', 'KM', 'Bosnia-Herzegovina convertible mark'),
  CurrencyInfo('BBD', 'BBD', 'Barbadian dollar'),
  CurrencyInfo('BDT', '৳', 'Bangladeshi taka'),
  CurrencyInfo('BGN', 'BGN', 'Bulgarian lev'),
  CurrencyInfo('BHD', 'BHD', 'Bahraini dinar', minorDigits: 3),
  CurrencyInfo('BIF', 'BIF', 'Burundian franc', minorDigits: 0),
  CurrencyInfo('BMD', 'BMD', 'Bermudian dollar'),
  CurrencyInfo('BND', 'BND', 'Brunei dollar'),
  CurrencyInfo('BOB', 'Bs', 'Bolivian boliviano'),
  CurrencyInfo('BRL', r'R$', 'Brazilian real'),
  CurrencyInfo('BSD', 'BSD', 'Bahamian dollar'),
  CurrencyInfo('BTN', 'BTN', 'Bhutanese ngultrum'),
  CurrencyInfo('BWP', 'BWP', 'Botswana pula'),
  CurrencyInfo('BYN', 'Br', 'Belarusian ruble'),
  CurrencyInfo('BZD', 'BZD', 'Belize dollar'),
  CurrencyInfo('CDF', 'CDF', 'Congolese franc'),
  CurrencyInfo('CHF', 'CHF', 'Swiss franc'),
  CurrencyInfo('CLP', 'CLP', 'Chilean peso', minorDigits: 0),
  CurrencyInfo('CNY', 'CN¥', 'Chinese yuan'),
  CurrencyInfo('COP', 'COP', 'Colombian peso'),
  CurrencyInfo('CRC', '₡', 'Costa Rican colón'),
  CurrencyInfo('CUP', 'CUP', 'Cuban peso'),
  CurrencyInfo('CVE', 'CVE', 'Cape Verdean escudo'),
  CurrencyInfo('CZK', 'Kč', 'Czech koruna'),
  CurrencyInfo('DJF', 'DJF', 'Djiboutian franc', minorDigits: 0),
  CurrencyInfo('DKK', 'kr', 'Danish krone'),
  CurrencyInfo('DOP', r'RD$', 'Dominican peso'),
  CurrencyInfo('DZD', 'DZD', 'Algerian dinar'),
  CurrencyInfo('EGP', 'E£', 'Egyptian pound'),
  CurrencyInfo('ERN', 'ERN', 'Eritrean nakfa'),
  CurrencyInfo('ETB', 'ETB', 'Ethiopian birr'),
  CurrencyInfo('FJD', 'FJD', 'Fijian dollar'),
  CurrencyInfo('FKP', 'FKP', 'Falkland Islands pound'),
  CurrencyInfo('GEL', '₾', 'Georgian lari'),
  CurrencyInfo('GHS', 'GH₵', 'Ghanaian cedi'),
  CurrencyInfo('GIP', 'GIP', 'Gibraltar pound'),
  CurrencyInfo('GMD', 'GMD', 'Gambian dalasi'),
  CurrencyInfo('GNF', 'GNF', 'Guinean franc', minorDigits: 0),
  CurrencyInfo('GTQ', 'Q', 'Guatemalan quetzal'),
  CurrencyInfo('GYD', 'GYD', 'Guyanese dollar'),
  CurrencyInfo('HKD', r'HK$', 'Hong Kong dollar'),
  CurrencyInfo('HNL', 'HNL', 'Honduran lempira'),
  CurrencyInfo('HTG', 'HTG', 'Haitian gourde'),
  CurrencyInfo('HUF', 'Ft', 'Hungarian forint'),
  CurrencyInfo('IDR', 'Rp', 'Indonesian rupiah'),
  CurrencyInfo('ILS', '₪', 'Israeli new shekel'),
  CurrencyInfo('IQD', 'IQD', 'Iraqi dinar', minorDigits: 3),
  CurrencyInfo('IRR', 'IRR', 'Iranian rial'),
  CurrencyInfo('ISK', 'kr', 'Icelandic króna', minorDigits: 0),
  CurrencyInfo('JMD', r'J$', 'Jamaican dollar'),
  CurrencyInfo('JOD', 'JOD', 'Jordanian dinar', minorDigits: 3),
  CurrencyInfo('KES', 'KSh', 'Kenyan shilling'),
  CurrencyInfo('KGS', 'KGS', 'Kyrgyzstani som'),
  CurrencyInfo('KHR', '៛', 'Cambodian riel'),
  CurrencyInfo('KMF', 'KMF', 'Comorian franc', minorDigits: 0),
  CurrencyInfo('KPW', 'KPW', 'North Korean won'),
  CurrencyInfo('KRW', '₩', 'South Korean won', minorDigits: 0),
  CurrencyInfo('KWD', 'KWD', 'Kuwaiti dinar', minorDigits: 3),
  CurrencyInfo('KYD', 'KYD', 'Cayman Islands dollar'),
  CurrencyInfo('KZT', '₸', 'Kazakhstani tenge'),
  CurrencyInfo('LAK', '₭', 'Lao kip'),
  CurrencyInfo('LBP', 'L£', 'Lebanese pound'),
  CurrencyInfo('LKR', 'Rs', 'Sri Lankan rupee'),
  CurrencyInfo('LRD', 'LRD', 'Liberian dollar'),
  CurrencyInfo('LSL', 'LSL', 'Lesotho loti'),
  CurrencyInfo('LYD', 'LYD', 'Libyan dinar', minorDigits: 3),
  CurrencyInfo('MAD', 'MAD', 'Moroccan dirham'),
  CurrencyInfo('MDL', 'MDL', 'Moldovan leu'),
  CurrencyInfo('MGA', 'Ar', 'Malagasy ariary'),
  CurrencyInfo('MKD', 'MKD', 'Macedonian denar'),
  CurrencyInfo('MMK', 'K', 'Myanmar kyat'),
  CurrencyInfo('MNT', '₮', 'Mongolian tögrög'),
  CurrencyInfo('MOP', 'MOP', 'Macanese pataca'),
  CurrencyInfo('MRU', 'MRU', 'Mauritanian ouguiya'),
  CurrencyInfo('MUR', 'Rs', 'Mauritian rupee'),
  CurrencyInfo('MVR', 'MVR', 'Maldivian rufiyaa'),
  CurrencyInfo('MWK', 'MWK', 'Malawian kwacha'),
  CurrencyInfo('MXN', r'MX$', 'Mexican peso'),
  CurrencyInfo('MZN', 'MZN', 'Mozambican metical'),
  CurrencyInfo('NAD', 'NAD', 'Namibian dollar'),
  CurrencyInfo('NGN', '₦', 'Nigerian naira'),
  CurrencyInfo('NIO', r'C$', 'Nicaraguan córdoba'),
  CurrencyInfo('NOK', 'kr', 'Norwegian krone'),
  CurrencyInfo('NPR', 'Rs', 'Nepalese rupee'),
  CurrencyInfo('NZD', r'NZ$', 'New Zealand dollar'),
  CurrencyInfo('OMR', 'OMR', 'Omani rial', minorDigits: 3),
  CurrencyInfo('PAB', 'PAB', 'Panamanian balboa'),
  CurrencyInfo('PEN', 'S/', 'Peruvian sol'),
  CurrencyInfo('PGK', 'PGK', 'Papua New Guinean kina'),
  CurrencyInfo('PHP', '₱', 'Philippine peso'),
  CurrencyInfo('PKR', 'Rs', 'Pakistani rupee'),
  CurrencyInfo('PLN', 'zł', 'Polish złoty'),
  CurrencyInfo('PYG', '₲', 'Paraguayan guaraní', minorDigits: 0),
  CurrencyInfo('RON', 'lei', 'Romanian leu'),
  CurrencyInfo('RSD', 'RSD', 'Serbian dinar'),
  CurrencyInfo('RUB', '₽', 'Russian ruble'),
  CurrencyInfo('RWF', 'RWF', 'Rwandan franc', minorDigits: 0),
  CurrencyInfo('SBD', 'SBD', 'Solomon Islands dollar'),
  CurrencyInfo('SCR', 'SCR', 'Seychellois rupee'),
  CurrencyInfo('SDG', 'SDG', 'Sudanese pound'),
  CurrencyInfo('SEK', 'kr', 'Swedish krona'),
  CurrencyInfo('SHP', 'SHP', 'Saint Helena pound'),
  CurrencyInfo('SLE', 'SLE', 'Sierra Leonean leone'),
  CurrencyInfo('SOS', 'SOS', 'Somali shilling'),
  CurrencyInfo('SRD', 'SRD', 'Surinamese dollar'),
  CurrencyInfo('SSP', 'SSP', 'South Sudanese pound'),
  CurrencyInfo('STN', 'STN', 'São Tomé and Príncipe dobra'),
  CurrencyInfo('SYP', 'SYP', 'Syrian pound'),
  CurrencyInfo('SZL', 'SZL', 'Eswatini lilangeni'),
  CurrencyInfo('THB', '฿', 'Thai baht'),
  CurrencyInfo('TJS', 'TJS', 'Tajikistani somoni'),
  CurrencyInfo('TMT', 'TMT', 'Turkmenistani manat'),
  CurrencyInfo('TND', 'TND', 'Tunisian dinar', minorDigits: 3),
  CurrencyInfo('TOP', 'TOP', 'Tongan paʻanga'),
  CurrencyInfo('TRY', '₺', 'Turkish lira'),
  CurrencyInfo('TTD', r'TT$', 'Trinidad and Tobago dollar'),
  CurrencyInfo('TWD', r'NT$', 'New Taiwan dollar'),
  CurrencyInfo('TZS', 'TSh', 'Tanzanian shilling'),
  CurrencyInfo('UAH', '₴', 'Ukrainian hryvnia'),
  CurrencyInfo('UGX', 'USh', 'Ugandan shilling', minorDigits: 0),
  CurrencyInfo('UYU', r'$U', 'Uruguayan peso'),
  CurrencyInfo('UZS', 'UZS', 'Uzbekistani som'),
  CurrencyInfo('VES', 'VES', 'Venezuelan bolívar'),
  CurrencyInfo('VND', '₫', 'Vietnamese đồng', minorDigits: 0),
  CurrencyInfo('VUV', 'VUV', 'Vanuatu vatu', minorDigits: 0),
  CurrencyInfo('WST', 'WST', 'Samoan tala'),
  CurrencyInfo('XAF', 'FCFA', 'Central African CFA franc', minorDigits: 0),
  CurrencyInfo('XCD', r'EC$', 'East Caribbean dollar'),
  CurrencyInfo('XOF', 'CFA', 'West African CFA franc', minorDigits: 0),
  CurrencyInfo('XPF', 'CFP', 'CFP franc', minorDigits: 0),
  CurrencyInfo('YER', 'YER', 'Yemeni rial'),
  CurrencyInfo('ZAR', 'R', 'South African rand'),
  CurrencyInfo('ZMW', 'ZMW', 'Zambian kwacha'),
  CurrencyInfo('ZWL', 'ZWL', 'Zimbabwean dollar'),
];

CurrencyInfo currencyByCode(String code) => supportedCurrencies.firstWhere(
  (c) => c.code == code,
  orElse: () => supportedCurrencies.first,
);
