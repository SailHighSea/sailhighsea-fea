import 'package:flutter/material.dart';

import '../../core/widgets/async_placeholder.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/adaptive_grid.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/segmented_pills.dart';
import '../../core/widgets/surface_card.dart';
import '../family/member_providers.dart';
import '../overview/overview_providers.dart';
import '../overview/widgets/overview_view.dart';
import 'domain/insights_calculations.dart';
import 'insights_providers.dart';
import '../home/widgets/trend_cards.dart' show DashedLine;
import 'widgets/charts.dart';
import 'widgets/insight_cards.dart';

/// Insights and the Dashboard (Insights, Dashboard, TabInsights, DeskInsights mockups): week,
/// month or year with stat tiles, trend and daily charts, spending by category, who spent
/// what, and a note or two. Charts use the category colours, so the colour-blind palette
/// from Appearance applies.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSeeEveryone = ref.watch(canSeeEveryoneProvider);
    final tab = ref.watch(insightsTabProvider);
    final async = ref.watch(insightsProvider);
    final data = async.value;
    final t = context.tokens;
    final tabs = canSeeEveryone
        ? SegmentedPills(
            labels: const ['Insights', 'Everyone'],
            selected: tab == InsightsTab.everyone ? 1 : 0,
            onChanged: (i) => ref
                .read(insightsTabProvider.notifier)
                .select(i == 1 ? InsightsTab.everyone : InsightsTab.charts),
          )
        : null;
    if (canSeeEveryone && tab == InsightsTab.everyone) {
      return AdaptivePage(
        header: const PageHeader(title: 'Insights'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 320, child: tabs),
          ),
          const SizedBox(height: 14),
          const OverviewView(),
        ],
      );
    }
    if (data == null) {
      return AsyncPlaceholder(
        what: 'insights',
        error: async.hasError ? async.error : null,
        onRetry: () => ref.invalidate(insightsProvider),
      );
    }
    final money = ref.watch(moneyFormatterProvider);
    final period = ref.watch(insightsPeriodProvider);
    final monthShort = DateFormat('MMM', 'en_US').format(data.month);
    final monthName = DateFormat('MMMM', 'en_US').format(data.month);
    final empty = data.totalCents == 0;

    final periodSwitch = SegmentedPills(
      labels: [for (final p in InsightsPeriod.values) p.label],
      selected: period.index,
      onChanged: (i) => ref
          .read(insightsPeriodProvider.notifier)
          .select(InsightsPeriod.values[i]),
    );

    final detail = <Widget>[
      InsightCard(
        title: data.trendTitle,
        trailing: period == InsightsPeriod.month ? null : money.currency.symbol,
        child: TrendChart(bars: data.trend, money: money),
      ),
      if (period == InsightsPeriod.month && data.daily.isNotEmpty)
        InsightCard(
          title: data.dailyTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DailyChart(
                points: data.daily,
                paceCents: data.paceCents,
                monthLabel: monthShort,
              ),
              const SizedBox(height: 10),
              _Legend(
                items: [(t.primary, 'Under pace'), (t.amberBar, 'Over pace')],
                dashed: data.paceCents > 0
                    ? '${money.formatWhole(data.paceCents)} a day keeps you on budget'
                    : null,
              ),
            ],
          ),
        ),
    ];

    final breakdown = <Widget>[
      InsightCard(
        title: period == InsightsPeriod.year
            ? 'Spending by category, ${data.month.year}'
            : (period == InsightsPeriod.week
                  ? 'Spending by category'
                  : 'Where it went in $monthName'),
        child: data.categories.isEmpty
            ? Text('Nothing spent yet.', style: TextStyle(color: t.muted))
            : CategoryBars(lines: data.categories, money: money),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InsightCard(
            title: 'Who spent what',
            child: data.members.isEmpty
                ? Text('Nothing spent yet.', style: TextStyle(color: t.muted))
                : MemberShares(members: data.members, money: money),
          ),
          for (final note in data.notes) ...[
            const SizedBox(height: 12),
            NoteBox(note: note),
          ],
        ],
      ),
    ];

    return AdaptivePage(
      header: PageHeader(
        title: 'Insights',
        trailing: SizedBox(width: 300, child: periodSwitch),
        trailingBelowWhenCompact: true,
      ),
      children: [
        if (tabs != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: 320, child: tabs),
          ),
          const SizedBox(height: 14),
        ],
        AdaptiveGrid(
          compact: 2,
          medium: 4,
          wide: 4,
          children: [
            for (final s in data.stats) StatCard(tile: s, money: money),
          ],
        ),
        const SizedBox(height: 14),
        if (empty)
          SurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Text(
              'No spending in this ${period.label.toLowerCase()} yet. Charts appear as expenses are added.',
              key: const ValueKey('insights-empty'),
              style: TextStyle(fontSize: 15, height: 1.35, color: t.muted),
            ),
          )
        else ...[
          AdaptiveGrid(
            compact: 1,
            medium: 1,
            wide: 2,
            gap: 16,
            children: detail,
          ),
          const SizedBox(height: 14),
          AdaptiveGrid(
            compact: 1,
            medium: 2,
            wide: 2,
            gap: 16,
            children: breakdown,
          ),
        ],
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items, this.dashed});

  final List<(Color, String)> items;
  final String? dashed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = TextStyle(fontSize: 13, color: t.muted);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final (color, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: style),
            ],
          ),
        if (dashed != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                child: DashedLine(color: t.text, thickness: 2, dash: 4, gap: 3),
              ),
              const SizedBox(width: 4),
              Flexible(child: Text(dashed!, style: style)),
            ],
          ),
      ],
    );
  }
}
