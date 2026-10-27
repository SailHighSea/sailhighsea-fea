import 'package:flutter/material.dart';

import 'appearance_settings.dart';
import 'color_themes.dart';
import 'header_gradient.dart';

/// The soft backdrop the Glass look sits on when no picture is chosen: a few blurred colour
/// patches from the colour theme, pale in Light and deep in Dark and Pure black.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.theme, required this.variant});

  final ColorThemeId theme;
  final ThemeVariant variant;

  @override
  Widget build(BuildContext context) {
    final (a, b) = headerGradientFor(theme, ThemeVariant.light);
    final accent = previewFor(theme).accent;
    final light = variant == ThemeVariant.light;
    Color tone(Color c, double amount) => light
        ? Color.lerp(c, Colors.white, 1 - amount)!
        : Color.lerp(Colors.black, c, amount)!;
    final base = light
        ? Color.lerp(a, Colors.white, 0.88)!
        : (variant == ThemeVariant.pure
              ? Colors.black
              : Color.lerp(Colors.black, a, 0.22)!);
    Widget patch(Alignment at, Color c, double radius) => Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: at,
            radius: radius,
            colors: [c, c.withValues(alpha: 0)],
          ),
        ),
      ),
    );
    // Painted once and kept as a picture: scrolling the page above never redraws it.
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: base),
            patch(
              const Alignment(-0.8, -0.7),
              tone(a, light ? 0.55 : 0.55),
              0.9,
            ),
            patch(const Alignment(0.9, -0.2), tone(b, light ? 0.5 : 0.5), 0.8),
            patch(
              const Alignment(-0.3, 0.9),
              tone(accent, light ? 0.45 : 0.30),
              0.9,
            ),
          ],
        ),
      ),
    );
  }
}
