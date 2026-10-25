import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// Draws a dashed rounded outline around [child] (the invite code box).
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    required this.color,
    this.radius = 20,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedPainter(color, radius),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(1),
      );
    for (final PathMetric metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius;
}
