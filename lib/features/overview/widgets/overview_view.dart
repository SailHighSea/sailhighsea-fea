import 'package:flutter/material.dart';

import '../../../core/widgets/async_placeholder.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/adaptive_grid.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/time.dart';
import '../../../core/widgets/hero_panel.dart';
import '../../../core/widgets/month_navigator.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../core/widgets/surface_card.dart';
import '../../budgets/budget_providers.dart';
import '../../family/member_providers.dart';
import '../../insights/domain/insights_calculations.dart';
import '../../insights/widgets/insight_cards.dart';
import '../domain/overview_calculations.dart';
import '../overview_providers.dart';
import 'allowance_sheet.dart';

/// "Everyone": the family's month at a glance and one row per person. Tap a person to see
/// Home for just them.
class OverviewView extends ConsumerWidget {
  const OverviewView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(overviewProvider);
    final data = async.value;
    final t = context.tokens;
    if (data == null) {
      return AsyncPlaceholder(
        what: 'the overview',
        error: async.hasError ? async.error : null,
        onRetry: () => ref.invalidate(overviewProvider),
      );
    }
    final money = ref.watch(moneyFormatterProvider);
    final permissions = ref.watch(permissionsProvider);
    final months = ref.read(selectedMonthProvider.notifier);
    final palette = [t.primary, t.amber, t.purple, t.blue, t.rose, t.grey];

    Future<void> editAllowance(PersonSpend person) async {
      final cents = await showAllowanceSheet(
        context,
        money: money,
        name: person.isYou ? 'you' : person.name,
        current: person.allowanceCents,
      );
      if (cents == null) return;
      await ref
          .read(budgetRepositoryProvider)
          .setAllowance(data.month, person.userId, cents);
    }

    void openPerson(PersonSpend person) {
      if (person.hasLeft) return;
      ref.read(memberFilterProvider.notifier).select(person.userId);
      context.go('/home');
    }

    final rows = <Widget>[
      for (var i = 0; i < data.people.length; i++)
        PersonRow(
          person: data.people[i],
          color: palette[i % palette.length],
          money: money,
          canSetAllowance:
              permissions.canSetAllowances && !data.people[i].hasLeft,
          onTap: data.people[i].hasLeft
              ? null
              : () => openPerson(data.people[i]),
          onAllowance: () => editAllowance(data.people[i]),
        ),
    ];

    final over = data.isOver;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonthNavigator(
          month: data.month,
          onPrevious: months.previous,
          onNext: months.next,
          titleSize: 18,
        ),
        const SizedBox(height: 12),
        HeroPanel(
          label: 'Everyone spent',
          value: money.formatWhole(data.totalCents),
          caption: over
              ? 'Over the ${money.formatWhole(data.budgetCents)} budget by ${money.formatWhole(-data.leftCents)}'
              : 'of ${money.formatWhole(data.budgetCents)} · ${money.formatWhole(data.leftCents)} left',
        ),
        const SizedBox(height: 14),
        if (data.totalCents > 0)
          InsightCard(
            title: 'Who spent what',
            child: MemberShares(
              members: [
                for (final p in data.people)
                  if (p.spentCents > 0)
                    MemberShare(name: p.name, cents: p.spentCents),
              ],
              money: money,
            ),
          ),
        if (data.totalCents > 0) const SizedBox(height: 14),
        AdaptiveGrid(compact: 1, medium: 2, wide: 2, children: rows),
        if (data.people.length == 1) ...[
          const SizedBox(height: 14),
          SurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Only you so far. Invite family from the Family page and their spending shows up here.',
              key: const ValueKey('overview-alone'),
              style: TextStyle(fontSize: 15, height: 1.35, color: t.muted),
            ),
          ),
        ],
      ],
    );
  }
}

/// One person: name, spent, their share of the family total, top category and allowance.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.person,
    required this.color,
    required this.money,
    required this.canSetAllowance,
    required this.onAllowance,
    this.onTap,
  });

  final PersonSpend person;
  final Color color;
  final MoneyFormatter money;
  final bool canSetAllowance;
  final VoidCallback onAllowance;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final initial = person.name.trim().isEmpty
        ? '?'
        : String.fromCharCode(person.name.trim().runes.first).toUpperCase();
    final top = person.topCategoryName == null
        ? 'No spending yet'
        : 'Most on ${person.topCategoryName}';
    final allowance = person.allowanceCents;
    return SurfaceCard(
      key: ValueKey('person-${person.userId}'),
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      semanticLabel:
          '${person.name}: ${money.formatWhole(person.spentCents)}, ${person.sharePercent}% of the family. $top',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      Text(top, style: TextStyle(fontSize: 13, color: t.muted)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money.formatWhole(person.spentCents),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      '${person.sharePercent}%',
                      style: TextStyle(fontSize: 13, color: t.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ProgressBar(
            fraction: person.sharePercent / 100,
            height: 8,
            color: color,
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Text(
              'Today ${money.formatWhole(person.todayCents)} · This week ${money.formatWhole(person.weekCents)}',
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ),
          if (allowance != null) ...[
            const SizedBox(height: 10),
            ProgressBar(
              fraction: person.allowanceFraction,
              height: 6,
              color: person.overAllowance ? t.rose : t.primary,
            ),
            const SizedBox(height: 4),
            Text(
              person.overAllowance
                  ? 'Over the ${money.formatWhole(allowance)} allowance by ${money.formatWhole(-person.allowanceLeftCents!)}'
                  : '${money.formatWhole(person.spentCents)} of ${money.formatWhole(allowance)} allowance · ${money.formatWhole(person.allowanceLeftCents!)} left',
              key: ValueKey('allowance-text-${person.userId}'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: person.overAllowance
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: person.overAllowance ? t.rose : t.muted,
              ),
            ),
          ],
          if (canSetAllowance)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('allowance-button-${person.userId}'),
                onPressed: onAllowance,
                style: TextButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                  padding: EdgeInsets.zero,
                  foregroundColor: t.primary,
                ),
                child: Text(
                  allowance == null ? 'Set allowance' : 'Change allowance',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
