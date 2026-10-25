import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appearance_settings.dart';

/// Overridden in `main()` (and in tests) once SharedPreferences has loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

const _kMode = 'appearance.mode';
const _kTheme = 'appearance.colorTheme';
const _kLargerText = 'appearance.largerText';
const _kColorBlind = 'appearance.colorBlindCharts';
const _kCurrency = 'appearance.currency';

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// Appearance choices, persisted locally so they survive restarts.
class AppearanceController extends Notifier<AppearanceSettings> {
  late SharedPreferences _prefs;

  @override
  AppearanceSettings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return AppearanceSettings(
      mode: _enumByName(
        AppearanceMode.values,
        _prefs.getString(_kMode),
        AppearanceMode.system,
      ),
      colorTheme: _enumByName(
        ColorThemeId.values,
        _prefs.getString(_kTheme),
        ColorThemeId.forest,
      ),
      largerText: _prefs.getBool(_kLargerText) ?? false,
      colorBlindCharts: _prefs.getBool(_kColorBlind) ?? false,
      currencyCode: _prefs.getString(_kCurrency) ?? 'SGD',
    );
  }

  Future<void> setMode(AppearanceMode mode) {
    state = state.copyWith(mode: mode);
    return _prefs.setString(_kMode, mode.name);
  }

  Future<void> setColorTheme(ColorThemeId theme) {
    state = state.copyWith(colorTheme: theme);
    return _prefs.setString(_kTheme, theme.name);
  }

  Future<void> setLargerText(bool value) {
    state = state.copyWith(largerText: value);
    return _prefs.setBool(_kLargerText, value);
  }

  Future<void> setColorBlindCharts(bool value) {
    state = state.copyWith(colorBlindCharts: value);
    return _prefs.setBool(_kColorBlind, value);
  }

  Future<void> setCurrency(String code) {
    state = state.copyWith(currencyCode: code);
    return _prefs.setString(_kCurrency, code);
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceController, AppearanceSettings>(
      AppearanceController.new,
    );
