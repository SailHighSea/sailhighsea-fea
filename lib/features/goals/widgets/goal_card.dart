import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/percent_ring.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/goal_calculations.dart';

/// A savings goal: progress ring, saved of target, monthly amount and projected finish.
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.goal,
    required this.money,
    this.onTap,
  });

  final GoalView goal;
  final MoneyFormatter money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final monthly = goal.goal.monthlyCents > 0
        ? '${money.formatWhole(goal.goal.monthlyCents)} a month · ${doneByLabel(goal)}'
        : doneByLabel(goal);
    final progress =
        '${money.formatWhole(goal.savedCents)} of ${money.formatWhole(goal.targetCents)}';
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      semanticLabel: '${goal.goal.name}: $progress, ${goal.percent}%. $monthly',
      child: ExcludeSemantics(
        child: Row(
          children: [
            PercentRing(fraction: goal.fraction, percent: goal.percent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    goal.goal.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    progress,
                    style: TextStyle(fontSize: 14, color: t.muted),
                  ),
                  Text(monthly, style: TextStyle(fontSize: 14, color: t.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
