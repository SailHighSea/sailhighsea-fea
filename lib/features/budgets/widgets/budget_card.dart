import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/budget_calculations.dart';

/// One category's budget: name, spent of budget, a bar, and how much is left. Turns amber at
/// 90% ("Almost at limit") and rose when over budget.
class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.line,
    required this.money,
    this.onTap,
  });

  final BudgetLine line;
  final MoneyFormatter money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (
      Color bar,
      Color textColor,
      FontWeight weight,
      String status,
    ) = switch (line.state) {
      BudgetState.ok => (
        t.primary,
        t.muted,
        FontWeight.w400,
        '${money.formatWhole(line.leftCents)} left',
      ),
      BudgetState.nearLimit => (
        t.amberBar,
        t.amberText,
        FontWeight.w700,
        'Almost at limit · ${money.formatWhole(line.leftCents)} left',
      ),
      BudgetState.over => (
        t.rose,
        t.rose,
        FontWeight.w700,
        'Over by ${money.formatWhole(line.overCents)}',
      ),
    };
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: onTap,
      semanticLabel:
          '${line.name}: ${money.formatWhole(line.spentCents)} of ${money.formatWhole(line.budgetCents)}, $status',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(
                    line.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  Text(
                    '${money.formatWhole(line.spentCents)} / ${money.formatWhole(line.budgetCents)}',
                    style: TextStyle(fontSize: 14, color: t.muted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ProgressBar(
                fraction: line.state == BudgetState.over ? 1 : line.fraction,
                color: bar,
              ),
              const SizedBox(height: 8),
              Text(
                status,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: weight,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
