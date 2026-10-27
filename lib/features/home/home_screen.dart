import 'package:flutter/material.dart';

import '../../core/widgets/async_placeholder.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/layout/dashboard_layout.dart';
import '../../core/layout/destinations.dart';
import '../../core/layout/window_class.dart';
import '../../core/money/money_provider.dart';
import '../family/member_providers.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/theme/appearance_settings.dart';
import '../../core/theme/personal_look.dart';
import '../../core/time.dart';
import '../overview/overview_providers.dart';
import '../overview/widgets/category_by_person_card.dart';
import '../overview/widgets/everyone_card.dart';
import '../overview/widgets/member_filter_chips.dart';
import 'home_providers.dart';
import 'widgets/bill_goal_cards.dart';
import 'widgets/categories_card.dart';
import 'widgets/category_cards.dart';
import 'widgets/gradient_home_header.dart';
import 'widgets/hero_card.dart';
import 'widgets/personal_hero.dart';
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
    // The card says which month it shows once it is not the current one.
    final heroTitle = now.month == month.month && now.year == month.year
        ? 'Spent this month'
        : 'Spent in ${DateFormat('MMMM', 'en_US').format(month)}';

    final gradientHeader =
        ref.watch(appearanceProvider).homeHeader == HomeHeaderStyle.gradient;
    final cardStyle = ref.watch(personalLookProvider).card;

    final add = permissions.canWriteExpenses
        ? () => context.push('/add')
        : null;

    final layout = DashboardLayout(
      header: (context, mode) => HomeHeader(
        month: month,
        onPrevious: months.previous,
        onNext: months.next,
        onAdd: add,
        onSelectDestination: goTo,
        mode: mode,
      ),
      // The gradient look: a full-width band, with the overview card reaching up into it and the
      // month switch inside that card. The Add button floats at the bottom right.
      band: gradientHeader ? (context, mode) => GradientBand(mode: mode) : null,
      bandOverlap: kHeaderOverlap,
      bottomSpace: gradientHeader && add != null ? 84 : 0,
      // Swipe the card sideways to change month: left for the next, right for the previous.
      hero: (context, mode) => GestureDetector(
        key: const ValueKey('hero-swipe'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          final months = ref.read(selectedMonthProvider.notifier);
          if (v < -300) months.next();
          if (v > 300) months.previous();
        },
        child: PersonalHero(
          style: cardStyle,
          child: !gradientHeader
              ? HeroCard(summary: summary, money: money, title: heroTitle)
              : cardStyle.active
              ? HeroCard(
                  summary: summary,
                  money: money,
                  title: heroTitle,
                  top: OverviewTitle(
                    month: month,
                    now: now,
                    onPrevious: months.previous,
                    onNext: months.next,
                  ),
                )
              : OverviewOnGradient(
                  child: HeroCard(
                    summary: summary,
                    money: money,
                    title: heroTitle,
                    top: OverviewTitle(
                      month: month,
                      now: now,
                      onPrevious: months.previous,
                      onNext: months.next,
                    ),
                  ),
                ),
        ),
      ),
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
    if (!gradientHeader || add == null) return layout;
    return Stack(
      children: [
        Positioned.fill(child: layout),
        Positioned(
          right: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: HomeAddButton(
            onTap: add,
            long: context.layout.windowClass != WindowClass.compact,
          ),
        ),
      ],
    );
  }
}
