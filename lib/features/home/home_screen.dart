import 'package:flutter/material.dart';

import '../../core/widgets/async_placeholder.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/dashboard_layout.dart';
import '../../core/layout/destinations.dart';
import '../../core/money/money_provider.dart';
import '../family/member_providers.dart';
import '../../core/time.dart';
import '../overview/overview_providers.dart';
import '../overview/widgets/category_by_person_card.dart';
import '../overview/widgets/everyone_card.dart';
import '../overview/widgets/member_filter_chips.dart';
import 'home_providers.dart';
import 'widgets/bill_goal_cards.dart';
import 'widgets/categories_card.dart';
import 'widgets/category_cards.dart';
import 'widgets/hero_card.dart';
import 'widgets/home_header.dart';
import 'widgets/recent_card.dart';
import 'widgets/trend_cards.dart';

/// Home dashboard (docs/SPEC.md section 3). The same sections on every size; how they
/// are arranged is decided by [DashboardLayout] in core/layout.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(homeSummaryProvider);
    final summary = summaryAsync.value;
    if (summary == null) {
      return AsyncPlaceholder(
        what: 'expenses',
        error: summaryAsync.hasError ? summaryAsync.error : null,
        onRetry: () => ref.invalidate(homeSummaryProvider),
      );
    }
    final money = ref.watch(moneyFormatterProvider);
    final permissions = ref.watch(permissionsProvider);
    final now = ref.watch(clockProvider)();
    final month = ref.watch(selectedMonthProvider);
    final months = ref.read(selectedMonthProvider.notifier);

    void goTo(AppDestination d) => context.go(d.path);

    final lastDay = now.month == month.month && now.year == month.year
        ? now.day
        : daysInMonth(month);
    final monthShort = DateFormat('MMM', 'en_US').format(month);

    return DashboardLayout(
      header: (context, mode) => HomeHeader(
        month: month,
        onPrevious: months.previous,
        onNext: months.next,
        onAdd: permissions.canWriteExpenses ? () => context.push('/add') : null,
        onSelectDestination: goTo,
        mode: mode,
      ),
      hero: (context, mode) => HeroCard(summary: summary, money: money),
      trend: (context, mode) => switch (mode) {
        DashboardMode.wide => MonthBarsCard(
          summary: summary,
          money: money,
          rangeTitle: 'Daily spending, 1 to $lastDay $monthShort',
          startLabel: '$monthShort 1',
          endLabel: '$monthShort $lastDay',
          onFullDashboard: () => goTo(AppDestination.insights),
        ),
        DashboardMode.split => WeekBarsCard(
          summary: summary,
          money: money,
          size: WeekChartSize.roomy,
          onFullDashboard: () => goTo(AppDestination.insights),
        ),
        DashboardMode.stacked => WeekBarsCard(
          summary: summary,
          money: money,
          size: WeekChartSize.compact,
          onFullDashboard: () => goTo(AppDestination.insights),
        ),
      },
      categories: (context, mode) => TopCategoriesCard(
        categories: summary.categories,
        money: money,
        horizontalPadding: mode == DashboardMode.wide ? 20 : 16,
      ),
      compare: (context, mode) => CategoryCompareCard(
        items: summary.comparison,
        money: money,
        horizontalPadding: mode == DashboardMode.wide ? 20 : 16,
      ),
      tiles: (context, mode) => CategoryTilesCard(
        items: summary.comparison,
        money: money,
        horizontalPadding: mode == DashboardMode.wide ? 20 : 16,
      ),
      nextBill: (context, mode) => NextBillCard(
        bill: summary.nextBill,
        money: money,
        wide: mode == DashboardMode.wide,
        onTap: () => goTo(AppDestination.bills),
      ),
      goal: (context, mode) => GoalCard(
        goal: summary.goal,
        money: money,
        wide: mode == DashboardMode.wide,
        onTap: () => goTo(AppDestination.goals),
      ),
      filters: ref.watch(canSeeEveryoneProvider)
          ? (context, mode) => const MemberFilterChips()
          : null,
      everyone: ref.watch(canSeeEveryoneProvider)
          ? (context, mode) => EveryoneCard(
              onTap: () {
                ref
                    .read(insightsTabProvider.notifier)
                    .select(InsightsTab.everyone);
                ref.read(memberFilterProvider.notifier).select(null);
                goTo(AppDestination.insights);
              },
            )
          : null,
      byPerson: ref.watch(canSeeEveryoneProvider)
          ? (context, mode) => CategoryByPersonCard(
              horizontalPadding: mode == DashboardMode.wide ? 20 : 16,
            )
          : null,
      recent: (context, mode) => RecentCard(
        items: summary.recent,
        money: money,
        now: now,
        table: mode == DashboardMode.wide,
        onSeeAll: () => context.go('/expenses'),
        onOpen: permissions.canWriteExpenses
            ? (expense) => context.push('/expenses/${expense.id}/edit')
            : null,
        canOpen: (e) => ref.read(canEditExpenseProvider)(e.createdBy),
      ),
    );
  }
}
