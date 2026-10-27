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

/// The glass look around [child]: the blur, a tint of [color], a soft light sheen from the top
/// left and a thin edge. [color] is the solid surface it replaces; the glass is a see-through
/// version of it so text keeps its contrast.
class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = BorderRadius.zero,
    this.blur = 22,
    this.onlyTopEdge = false,
    this.strength = 1,
  });

  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final double blur;

  /// A bar along the bottom of the screen draws its edge on top only.
  final bool onlyTopEdge;

  /// 1 is the card look; a bar with small text on it uses more (it is clamped so some of the
  /// background always shows through).
  final double strength;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final edge = Colors.white.withValues(alpha: dark ? 0.16 : 0.55);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
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
          child: child,
        ),
      ),
    );
  }
}
