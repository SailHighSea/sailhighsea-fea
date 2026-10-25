import 'package:flutter/material.dart';

/// Design tokens from docs/SPEC.md section 2. Every colour the UI uses comes from here,
/// so switching mode or colour theme restyles the app without touching any screen.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.muted,
    required this.primary,
    required this.onPrimary,
    required this.hero,
    required this.heroTrack,
    required this.heroMuted,
    required this.heroText,
    required this.heroBorder,
    required this.ringAccent,
    required this.neutralBar,
    required this.navRail,
    required this.navActiveBackground,
    required this.navActiveText,
    required this.sidebar,
    required this.sidebarActive,
    required this.sidebarText,
    required this.sidebarBorder,
    required this.amberText,
    required this.amber,
    required this.amberBar,
    required this.blue,
    required this.purple,
    required this.rose,
    required this.grey,
    required this.toggleOff,
    required this.chipBorder,
    required this.avatars,
    required this.categoryPalette,
  });

  final Color background;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color primary;
  final Color onPrimary;

  final Color hero;
  final Color heroTrack;
  final Color heroMuted;
  final Color heroText;
  final Color heroBorder;
  final Color ringAccent;

  final Color neutralBar;

  final Color navRail;
  final Color navActiveBackground;
  final Color navActiveText;
  final Color sidebar;
  final Color sidebarActive;
  final Color sidebarText;
  final Color sidebarBorder;

  final Color amberText;
  final Color amber;
  final Color amberBar;
  final Color blue;
  final Color purple;
  final Color rose;
  final Color grey;
  final Color toggleOff;
  final Color chipBorder;

  /// Member avatar background / foreground pairs (sidebar footer, lists).
  final List<AvatarColors> avatars;

  /// Category colours keyed by category colour key (`food`, `bills`, ...).
  /// Swapped for a colour-blind safe palette when that option is on.
  final Map<String, Color> categoryPalette;

  /// Colour for a category colour key; unknown keys fall back to the neutral grey.
  Color categoryColor(String key) => categoryPalette[key] ?? grey;

  @override
  AppTokens copyWith({
    Color? background,
    Color? surface,
    Color? border,
    Color? text,
    Color? muted,
    Color? primary,
    Color? onPrimary,
    Color? hero,
    Color? heroTrack,
    Color? heroMuted,
    Color? heroText,
    Color? heroBorder,
    Color? ringAccent,
    Color? neutralBar,
    Color? navRail,
    Color? navActiveBackground,
    Color? navActiveText,
    Color? sidebar,
    Color? sidebarActive,
    Color? sidebarText,
    Color? sidebarBorder,
    Color? amberText,
    Color? amber,
    Color? amberBar,
    Color? blue,
    Color? purple,
    Color? rose,
    Color? grey,
    Color? toggleOff,
    Color? chipBorder,
    List<AvatarColors>? avatars,
    Map<String, Color>? categoryPalette,
  }) {
    return AppTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      hero: hero ?? this.hero,
      heroTrack: heroTrack ?? this.heroTrack,
      heroMuted: heroMuted ?? this.heroMuted,
      heroText: heroText ?? this.heroText,
      heroBorder: heroBorder ?? this.heroBorder,
      ringAccent: ringAccent ?? this.ringAccent,
      neutralBar: neutralBar ?? this.neutralBar,
      navRail: navRail ?? this.navRail,
      navActiveBackground: navActiveBackground ?? this.navActiveBackground,
      navActiveText: navActiveText ?? this.navActiveText,
      sidebar: sidebar ?? this.sidebar,
      sidebarActive: sidebarActive ?? this.sidebarActive,
      sidebarText: sidebarText ?? this.sidebarText,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      amberText: amberText ?? this.amberText,
      amber: amber ?? this.amber,
      amberBar: amberBar ?? this.amberBar,
      blue: blue ?? this.blue,
      purple: purple ?? this.purple,
      rose: rose ?? this.rose,
      grey: grey ?? this.grey,
      toggleOff: toggleOff ?? this.toggleOff,
      chipBorder: chipBorder ?? this.chipBorder,
      avatars: avatars ?? this.avatars,
      categoryPalette: categoryPalette ?? this.categoryPalette,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      border: l(border, other.border),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      hero: l(hero, other.hero),
      heroTrack: l(heroTrack, other.heroTrack),
      heroMuted: l(heroMuted, other.heroMuted),
      heroText: l(heroText, other.heroText),
      heroBorder: l(heroBorder, other.heroBorder),
      ringAccent: l(ringAccent, other.ringAccent),
      neutralBar: l(neutralBar, other.neutralBar),
      navRail: l(navRail, other.navRail),
      navActiveBackground: l(navActiveBackground, other.navActiveBackground),
      navActiveText: l(navActiveText, other.navActiveText),
      sidebar: l(sidebar, other.sidebar),
      sidebarActive: l(sidebarActive, other.sidebarActive),
      sidebarText: l(sidebarText, other.sidebarText),
      sidebarBorder: l(sidebarBorder, other.sidebarBorder),
      amberText: l(amberText, other.amberText),
      amber: l(amber, other.amber),
      amberBar: l(amberBar, other.amberBar),
      blue: l(blue, other.blue),
      purple: l(purple, other.purple),
      rose: l(rose, other.rose),
      grey: l(grey, other.grey),
      toggleOff: l(toggleOff, other.toggleOff),
      chipBorder: l(chipBorder, other.chipBorder),
      avatars: t < 0.5 ? avatars : other.avatars,
      categoryPalette: {
        for (final key in categoryPalette.keys)
          key: l(
            categoryPalette[key]!,
            other.categoryPalette[key] ?? categoryPalette[key]!,
          ),
      },
    );
  }
}

@immutable
class AvatarColors {
  const AvatarColors(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

extension AppTokensContext on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}
