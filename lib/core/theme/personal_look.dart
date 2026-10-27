import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance_provider.dart';

/// What sits behind a screen or a card.
enum BackgroundKind { none, solid, gradient, picture }

/// How the text on top is coloured: from the brightness behind it, or forced.
enum TextTone { auto, light, dark }

/// Plain colours people can choose from (ARGB).
const kBackgroundColors = <int>[
  0xFFF4F6F5,
  0xFF0E1512,
  0xFF000000,
  0xFFDCEFE6,
  0xFFDCEAF5,
  0xFFF6E0DA,
  0xFFE8E2F7,
  0xFFF9E0E8,
  0xFFD8EEF0,
  0xFFF1E4DA,
  0xFFE6EFCB,
  0xFF2E2058,
];

/// Two-colour gradients people can choose from (ARGB, start and end).
const kBackgroundGradients = <(int, int)>[
  (0xFF0B6E4F, 0xFF0B3D2E),
  (0xFF1B6FA8, 0xFF0B2F4E),
  (0xFFF28C28, 0xFF7A3329),
  (0xFF6B4FBB, 0xFF2E2058),
  (0xFFC2335F, 0xFF4A1530),
  (0xFF0E7C86, 0xFF0A3A40),
  (0xFFF2B84B, 0xFFB8432F),
  (0xFF3B4CCA, 0xFF141C4A),
  (0xFF9AA8A1, 0xFF161B1F),
  (0xFFDCEFE6, 0xFFB7D0E4),
  (0xFFF9E0E8, 0xFFE8E2F7),
  (0xFFFFD6A5, 0xFFFFADAD),
];

/// Perceived brightness of a colour, 0 (black) to 1 (white).
double luminanceOf(int argb) {
  final r = (argb >> 16) & 255, g = (argb >> 8) & 255, b = argb & 255;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

/// A background for a screen or a card. Immutable; stored as JSON.
@immutable
class BackgroundStyle {
  const BackgroundStyle({
    this.kind = BackgroundKind.none,
    this.color = 0xFFF4F6F5,
    this.gradient = 0,
    this.angle = 160,
    this.picturePath,
    this.pictureLuminance = 0.5,
    this.blur = 0,
    this.dim = 35,
    this.tone = TextTone.auto,
    this.glass = true,
  });

  static const none = BackgroundStyle();

  final BackgroundKind kind;
  final int color;

  /// Index into [kBackgroundGradients].
  final int gradient;

  /// Degrees, 0 to 360.
  final int angle;
  final String? picturePath;

  /// Average brightness of the stored picture, measured when it was chosen.
  final double pictureLuminance;

  /// Blur radius for a picture, 0 to 24.
  final int blur;

  /// How much black is laid over a picture, percent, 0 to 80.
  final int dim;
  final TextTone tone;

  /// Cards and the bottom bar drawn as frosted glass over the background (the page style only).
  final bool glass;

  bool get active =>
      kind != BackgroundKind.none &&
      (kind != BackgroundKind.picture || picturePath != null);

  List<Color> get gradientColors {
    final g =
        kBackgroundGradients[gradient.clamp(
          0,
          kBackgroundGradients.length - 1,
        )];
    return [Color(g.$1), Color(g.$2)];
  }

  /// Brightness of what the text sits on, after any dimming.
  double get luminance => switch (kind) {
    BackgroundKind.none => 1,
    BackgroundKind.solid => luminanceOf(color),
    BackgroundKind.gradient =>
      (luminanceOf(kBackgroundGradients[gradient].$1) +
              luminanceOf(kBackgroundGradients[gradient].$2)) /
          2,
    BackgroundKind.picture => pictureLuminance * (1 - dim / 100),
  };

  /// Whether the text on top is light (the background is dark).
  bool get lightText => switch (tone) {
    TextTone.light => true,
    TextTone.dark => false,
    TextTone.auto => luminance < 0.5,
  };

  /// WCAG-style contrast between the background and the text colour in use.
  double get contrast {
    double lin(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final bg = lin(luminance.clamp(0.0, 1.0));
    final fg = lightText ? 1.0 : 0.0;
    final hi = bg > fg ? bg : fg, lo = bg > fg ? fg : bg;
    return (hi + 0.05) / (lo + 0.05);
  }

  BackgroundStyle copyWith({
    BackgroundKind? kind,
    int? color,
    int? gradient,
    int? angle,
    String? picturePath,
    double? pictureLuminance,
    int? blur,
    int? dim,
    TextTone? tone,
    bool? glass,
  }) => BackgroundStyle(
    kind: kind ?? this.kind,
    color: color ?? this.color,
    gradient: gradient ?? this.gradient,
    angle: angle ?? this.angle,
    picturePath: picturePath ?? this.picturePath,
    pictureLuminance: pictureLuminance ?? this.pictureLuminance,
    blur: blur ?? this.blur,
    dim: dim ?? this.dim,
    tone: tone ?? this.tone,
    glass: glass ?? this.glass,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'color': color,
    'gradient': gradient,
    'angle': angle,
    'picturePath': picturePath,
    'pictureLuminance': pictureLuminance,
    'blur': blur,
    'dim': dim,
    'tone': tone.name,
    'glass': glass,
  };

  static BackgroundStyle fromJson(Map<String, Object?> j) {
    T byName<T extends Enum>(List<T> v, Object? n, T d) {
      for (final e in v) {
        if (e.name == n) return e;
      }
      return d;
    }

    int n(Object? v, int d, int lo, int hi) => v is int ? v.clamp(lo, hi) : d;
    return BackgroundStyle(
      kind: byName(BackgroundKind.values, j['kind'], BackgroundKind.none),
      color: j['color'] is int ? j['color']! as int : 0xFFF4F6F5,
      gradient: n(j['gradient'], 0, 0, kBackgroundGradients.length - 1),
      angle: n(j['angle'], 160, 0, 360),
      picturePath: j['picturePath'] as String?,
      pictureLuminance: j['pictureLuminance'] is num
          ? (j['pictureLuminance']! as num).toDouble().clamp(0.0, 1.0)
          : 0.5,
      blur: n(j['blur'], 0, 0, 24),
      dim: n(j['dim'], 35, 0, 80),
      tone: byName(TextTone.values, j['tone'], TextTone.auto),
      glass: j['glass'] is bool ? j['glass']! as bool : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackgroundStyle &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// The app's two personal backgrounds: behind every screen, and behind the Home hero card.
@immutable
class PersonalLook {
  const PersonalLook({
    this.page = BackgroundStyle.none,
    this.card = BackgroundStyle.none,
  });

  final BackgroundStyle page;
  final BackgroundStyle card;

  PersonalLook copyWith({BackgroundStyle? page, BackgroundStyle? card}) =>
      PersonalLook(page: page ?? this.page, card: card ?? this.card);
}

const _kLook = 'personal.look';

class PersonalLookController extends Notifier<PersonalLook> {
  late final _prefs = ref.watch(sharedPreferencesProvider);

  @override
  PersonalLook build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_kLook);
    if (raw == null) return const PersonalLook();
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      return PersonalLook(
        page: BackgroundStyle.fromJson(
          (j['page'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
        card: BackgroundStyle.fromJson(
          (j['card'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
      );
    } on Object {
      return const PersonalLook();
    }
  }

  Future<void> _save(PersonalLook look) {
    state = look;
    return _prefs.setString(
      _kLook,
      jsonEncode({'page': look.page.toJson(), 'card': look.card.toJson()}),
    );
  }

  Future<void> setPage(BackgroundStyle s) => _save(state.copyWith(page: s));
  Future<void> setCard(BackgroundStyle s) => _save(state.copyWith(card: s));

  /// Puts both back to the theme.
  Future<void> reset() => _save(const PersonalLook());
}

final personalLookProvider =
    NotifierProvider<PersonalLookController, PersonalLook>(
      PersonalLookController.new,
    );
