import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/db/app_database.dart';
import '../../core/layout/adaptive_grid.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time.dart';
import '../../core/widgets/hero_panel.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';
import '../auth/auth_providers.dart';
import '../family/member_providers.dart';
import 'domain/goal_calculations.dart';
import 'goal_providers.dart';
import 'widgets/goal_card.dart';
import 'widgets/goal_sheets.dart';

/// Savings goals (Goals, TabGoals, DeskGoals mockups). Owner and admin create goals and add
/// money; everyone sees them.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goalViewsProvider);
    final goals = async.value;
    final t = context.tokens;
    if (goals == null) {
      return Center(
        child: async.hasError
            ? Text('Could not load goals: ${async.error}')
            : const CircularProgressIndicator(),
      );
    }
    final money = ref.watch(moneyFormatterProvider);
    final permissions = ref.watch(permissionsProvider);
    final members = ref.watch(membersProvider).value ?? const <MemberRow>[];
    final now = ref.watch(clockProvider)();
    final recent = ref.watch(recentContributionsProvider);
    final label = ref.watch(addedByLabelProvider);
    final repo = ref.read(goalRepositoryProvider);
    final me = ref.watch(currentUserIdProvider);

    Future<void> newGoal() async {
      final r = await showGoalSheet(context, money: money, now: now);
      if (r == null || r.delete) return;
      await repo.add(
        name: r.name,
        targetCents: r.targetCents,
        savedCents: r.savedCents,
        monthlyCents: r.monthlyCents,
        dueOn: r.dueOn,
      );
    }

    Future<void> editGoal(GoalRow goal) async {
      final r = await showGoalSheet(
        context,
        money: money,
        now: now,
        existing: goal,
      );
      if (r == null) return;
      if (r.delete) {
        await repo.softDelete(goal.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text('Deleted ${goal.name}'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => repo.restore(goal.id),
                ),
              ),
            );
        }
        return;
      }
      await repo.update(
        goal.id,
        name: r.name,
        targetCents: r.targetCents,
        savedCents: r.savedCents,
        monthlyCents: r.monthlyCents,
        dueOn: r.dueOn,
      );
    }

    Future<void> addMoney() async {
      final r = await showAddMoneySheet(
        context,
        money: money,
        goals: [for (final g in goals) g.goal],
      );
      if (r == null) return;
      await repo.addMoney(r.goalId, cents: r.cents, addedBy: me);
    }

    final memberCount = members.isEmpty ? 1 : members.length;
    return AdaptivePage(
      header: PageHeader(
        title: 'Savings goals',
        onBackWhenCompact: () => context.go('/home'),
        trailing: permissions.canManageGoals
            ? PillButton(
                key: const ValueKey('new-goal-button'),
                label: '+ New goal',
                height: 44,
                onTap: newGoal,
              )
            : null,
      ),
      children: [
        HeroPanel(
          label:
              'Saved across ${goals.length} ${goals.length == 1 ? 'goal' : 'goals'}',
          value: money.formatWhole(totalSaved(goals)),
          caption:
              'Shared with ${memberCount == 1 ? 'you' : 'all $memberCount household members'}',
          action: permissions.canManageGoals && goals.isNotEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: PillButton(
                    key: const ValueKey('add-money-button'),
                    label: 'Add money',
                    height: 44,
                    onTap: addMoney,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        if (goals.isEmpty)
          _EmptyGoals(canAdd: permissions.canManageGoals)
        else
          AdaptiveGrid(
            compact: 1,
            medium: 2,
            wide: 3,
            children: [
              for (final g in goals)
                GoalCard(
                  goal: g,
                  money: money,
                  onTap: permissions.canManageGoals
                      ? () => editGoal(g.goal)
                      : null,
                ),
            ],
          ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 14),
          SurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Recent contributions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final c in recent) ...[
                  Divider(color: t.border, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.goalName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: t.text,
                                ),
                              ),
                              Text(
                                '${label(c.addedByUserId)} · ${DateFormat('MMM d', 'en_US').format(c.day)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: t.muted),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '+${money.formatWhole(c.cents)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals({required this.canAdd});

  final bool canAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Text(
        canAdd
            ? 'No goals yet. Tap New goal to start saving for something together.'
            : 'No goals yet. The owner or an admin can add one.',
        key: const ValueKey('goals-empty'),
        style: TextStyle(fontSize: 15, height: 1.35, color: t.muted),
      ),
    );
  }
}
