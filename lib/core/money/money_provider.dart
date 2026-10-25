import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/appearance_provider.dart';
import 'currency.dart';
import 'money_format.dart';

/// Formatter for the household currency chosen in Appearance.
final moneyFormatterProvider = Provider<MoneyFormatter>((ref) {
  final code = ref.watch(appearanceProvider.select((s) => s.currencyCode));
  return MoneyFormatter(currencyByCode(code), locale: 'en_US');
});
