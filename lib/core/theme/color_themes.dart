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
  ColorThemeId.lavender: ThemePreview(
    Color(0xFF2E2058),
    Color(0xFFF2B84B),
    Color(0xFF4A3A85),
  ),
  ColorThemeId.rose: ThemePreview(
    Color(0xFF4A1530),
    Color(0xFFF5C96B),
    Color(0xFF7A2A52),
  ),
  ColorThemeId.lagoon: ThemePreview(
    Color(0xFF0A3A40),
    Color(0xFFFF9F6B),
    Color(0xFF1D5A62),
  ),
  ColorThemeId.indigo: ThemePreview(
    Color(0xFF141C4A),
    Color(0xFFFFC857),
    Color(0xFF2C3A8A),
  ),
  ColorThemeId.mocha: ThemePreview(
    Color(0xFF3A261B),
    Color(0xFFE8B04B),
    Color(0xFF5C4030),
  ),
  ColorThemeId.citrus: ThemePreview(
    Color(0xFF2A3A0A),
    Color(0xFFFF8A3D),
    Color(0xFF475E12),
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
  ColorThemeId.lavender: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFF6B4FBB),
      hero: Color(0xFF2E2058),
      heroTrack: Color(0xFF4A3A85),
      heroBorder: _clear,
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFFD5CCEE),
      navActiveBackground: Color(0xFFE8E2F7),
      navActiveText: Color(0xFF2E2058),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFFA99BFF),
      hero: Color(0xFF33276A),
      heroTrack: Color(0xFF5A4A9E),
      heroBorder: _clear,
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFF43386F),
      navActiveBackground: Color(0xFF2A2448),
      navActiveText: Color(0xFFA99BFF),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFFA99BFF),
      hero: Color(0xFF1F1740),
      heroTrack: Color(0xFF5A4A9E),
      heroBorder: Color(0xFF3F346F),
      ringAccent: Color(0xFFF2B84B),
      neutralBar: Color(0xFF39305E),
      navActiveBackground: Color(0xFF19162B),
      navActiveText: Color(0xFFA99BFF),
    ),
  },
  ColorThemeId.rose: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFFC2335F),
      hero: Color(0xFF4A1530),
      heroTrack: Color(0xFF7A2A52),
      heroBorder: _clear,
      ringAccent: Color(0xFFF5C96B),
      neutralBar: Color(0xFFF0C6D4),
      navActiveBackground: Color(0xFFF9E0E8),
      navActiveText: Color(0xFF4A1530),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFFF58AAE),
      hero: Color(0xFF5A1D3B),
      heroTrack: Color(0xFF8A3A5E),
      heroBorder: _clear,
      ringAccent: Color(0xFFF5C96B),
      neutralBar: Color(0xFF6A3049),
      navActiveBackground: Color(0xFF3A1F2C),
      navActiveText: Color(0xFFF58AAE),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFFF58AAE),
      hero: Color(0xFF361123),
      heroTrack: Color(0xFF8A3A5E),
      heroBorder: Color(0xFF612942),
      ringAccent: Color(0xFFF5C96B),
      neutralBar: Color(0xFF5A293E),
      navActiveBackground: Color(0xFF23131A),
      navActiveText: Color(0xFFF58AAE),
    ),
  },
  ColorThemeId.lagoon: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFF0E7C86),
      hero: Color(0xFF0A3A40),
      heroTrack: Color(0xFF1D5A62),
      heroBorder: _clear,
      ringAccent: Color(0xFFFF9F6B),
      neutralBar: Color(0xFFB5DCE0),
      navActiveBackground: Color(0xFFD8EEF0),
      navActiveText: Color(0xFF0A3A40),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFF4FD1D9),
      hero: Color(0xFF0F434A),
      heroTrack: Color(0xFF247079),
      heroBorder: _clear,
      ringAccent: Color(0xFFFF9F6B),
      neutralBar: Color(0xFF26565C),
      navActiveBackground: Color(0xFF1B3A3E),
      navActiveText: Color(0xFF4FD1D9),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFF4FD1D9),
      hero: Color(0xFF09282C),
      heroTrack: Color(0xFF247079),
      heroBorder: Color(0xFF194E55),
      ringAccent: Color(0xFFFF9F6B),
      neutralBar: Color(0xFF20494E),
      navActiveBackground: Color(0xFF102325),
      navActiveText: Color(0xFF4FD1D9),
    ),
  },
  ColorThemeId.indigo: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFF3B4CCA),
      hero: Color(0xFF141C4A),
      heroTrack: Color(0xFF2C3A8A),
      heroBorder: _clear,
      ringAccent: Color(0xFFFFC857),
      neutralBar: Color(0xFFC5CBF0),
      navActiveBackground: Color(0xFFE0E4F8),
      navActiveText: Color(0xFF141C4A),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFF8C9BFF),
      hero: Color(0xFF1B2560),
      heroTrack: Color(0xFF36479E),
      heroBorder: _clear,
      ringAccent: Color(0xFFFFC857),
      neutralBar: Color(0xFF323F86),
      navActiveBackground: Color(0xFF222A55),
      navActiveText: Color(0xFF8C9BFF),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFF8C9BFF),
      hero: Color(0xFF10163A),
      heroTrack: Color(0xFF36479E),
      heroBorder: Color(0xFF26326F),
      ringAccent: Color(0xFFFFC857),
      neutralBar: Color(0xFF2A3672),
      navActiveBackground: Color(0xFF141933),
      navActiveText: Color(0xFF8C9BFF),
    ),
  },
  ColorThemeId.mocha: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFF8A5A3B),
      hero: Color(0xFF3A261B),
      heroTrack: Color(0xFF5C4030),
      heroBorder: _clear,
      ringAccent: Color(0xFFE8B04B),
      neutralBar: Color(0xFFE3CDBD),
      navActiveBackground: Color(0xFFF1E4DA),
      navActiveText: Color(0xFF3A261B),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFFD9A07A),
      hero: Color(0xFF45302A),
      heroTrack: Color(0xFF6B4C3C),
      heroBorder: _clear,
      ringAccent: Color(0xFFE8B04B),
      neutralBar: Color(0xFF5A4234),
      navActiveBackground: Color(0xFF33261F),
      navActiveText: Color(0xFFD9A07A),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFFD9A07A),
      hero: Color(0xFF291D19),
      heroTrack: Color(0xFF6B4C3C),
      heroBorder: Color(0xFF4B352A),
      ringAccent: Color(0xFFE8B04B),
      neutralBar: Color(0xFF4C382C),
      navActiveBackground: Color(0xFF1F1713),
      navActiveText: Color(0xFFD9A07A),
    ),
  },
  ColorThemeId.citrus: {
    ThemeVariant.light: _ThemeColors(
      primary: Color(0xFF5C7F0B),
      hero: Color(0xFF2A3A0A),
      heroTrack: Color(0xFF475E12),
      heroBorder: _clear,
      ringAccent: Color(0xFFFF8A3D),
      neutralBar: Color(0xFFD3E2A9),
      navActiveBackground: Color(0xFFE6EFCB),
      navActiveText: Color(0xFF2A3A0A),
    ),
    ThemeVariant.dark: _ThemeColors(
      primary: Color(0xFFA8D44A),
      hero: Color(0xFF324410),
      heroTrack: Color(0xFF52701C),
      heroBorder: _clear,
      ringAccent: Color(0xFFFF8A3D),
      neutralBar: Color(0xFF44601A),
      navActiveBackground: Color(0xFF263311),
      navActiveText: Color(0xFFA8D44A),
    ),
    ThemeVariant.pure: _ThemeColors(
      primary: Color(0xFFA8D44A),
      hero: Color(0xFF1E290A),
      heroTrack: Color(0xFF52701C),
      heroBorder: Color(0xFF394E14),
      ringAccent: Color(0xFFFF8A3D),
      neutralBar: Color(0xFF3A5216),
      navActiveBackground: Color(0xFF171F0A),
      navActiveText: Color(0xFFA8D44A),
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
  'red': Color(0xFFD55E00),
  'orange': Color(0xFFE69F00),
  'yellow': Color(0xFFF0E442),
  'green': Color(0xFF009E73),
  'mint': Color(0xFF44AA99),
  'cyan': Color(0xFF56B4E9),
  'sky': Color(0xFF0072B2),
  'navy': Color(0xFF332288),
  'violet': Color(0xFFAA4499),
  'magenta': Color(0xFF882255),
  'coral': Color(0xFFCC6677),
  'sand': Color(0xFFDDCC77),
  'olive': Color(0xFF999933),
  'slate': Color(0xFF6C7A89),
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
  'red': Color(0xFFD64545),
  'orange': Color(0xFFE8833A),
  'yellow': Color(0xFFD9B21F),
  'green': Color(0xFF3FA564),
  'mint': Color(0xFF5CCFA0),
  'cyan': Color(0xFF2CB5D6),
  'sky': Color(0xFF5B9BE0),
  'navy': Color(0xFF2F4B8F),
  'violet': Color(0xFF7B5CD6),
  'magenta': Color(0xFFC2379A),
  'coral': Color(0xFFEF7B6A),
  'sand': Color(0xFFC9A56B),
  'olive': Color(0xFF7D8B3A),
  'slate': Color(0xFF5E7184),
};
