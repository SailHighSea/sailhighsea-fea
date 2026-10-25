import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/surface_card.dart';
import '../home_data.dart';

/// Next bill. [wide] is the roomier desktop card with an extra summary line.
class NextBillCard extends StatelessWidget {
  const NextBillCard({
    super.key,
    required this.bill,
    required this.money,
    required this.wide,
    required this.onTap,
  });

  final UpcomingBill? bill;
  final MoneyFormatter money;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final b = bill;
    final days = b == null
        ? ''
        : (b.daysUntil == 0
              ? 'due today'
              : (b.daysUntil == 1 ? 'in 1 day' : 'in ${b.daysUntil} days'));
    final dueWord = wide && b != null && b.daysUntil > 0 ? 'due $days' : days;
    return SurfaceCard(
      radius: wide ? AppRadii.card : AppRadii.smallCard,
      padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 14, vertical: 14),
      onTap: onTap,
      semanticLabel: b == null
          ? 'Next bill: none due'
          : 'Next bill: ${b.name}, ${money.format(b.amountCents)} $days',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: wide
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Next bill',
              style: TextStyle(fontSize: wide ? 13 : 12, color: t.muted),
            ),
            SizedBox(height: wide ? 6 : 4),
            if (b == null)
              Text(
                'Nothing due',
                style: TextStyle(
                  fontSize: wide ? 20 : 15,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              )
            else ...[
              Text(
                b.name,
                style: TextStyle(
                  fontSize: wide ? 20 : 15,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
              SizedBox(height: wide ? 6 : 4),
              Text(
                '${money.format(b.amountCents)} · $dueWord',
                style: TextStyle(
                  fontSize: wide ? 14 : 13,
                  fontWeight: FontWeight.w700,
                  color: t.amberText,
                ),
              ),
              if (wide) ...[
                const SizedBox(height: 6),
                Text(
                  '${b.billCount} bills, ${money.format(b.totalDueCents)} due by ${b.dueByLabel}',
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Savings goal with a progress bar.
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    required this.money,
    required this.wide,
    required this.onTap,
  });

  final GoalProgress? goal;
  final MoneyFormatter money;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final g = goal;
    final progress =
        '${g == null ? '' : money.formatWhole(g.savedCents)} of ${g == null ? '' : money.formatWhole(g.targetCents)}';
    final barHeight = wide ? 10.0 : 8.0;
    return SurfaceCard(
      radius: wide ? AppRadii.card : AppRadii.smallCard,
      padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 14, vertical: 14),
      onTap: onTap,
      semanticLabel: g == null ? 'Goal: none yet' : '${g.name} goal: $progress',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: wide
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              g == null ? 'Savings goal' : '${g.name} goal',
              style: TextStyle(fontSize: wide ? 13 : 12, color: t.muted),
            ),
            if (g == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No goal yet',
                  style: TextStyle(
                    fontSize: wide ? 20 : 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              )
            else ...[
              if (wide) ...[
                const SizedBox(height: 6),
                Text(
                  progress,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 6),
                _ProgressBar(fraction: g.fraction, height: barHeight),
                const SizedBox(height: 6),
                Text(
                  '${money.formatWhole(g.monthlyCents)} a month · done by ${g.doneByLabel}',
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: _ProgressBar(fraction: g.fraction, height: barHeight),
                ),
                const SizedBox(height: 4),
                Text(
                  progress,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fraction, required this.height});

  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: t.border)),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.primary,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
