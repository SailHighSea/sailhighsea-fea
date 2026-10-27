import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'personal_look.dart';
import 'preset_pictures.dart';

/// Paints a [BackgroundStyle] to fill its parent: a colour, a gradient, or a picture with blur
/// and dimming. Draws nothing for [BackgroundStyle.none].
class PersonalBackground extends StatelessWidget {
  const PersonalBackground({super.key, required this.style, this.minBlur = 0});

  final BackgroundStyle style;

  /// At least this much blur (the Glass look softens a picture once, here, instead of blurring
  /// behind every card).
  final int minBlur;

  @override
  Widget build(BuildContext context) {
    if (!style.active) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: switch (style.kind) {
        BackgroundKind.solid => ColoredBox(
          color: Color(style.color),
          child: const SizedBox.expand(),
        ),
        BackgroundKind.gradient => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              // 0 degrees points up, going clockwise (like CSS).
              begin: _alignment(style.angle + 180),
              end: _alignment(style.angle),
              colors: style.gradientColors,
            ),
          ),
          child: const SizedBox.expand(),
        ),
        BackgroundKind.picture => RepaintBoundary(
          child: _Picture(
            style: minBlur > style.blur ? style.copyWith(blur: minBlur) : style,
          ),
        ),
        BackgroundKind.none => const SizedBox.shrink(),
      },
    );
  }
}

Alignment _alignment(int degrees) {
  final r = degrees * math.pi / 180;
  return Alignment(math.sin(r), -math.cos(r));
}

class _Picture extends StatelessWidget {
  const _Picture({required this.style});
  final BackgroundStyle style;

  @override
  Widget build(BuildContext context) {
    final path = style.picturePath!;
    final fallback = ColoredBox(color: context.tokens.background);
    Widget image = isPresetPath(path)
        ? Image.asset(
            path.substring('asset:'.length),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.file(
            File(path),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
          );
    if (style.blur > 0) {
      image = ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: style.blur.toDouble(),
            sigmaY: style.blur.toDouble(),
            tileMode: TileMode.clamp,
          ),
          child: image,
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (style.dim > 0)
          ColoredBox(color: Colors.black.withValues(alpha: style.dim / 100)),
      ],
    );
  }
}
