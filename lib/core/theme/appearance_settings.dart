import 'package:flutter/foundation.dart';

/// Light/Dark/Pure black, or follow the system (which never picks Pure black).
enum AppearanceMode {
  system('System'),
  light('Light'),
  dark('Dark'),
  pureBlack('Pure black');

  const AppearanceMode(this.label);
  final String label;
}

/// Colour themes swap the hero card and accent colours (docs/SPEC.md section 2).
enum ColorThemeId {
  forest('Forest'),
  ocean('Ocean'),
  sunset('Sunset'),
  graphite('Graphite'),
  lavender('Lavender'),
  rose('Rose'),
  lagoon('Lagoon'),
  indigo('Indigo'),
  mocha('Mocha'),
  citrus('Citrus');

  const ColorThemeId(this.label);
  final String label;
}

/// Standard is solid cards and a flat bar; Glass is see-through cards over a soft backdrop with a
/// floating glass bottom bar.
enum AppLook {
  standard('Standard'),
  glass('Glass');

  const AppLook(this.label);
  final String label;
}

/// The top of Home: the plain month row, or a gradient band with the logo, name and person.
enum HomeHeaderStyle {
  classic('Classic'),
  gradient('Gradient');

  const HomeHeaderStyle(this.label);
  final String label;
}

@immutable
class AppearanceSettings {
  const AppearanceSettings({
    this.mode = AppearanceMode.system,
    this.colorTheme = ColorThemeId.forest,
    this.largerText = false,
    this.colorBlindCharts = false,
    this.currencyCode = 'SGD',
    this.homeHeader = HomeHeaderStyle.gradient,
    this.look = AppLook.standard,
    this.lightEffects = false,
  });

  final AppearanceMode mode;
  final ColorThemeId colorTheme;
  final bool largerText;
  final bool colorBlindCharts;
  final String currencyCode;
  final HomeHeaderStyle homeHeader;
  final AppLook look;

  /// Draws without blur and soft shadows: smoother on older or slower devices.
  final bool lightEffects;

  AppearanceSettings copyWith({
    AppearanceMode? mode,
    ColorThemeId? colorTheme,
    bool? largerText,
    bool? colorBlindCharts,
    String? currencyCode,
    HomeHeaderStyle? homeHeader,
    AppLook? look,
    bool? lightEffects,
  }) {
    return AppearanceSettings(
      mode: mode ?? this.mode,
      colorTheme: colorTheme ?? this.colorTheme,
      largerText: largerText ?? this.largerText,
      colorBlindCharts: colorBlindCharts ?? this.colorBlindCharts,
      currencyCode: currencyCode ?? this.currencyCode,
      homeHeader: homeHeader ?? this.homeHeader,
      look: look ?? this.look,
      lightEffects: lightEffects ?? this.lightEffects,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.mode == mode &&
      other.colorTheme == colorTheme &&
      other.largerText == largerText &&
      other.colorBlindCharts == colorBlindCharts &&
      other.currencyCode == currencyCode &&
      other.homeHeader == homeHeader &&
      other.look == look &&
      other.lightEffects == lightEffects;

  @override
  int get hashCode => Object.hash(
    mode,
    colorTheme,
    largerText,
    colorBlindCharts,
    currencyCode,
    homeHeader,
    look,
    lightEffects,
  );
}
