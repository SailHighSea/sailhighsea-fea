import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../home/widgets/hero_card.dart';
import '../domain/budget_calculations.dart';

/// The ring card beside the category budgets: percent used, what is left, days to go.
class BudgetHero extends StatelessWidget {
  const BudgetHero({super.key, required this.summary, required this.money});

  final BudgetsSummary summary;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final over = summary.isOver;
    final headline = over
        ? 'Over by ${money.formatWhole(-summary.leftCents)}'
        : '${money.formatWhole(summary.leftCents)} left';
    final detail = summary.daysLeft == 0
        ? 'Month is over'
        : '${summary.daysLeft} ${summary.daysLeft == 1 ? 'day' : 'days'} to go'
              '${over ? '' : ' · ${money.formatWhole(summary.perDayCents)} a day'}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: t.hero,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Semantics(
        container: true,
        label: '${summary.percent}% of the budget used. $headline. $detail.',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UsedRing(
              fraction: summary.fraction,
              percent: summary.percent,
              size: 132,
            ),
            const SizedBox(height: 18),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                headline,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: t.heroText,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: t.heroMuted),
            ),
          ],
        ),
      ),
    );
  }
}
