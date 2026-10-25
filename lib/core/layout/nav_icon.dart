import 'package:flutter/material.dart';

import 'destinations.dart';

/// Icon for a destination. Insights and Goals are drawn to match the thin outline style
/// of the mockups; the rest use Material outline icons.
class NavIcon extends StatelessWidget {
  const NavIcon(
    this.destination, {
    super.key,
    required this.size,
    required this.color,
  });

  final AppDestination destination;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    switch (destination) {
      case AppDestination.insights:
        return CustomPaint(
          size: Size.square(size),
          painter: _BarsPainter(color),
        );
      case AppDestination.goals:
        return CustomPaint(
          size: Size.square(size),
          painter: _TargetPainter(color),
        );
      default:
        return Icon(destination.icon, size: size, color: color);
    }
  }
}

Paint _stroke(Color color, double scale) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.8 * scale
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = _stroke(color, s);
    canvas
      ..drawLine(Offset(5 * s, 20 * s), Offset(5 * s, 11 * s), paint)
      ..drawLine(Offset(12 * s, 20 * s), Offset(12 * s, 4 * s), paint)
      ..drawLine(Offset(19 * s, 20 * s), Offset(19 * s, 13 * s), paint);
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color;
}

class _TargetPainter extends CustomPainter {
  _TargetPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = _stroke(color, s);
    final center = Offset(12 * s, 12 * s);
    canvas
      ..drawCircle(center, 8 * s, paint)
      ..drawCircle(center, 3.5 * s, paint);
  }

  @override
  bool shouldRepaint(_TargetPainter old) => old.color != color;
}
