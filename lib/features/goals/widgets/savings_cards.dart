import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/adaptive_grid.dart';
import '../../../core/money/money_format.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/hero_panel.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/savings_plan.dart';

/// The savings part of the Goals page: what is left this month, where the income goes, the total
/// held in savings and the savings rate. [onEdit] opens the income sheet (null for people who
/// cannot change it).
class SavingsSection extends StatelessWidget {
  const SavingsSection({
    super.key,
    required this.plan,
    required this.money,
    required this.onEdit,
  });

  final SavingsPlan plan;
  final MoneyFormatter money;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!plan.hasIncome) {
      return SurfaceCard(
        key: const ValueKey('income-empty'),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'How much can you save?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add your monthly income and what you hold in savings. The app then shows what is left to save each month and whether your goals fit.',
              style: TextStyle(fontSize: 14, height: 1.35, color: t.muted),
            ),
            if (onEdit != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: PillButton(
                  key: const ValueKey('income-set'),
                  label: 'Set income',
                  height: 44,
                  onTap: onEdit,
                ),
              ),
            ],
          ],
        ),
      );
    }
    final over = plan.leftCents < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroPanel(
          label: over ? 'Over by, this month' : 'Left to save this month',
          value: money.formatWhole(over ? -plan.leftCents : plan.leftCents),
          caption:
              'Income ${money.formatWhole(plan.incomeCents!)} · spent ${money.formatWhole(plan.spentCents)} · ${plan.ratePercent}% kept so far',
          action: onEdit == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: PillButton(
                    key: const ValueKey('income-edit'),
                    label: 'Income and savings',
                    height: 44,
                    onTap: onEdit,
                  ),
                ),
        ),
        const SizedBox(height: 14),
        AdaptiveGrid(
          compact: 1,
          medium: 2,
          wide: 3,
          children: [
            _FlowCard(plan: plan, money: money),
            _TotalCard(plan: plan, money: money),
            _RateCard(plan: plan),
          ],
        ),
        if (plan.status == PlanStatus.short) ...[
          const SizedBox(height: 14),
          _ShortCard(plan: plan, money: money),
        ],
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
        ),
        if (trailing != null)
          Text(trailing!, style: TextStyle(fontSize: 12, color: t.muted)),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.label, this.value);
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: t.text)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bar split into coloured parts that add up to [total] (parts of 0 are left out).
class _SplitBar extends StatelessWidget {
  const _SplitBar(this.parts);
  final List<(int, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final p in parts)
        if (p.$1 > 0) p,
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 16,
        child: Row(
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: shown[i].$1,
                child: ColoredBox(color: shown[i].$2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.plan, required this.money});
  final SavingsPlan plan;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final free = plan.leftCents > 0 ? plan.leftCents : 0;
    return SurfaceCard(
      key: const ValueKey('savings-flow'),
      padding: const EdgeInsets.all(16),
      semanticLabel:
          'Where your income goes: spent ${money.formatWhole(plan.spentCents)}, bills still due ${money.formatWhole(plan.billsDueCents)}, goals ${money.formatWhole(plan.goalsMonthlyCents)}, free ${money.formatWhole(free)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Title(
            'Where your income goes',
            trailing: money.formatWhole(plan.incomeCents!),
          ),
          const SizedBox(height: 12),
          _SplitBar([
            (plan.spentCents, t.primary),
            (plan.billsDueCents, t.blue),
            (plan.goalsMonthlyCents, t.amber),
            (free, t.border),
          ]),
          const SizedBox(height: 10),
          _Legend(
            t.primary,
            'Spent so far',
            money.formatWhole(plan.spentCents),
          ),
          _Legend(
            t.blue,
            'Bills still due',
            money.formatWhole(plan.billsDueCents),
          ),
          _Legend(
            t.amber,
            'Set aside for goals',
            money.formatWhole(plan.goalsMonthlyCents),
          ),
          _Legend(t.border, 'Free to spend or save', money.formatWhole(free)),
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.plan, required this.money});
  final SavingsPlan plan;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = plan.totalSavingsCents;
    return SurfaceCard(
      key: const ValueKey('savings-total'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Title(
            'Total savings',
            trailing: plan.totalAsOn == null
                ? null
                : 'as of ${DateFormat('MMM d', 'en_US').format(plan.totalAsOn!)}',
          ),
          const SizedBox(height: 8),
          if (total == null)
            Text(
              'Not set yet. Use Income and savings to add what you hold.',
              style: TextStyle(fontSize: 13, color: t.muted),
            )
          else ...[
            Text(
              money.formatWhole(total),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 10),
            _SplitBar([
              (plan.inGoalsCents, t.primary),
              (plan.notInGoalsCents, t.border),
            ]),
            const SizedBox(height: 10),
            _Legend(
              t.primary,
              'In goals',
              money.formatWhole(plan.inGoalsCents),
            ),
            _Legend(
              t.border,
              'Not in a goal',
              money.formatWhole(plan.notInGoalsCents),
            ),
          ],
        ],
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.plan});
  final SavingsPlan plan;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final month = DateFormat('MMM', 'en_US');
    final shown = plan.history;
    final top = shown.fold<int>(
      1,
      (m, r) => r.percent != null && r.percent! > m ? r.percent! : m,
    );
    return SurfaceCard(
      key: const ValueKey('savings-rate'),
      padding: const EdgeInsets.all(16),
      semanticLabel:
          'Savings rate, last 6 months: ${shown.map((r) => '${month.format(r.month)} ${r.percent ?? 'no income'}${r.percent == null ? '' : ' percent'}').join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Title('Savings rate', trailing: 'Last 6 months'),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < shown.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          shown[i].percent == null
                              ? '–'
                              : '${shown[i].percent}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == shown.length - 1
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: i == shown.length - 1 ? t.text : t.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        FractionallySizedBox(
                          widthFactor: 0.7,
                          child: Container(
                            height:
                                ((shown[i].percent ?? 0).clamp(0, 100) / top) *
                                    56 +
                                2,
                            decoration: BoxDecoration(
                              color: i == shown.length - 1
                                  ? t.primary
                                  : t.border,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < shown.length; i++)
                Expanded(
                  child: Text(
                    month.format(shown[i].month),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: t.muted),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShortCard extends StatelessWidget {
  const _ShortCard({required this.plan, required this.money});
  final SavingsPlan plan;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final missing = plan.goalsMonthlyCents - plan.availableForGoalsCents;
    final possible = plan.availableForGoalsCents > 0
        ? plan.availableForGoalsCents
        : 0;
    return SurfaceCard(
      key: const ValueKey('savings-short'),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: t.amber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your goals ask for ${money.formatWhole(plan.goalsMonthlyCents)} a month, '
              '${money.formatWhole(missing)} more than is left after spending and bills. '
              'This month you can set aside about ${money.formatWhole(possible)}.',
              style: TextStyle(fontSize: 14, height: 1.35, color: t.text),
            ),
          ),
        ],
      ),
    );
  }
}
