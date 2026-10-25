import 'package:flutter/material.dart';

import '../../core/widgets/async_placeholder.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/app_database.dart';
import '../../core/layout/adaptive_grid.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time.dart';
import '../../core/widgets/dashed_box.dart';
import '../../core/widgets/pill_button.dart';
import '../expenses/expense_providers.dart';
import '../family/member_providers.dart';
import 'budget_providers.dart';
import 'domain/budget_calculations.dart';
import 'widgets/budget_card.dart';
import 'widgets/budget_hero.dart';
import 'widgets/edit_budgets_sheet.dart';
import 'widgets/new_category_dialog.dart';

/// Budgets (Budgets, TabBudgets, DeskBudgets mockups): the month's overall budget with a
/// progress card per category. Owner and admin edit; everyone else reads.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(budgetsSummaryProvider);
    final summary = async.value;
    final t = context.tokens;
    if (summary == null) {
      return AsyncPlaceholder(
        what: 'budgets',
        error: async.hasError ? async.error : null,
        onRetry: () => ref.invalidate(budgetsSummaryProvider),
      );
    }
    final money = ref.watch(moneyFormatterProvider);
    final permissions = ref.watch(permissionsProvider);
    final months = ref.read(selectedMonthProvider.notifier);
    final month = summary.month;
    final monthLabel = DateFormat('MMMM yyyy', 'en_US').format(month);

    Future<void> edit() async {
      final rows = ref.read(budgetRowsProvider).value ?? const <BudgetRow>[];
      final effective = effectiveBudgets(rows, month);
      final categories =
          ref.read(categoriesProvider).value ?? const <CategoryRow>[];
      final result = await showEditBudgetsSheet(
        context,
        money: money,
        monthLabel: monthLabel,
        overallCents: effective[null],
        categories: categories,
        categoryBudgets: {
          for (final e in effective.entries)
            if (e.key != null) e.key!: e.value,
        },
      );
      if (result == null) return;
      final repo = ref.read(budgetRepositoryProvider);
      if (result.overall != effective[null]) {
        await repo.setBudget(month, null, result.overall ?? 0);
      }
      for (final e in result.byCategory.entries) {
        if (e.value != effective[e.key]) {
          await repo.setBudget(month, e.key, e.value ?? 0);
        }
      }
    }

    Future<void> addCategory() async {
      final result = await showNewCategorySheet(context, money: money);
      if (result == null) return;
      final category = await ref
          .read(categoryRepositoryProvider)
          .add(result.name);
      if (result.budgetCents != null) {
        await ref
            .read(budgetRepositoryProvider)
            .setBudget(month, category.id, result.budgetCents!);
      }
    }

    final cards = <Widget>[
      if (summary.lines.isEmpty)
        _EmptyBudgets(canEdit: permissions.canManageBudgets),
      for (final line in summary.lines)
        BudgetCard(
          line: line,
          money: money,
          onTap: permissions.canManageBudgets ? edit : null,
        ),
      if (permissions.canManageCategories) _NewCategoryTile(onTap: addCategory),
    ];

    return AdaptivePage(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Budgets',
            trailing: permissions.canManageBudgets
                ? PillButton(
                    key: const ValueKey('edit-budgets-button'),
                    label: 'Edit budgets',
                    style: PillStyle.outlined,
                    height: 44,
                    onTap: edit,
                  )
                : null,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _MonthButton(
                icon: Icons.chevron_left_rounded,
                label: 'Previous month',
                onTap: months.previous,
              ),
              Flexible(
                child: Text(
                  '$monthLabel · ${money.formatWhole(summary.spentCents)} of ${money.formatWhole(summary.overallCents)}',
                  key: const ValueKey('budgets-subtitle'),
                  style: TextStyle(fontSize: 15, color: t.muted),
                ),
              ),
              _MonthButton(
                icon: Icons.chevron_right_rounded,
                label: 'Next month',
                onTap: months.next,
              ),
            ],
          ),
        ],
      ),
      children: [
        HeroGridLayout(
          hero: BudgetHero(summary: summary, money: money),
          grid: AdaptiveGrid(compact: 1, medium: 2, wide: 3, children: cards),
        ),
      ],
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: kMinTapTarget,
        height: kMinTapTarget,
        child: Icon(icon, color: context.tokens.muted),
      ),
    ),
  );
}

class _NewCategoryTile extends StatelessWidget {
  const _NewCategoryTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'New category',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('new-category-tile'),
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: DashedBox(
          color: t.grey,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: Center(
            child: Text(
              '+ New category',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBudgets extends StatelessWidget {
  const _EmptyBudgets({required this.canEdit});

  final bool canEdit;

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
        canEdit
            ? 'No category budgets yet. Tap Edit budgets to set one.'
            : 'No category budgets yet. The owner or an admin can set them.',
        key: const ValueKey('budgets-empty'),
        style: TextStyle(fontSize: 15, height: 1.35, color: t.muted),
      ),
    );
  }
}
