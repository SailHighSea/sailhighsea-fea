import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../home_data.dart';

/// The green summary card: spent, budget, ring, and today / week / safe per day.
/// Identical in every theme and size; only token colours change.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.summary,
    required this.money,
    this.top,
    this.title = 'Spent this month',
  });

  final HomeSummary summary;
  final MoneyFormatter money;

  /// Placed above the numbers (the month switch and title in the gradient look).
  final Widget? top;

  /// "Spent this month", or "Spent in August" when another month is on show.
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final remaining = summary.remainingCents;
    final remainingText = remaining >= 0
        ? '${money.formatWhole(remaining)} left'
        : '${money.formatWhole(-remaining)} over';
    final spent = money.formatWhole(summary.spentCents);
    final budget = money.formatWhole(summary.budgetCents);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: t.hero,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: t.heroBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Outside the summary below, so its buttons stay reachable by a screen reader.
          if (top != null) ...[top!, const SizedBox(height: 6)],
          Semantics(
            container: true,
            label:
                '$title $spent of $budget, ${summary.usedPercent} percent used, $remainingText. '
                'Today ${money.formatWhole(summary.todayCents)}, this week ${money.formatWhole(summary.weekCents)}, '
                'safe per day ${money.formatWhole(summary.safePerDayCents)}.',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 14,
                                color: t.heroMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                spent,
                                style: TextStyle(
                                  fontSize: 38,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1,
                                  color: t.heroText,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'of $budget · $remainingText',
                              style: TextStyle(
                                fontSize: 14,
                                color: t.heroMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      UsedRing(
                        fraction: summary.usedFraction,
                        percent: summary.usedPercent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: t.heroTrack),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          label: 'Today',
                          value: money.formatWhole(summary.todayCents),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Stat(
                          label: 'This week',
                          value: money.formatWhole(summary.weekCents),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Stat(
                          label: 'Safe per day',
                          value: money.formatWhole(summary.safePerDayCents),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: t.heroMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: t.heroText,
          ),
        ),
      ],
    );
  }
}

/// 96px ring with the used percentage in the middle.
class UsedRing extends StatelessWidget {
  const UsedRing({
    super.key,
    required this.fraction,
    required this.percent,
    this.size = 96,
    this.showLabel = true,
  });

  final double fraction;
  final int percent;
  final double size;
  final bool showLabel;

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
            painter: _RingPainter(
              track: t.heroTrack,
              arc: t.ringAccent,
              fraction: fraction,
              stroke: size * 10 / 96,
            ),
          ),
          // The label shrinks instead of overflowing the ring at large text sizes.
          Padding(
            padding: EdgeInsets.all(size * 0.16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$percent%',
                    style: TextStyle(
                      fontSize: 22 * size / 96,
                      fontWeight: FontWeight.w700,
                      color: t.heroText,
                    ),
                  ),
                  if (showLabel)
                    Text(
                      'used',
                      style: TextStyle(fontSize: 12, color: t.heroMuted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.track,
    required this.arc,
    required this.fraction,
    required this.stroke,
  });

  final Color track;
  final Color arc;
  final double fraction;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (fraction <= 0) return;
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = arc;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction, false, progress);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.track != track ||
      old.arc != arc ||
      old.fraction != fraction ||
      old.stroke != stroke;
}
