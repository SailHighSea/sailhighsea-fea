import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'appearance_settings.dart';

enum ThemeVariant { light, dark, pure }

/// Hero card swatches shown in Appearance (docs/SPEC.md section 2).
class ThemePreview {
  const ThemePreview(this.hero, this.accent, this.track);
  final Color hero;
  final Color accent;
  final Color track;
}

const _previews = {
  ColorThemeId.forest: ThemePreview(
    Color(0xFF0B3D2E),
    Color(0xFFF2B84B),
    Color(0xFF1F5A47),
  ),
  ColorThemeId.ocean: ThemePreview(
    Color(0xFF0B2F4E),
    Color(0xFFF28C28),
    Color(0xFF1B4F7A),
  ),
  ColorThemeId.sunset: ThemePreview(
    Color(0xFF4A1F1A),
    Color(0xFFF2B84B),
    Color(0xFF7A3329),
  ),
  ColorThemeId.graphite: ThemePreview(
    Color(0xFF161B1F),
    Color(0xFF6FB3D9),
    Color(0xFF3D4852),
  ),
};

ThemePreview previewFor(ColorThemeId id) => _previews[id]!;

/// What a mode contributes regardless of colour theme: surfaces, text and shared colours.
class _ModeBase {
  const _ModeBase({
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.onPrimary,
    required this.navRail,
    required this.amberText,
    required this.grey,
    required this.toggleOff,
    required this.chipBorder,
  });

  final Color background;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color onPrimary;
  final Color navRail;
  final Color amberText;
  final Color grey;
  final Color toggleOff;
  final Color chipBorder;
}

const _modeBases = {
  ThemeVariant.light: _ModeBase(
    background: Color(0xFFF4F6F5),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFE3E8E5),
    text: Color(0xFF0F1F1A),
    muted: Color(0xFF55645D),
    onPrimary: Color(0xFFFFFFFF),
    navRail: Color(0xFFFFFFFF),
    amberText: Color(0xFF8A5A00),
    grey: Color(0xFF9AA8A1),
    toggleOff: Color(0xFFC9D3CE),
    chipBorder: Color(0x00000000),
  ),
  ThemeVariant.dark: _ModeBase(
    background: Color(0xFF0E1512),
    surface: Color(0xFF17211C),
    border: Color(0xFF26332C),
    text: Color(0xFFE8F0EC),
    muted: Color(0xFF9DB0A6),
    onPrimary: Color(0xFF0E1512),
    navRail: Color(0xFF17211C),
    amberText: Color(0xFFF2B84B),
    grey: Color(0xFF7B8A83),
    toggleOff: Color(0xFF33423A),
    chipBorder: Color(0xFF26332C),
  ),
  ThemeVariant.pure: _ModeBase(
    background: Color(0xFF000000),
    surface: Color(0xFF0A0F0D),
    border: Color(0xFF1F2B26),
    text: Color(0xFFF2F7F4),
    muted: Color(0xFF9DB0A6),
    onPrimary: Color(0xFF000000),
    navRail: Color(0xFF000000),
    amberText: Color(0xFFF2B84B),
    grey: Color(0xFF7B8A83),
    toggleOff: Color(0xFF26332C),
    chipBorder: Color(0xFF1F2B26),
  ),
};

/// What a colour theme contributes for one variant.
class _ThemeColors {
  const _ThemeColors({
    required this.primary,
    required this.hero,
    required this.heroTrack,
    required this.heroBorder,
    required this.ringAccent,
    required this.neutralBar,
    required this.navActiveBackground,
    required this.navActiveText,
  });

  final Color primary;
  final Color hero;
  final Color heroTrack;
  final Color heroBorder;
  final Color ringAccent;
  final Color neutralBar;
  final Color navActiveBackground;
  final Color navActiveText;
}

const _clear = Color(0x00000000);

// Forest values are exactly the SPEC table. The other themes keep the same structure;
// their colours are defaults and easy to retune here.
const _themeColors = {
  ColorThemeId.forest: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFF0B6E4F),
      hero: Color(0xFF0B3D2E),
      heroTrack: Color(0xFF1F5A47),
      heroBorder: _clear,
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFFB9D9CB),
      navActiveBackground: Color(0xFFDCEFE6),
      navActiveText: Color(0xFF0B3D2E),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFF4CC38A),
      hero: Color(0xFF123F31),
      heroTrack: Color(0xFF2A6150),
      heroBorder: _clear,
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFF2F5B4A),
      navActiveBackground: Color(0xFF1F3A30),
      navActiveText: Color(0xFF4CC38A),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFF4CC38A),
      hero: Color(0xFF0B2E23),
      heroTrack: Color(0xFF1F5A47),
      heroBorder: Color(0xFF14463A),
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFF2A5646),
      navActiveBackground: Color(0xFF0F2A21),
      navActiveText: Color(0xFF4CC38A),
    ),
  },
  ColorThemeId.ocean: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFF1B6FA8),
      hero: Color(0xFF0B2F4E),
      heroTrack: Color(0xFF1B4F7A),
      heroBorder: _clear,
      ringAccent: Color(0xFFF28C28),
      neutralBar: Color(0xFFB7D0E4),
      navActiveBackground: Color(0xFFDCEAF5),
      navActiveText: Color(0xFF0B2F4E),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFF6FB3D9),
      hero: Color(0xFF12395C),
      heroTrack: Color(0xFF28608F),
      heroBorder: _clear,
      ringAccent: Color(0xFFF28C28),
      neutralBar: Color(0xFF2B4E6E),
      navActiveBackground: Color(0xFF1D3550),
      navActiveText: Color(0xFF6FB3D9),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFF6FB3D9),
      hero: Color(0xFF08243C),
      heroTrack: Color(0xFF1B4F7A),
      heroBorder: Color(0xFF123F66),
      ringAccent: Color(0xFFF28C28),
      neutralBar: Color(0xFF234563),
      navActiveBackground: Color(0xFF0E2338),
      navActiveText: Color(0xFF6FB3D9),
    ),
  },
  ColorThemeId.sunset: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFFB2452D),
      hero: Color(0xFF4A1F1A),
      heroTrack: Color(0xFF7A3329),
      heroBorder: _clear,
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFFE8C5BC),
      navActiveBackground: Color(0xFFF6E3DD),
      navActiveText: Color(0xFF4A1F1A),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFFF0997F),
      hero: Color(0xFF5A2720),
      heroTrack: Color(0xFF8A4034),
      heroBorder: _clear,
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFF5E3A33),
      navActiveBackground: Color(0xFF4A2A24),
      navActiveText: Color(0xFFF0997F),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFFF0997F),
      hero: Color(0xFF381714),
      heroTrack: Color(0xFF7A3329),
      heroBorder: Color(0xFF5A2720),
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFF4F2F29),
      navActiveBackground: Color(0xFF2A1512),
      navActiveText: Color(0xFFF0997F),
    ),
  },
  ColorThemeId.graphite: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFF2F3A43),
      hero: Color(0xFF161B1F),
      heroTrack: Color(0xFF3D4852),
      heroBorder: _clear,
      ringAccent: Color(0xFF6FB3D9),
      neutralBar: Color(0xFFC5CDD3),
      navActiveBackground: Color(0xFFE3E8EB),
      navActiveText: Color(0xFF161B1F),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFF6FB3D9),
      hero: Color(0xFF1E252A),
      heroTrack: Color(0xFF4A5560),
      heroBorder: _clear,
      ringAccent: Color(0xFF6FB3D9),
      neutralBar: Color(0xFF3A464F),
      navActiveBackground: Color(0xFF2A343B),
      navActiveText: Color(0xFF6FB3D9),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFF6FB3D9),
      hero: Color(0xFF0F1417),
      heroTrack: Color(0xFF3D4852),
      heroBorder: Color(0xFF2A343B),
      ringAccent: Color(0xFF6FB3D9),
      neutralBar: Color(0xFF333E46),
      navActiveBackground: Color(0xFF1A2126),
      navActiveText: Color(0xFF6FB3D9),
    ),
  },
};

const _avatarColors = [
  AvatarColors(Color(0xFFFFFFFF), Color(0xFF0B3D2E)),
  AvatarColors(Color(0xFFFBE9C4), Color(0xFF4A3200)),
  AvatarColors(Color(0xFFE6E2F3), Color(0xFF4B3F8A)),
];

const _heroMuted = Color(0xFFBFD8CC);
const _white = Color(0xFFFFFFFF);
const _amber = Color(0xFFF2B84B);
const _amberBar = Color(0xFFE0A020);
const _blue = Color(0xFF6FB3D9);
const _purple = Color(0xFF8A7FB8);
const _rose = Color(0xFFD9776B);

// Okabe-Ito based palette, distinguishable under the common colour-vision deficiencies.
const _colorBlindPalette = {
  'food': Color(0xFF009E73),
  'bills': Color(0xFF56B4E9),
  'transport': Color(0xFFE69F00),
  'fun': Color(0xFFCC79A7),
  'health': Color(0xFFD55E00),
  'other': Color(0xFF9AA8A1),
  'purple2': Color(0xFF0072B2),
  'teal': Color(0xFF44AA99),
  'pink': Color(0xFF882255),
  'indigo': Color(0xFF332288),
  'lime': Color(0xFFDDCC77),
  'brown': Color(0xFF999999),
};

AppTokens tokensFor(
  ColorThemeId theme,
  ThemeVariant variant, {
  bool colorBlind = false,
}) {
  final base = _modeBases[variant]!;
  final colors = _themeColors[theme]![variant]!;
  final palette = colorBlind
      ? _colorBlindPalette
      : {
          'food': colors.primary,
          'bills': _blue,
          'transport': _amberBar,
          'fun': _purple,
          'health': _rose,
          'other': base.grey,
          ..._extraCategoryColors,
        };
  return AppTokens(
    background: base.background,
    surface: base.surface,
    border: base.border,
    text: base.text,
    muted: base.muted,
    primary: colors.primary,
    onPrimary: base.onPrimary,
    hero: colors.hero,
    heroTrack: colors.heroTrack,
    heroMuted: _heroMuted,
    heroText: _white,
    heroBorder: colors.heroBorder,
    ringAccent: colors.ringAccent,
    neutralBar: colors.neutralBar,
    navRail: base.navRail,
    navActiveBackground: colors.navActiveBackground,
    navActiveText: colors.navActiveText,
    // Desktop sidebar: hero green in Light/Dark, true black in Pure black.
    sidebar: variant == ThemeVariant.pure ? base.background : colors.hero,
    sidebarActive: colors.heroTrack,
    sidebarText: _heroMuted,
    sidebarBorder: variant == ThemeVariant.pure ? base.border : _clear,
    amberText: base.amberText,
    amber: _amber,
    amberBar: _amberBar,
    blue: _blue,
    purple: _purple,
    rose: _rose,
    grey: base.grey,
    toggleOff: base.toggleOff,
    chipBorder: base.chipBorder,
    avatars: _avatarColors,
    categoryPalette: palette,
  );
}

/// Colours for categories people add themselves (see `newCategoryColorKeys`).
const _extraCategoryColors = {
  'purple2': Color(0xFFB05FCB),
  'teal': Color(0xFF2BA7A0),
  'pink': Color(0xFFD96BA0),
  'indigo': Color(0xFF4A63C9),
  'lime': Color(0xFF8DB83A),
  'brown': Color(0xFFA8774F),
};
