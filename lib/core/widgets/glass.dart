import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Whether cards and bars are drawn as frosted glass: translucent, blurring what is behind them,
/// with a thin light edge. Switched on in the app's builder when a personal background is set and
/// the person left "Glass cards and bars" on.
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(GlassScope old) => old.enabled != enabled;
}

/// The glass look around [child]: a see-through tint of [color], a soft light sheen from the top
/// left and a thin light edge. No live blur: the backdrop behind is already soft (or blurred once
/// when it is a picture), and a blur filter per card is what made scrolling slow. [color] is the
/// solid surface it replaces; the tint keeps enough of it for text to keep its contrast.
class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = BorderRadius.zero,
    this.onlyTopEdge = false,
    this.strength = 1,
    this.blur = 0,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;

  /// A bar along the bottom of the screen draws its edge on top only.
  final bool onlyTopEdge;

  /// 1 is the card look; a bar with small text on it uses more (it is clamped so some of the
  /// background always shows through).
  final double strength;

  /// Frosted blur of what scrolls behind, in pixels. Only for the one or two surfaces that
  /// content passes under (the bottom bar, the overview card); a blur on every card is what made
  /// scrolling slow, and over the still backdrop it would show nothing.
  final double blur;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final edge = Colors.white.withValues(alpha: dark ? 0.16 : 0.55);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: color.withValues(
          alpha: ((dark ? 0.58 : 0.64) * strength).clamp(0.0, 0.88),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.10 : 0.30),
            Colors.white.withValues(alpha: 0),
          ],
        ),
        border: onlyTopEdge
            ? Border(top: BorderSide(color: edge))
            : Border.all(color: edge),
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
    if (blur <= 0) return box;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.clamp,
        ),
        child: box,
      ),
    );
  }
}
