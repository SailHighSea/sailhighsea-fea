import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A ring on a light card with a percentage in the middle (the goal cards).
class PercentRing extends StatelessWidget {
  const PercentRing({
    super.key,
    required this.fraction,
    required this.percent,
    this.size = 76,
  });

  final double fraction;
  final int percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _Painter(
              track: t.border,
              arc: t.primary,
              fraction: fraction,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter({required this.track, required this.arc, required this.fraction});

  final Color track;
  final Color arc;
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.115;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = arc,
    );
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.track != track || old.arc != arc || old.fraction != fraction;
}
