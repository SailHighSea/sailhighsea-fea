import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/insights_calculations.dart';

String _whole(MoneyFormatter money, int cents) {
  final factor = money.currency.minorFactor;
  final rounded = (cents + factor ~/ 2) ~/ factor;
  return NumberFormat.decimalPattern('en_US').format(rounded);
}

/// "Last 6 months": one bar per period with its value above it. The current period is the
/// strong colour, the others a tint of it.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.bars, required this.money});

  final List<TrendBar> bars;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tint = Color.alphaBlend(t.primary.withValues(alpha: 0.28), t.surface);
    final maxCents = bars.fold<int>(0, (m, b) => b.cents > m ? b.cents : m);
    final top = maxCents <= 0 ? 1.0 : maxCents * 1.18;
    final summary = [
      for (final b in bars) '${b.label} ${_whole(money, b.cents)}',
    ].join(', ');
    final many = bars.length > 8;
    return Semantics(
      label: 'Bar chart. $summary',
      excludeSemantics: true,
      child: SizedBox(
        height: 190,
        child: BarChart(
          duration: Duration.zero,
          BarChartData(
            maxY: top,
            minY: 0,
            alignment: BarChartAlignment.spaceAround,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              enabled: false,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => Colors.transparent,
                tooltipPadding: EdgeInsets.zero,
                tooltipMargin: 2,
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                      many && !bars[groupIndex].highlight
                          ? ''
                          : _whole(money, bars[groupIndex].cents),
                      TextStyle(
                        fontSize: 12,
                        fontWeight: bars[groupIndex].highlight
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: bars[groupIndex].highlight ? t.text : t.muted,
                      ),
                    ),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    final bar = bars[value.toInt()];
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        bar.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: bar.highlight
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: bar.highlight ? t.text : t.muted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < bars.length; i++)
                BarChartGroupData(
                  x: i,
                  showingTooltipIndicators: const [0],
                  barRods: [
                    BarChartRodData(
                      toY: bars[i].cents.toDouble(),
                      width: many ? 14 : 32,
                      color: bars[i].highlight ? t.primary : tint,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Daily spending, 1 to 24 Oct": a bar per day, amber when over the daily pace, with the
/// dashed pace line.
class DailyChart extends StatelessWidget {
  const DailyChart({
    super.key,
    required this.points,
    required this.paceCents,
    required this.monthLabel,
  });

  final List<DayPoint> points;
  final int paceCents;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final maxCents = points.fold<int>(
      paceCents,
      (m, p) => p.cents > m ? p.cents : m,
    );
    final top = maxCents <= 0 ? 1.0 : maxCents * 1.1;
    final highest = points.fold<int>(0, (m, p) => p.cents > m ? p.cents : m);
    return Semantics(
      label:
          'Daily spending bar chart for $monthLabel, ${points.length} days, highest day ${highest ~/ 100}',
      excludeSemantics: true,
      child: SizedBox(
        height: 160,
        child: BarChart(
          duration: Duration.zero,
          BarChartData(
            maxY: top,
            minY: 0,
            alignment: BarChartAlignment.spaceBetween,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: const BarTouchData(enabled: false),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                if (paceCents > 0)
                  HorizontalLine(
                    y: paceCents.toDouble(),
                    color: t.text,
                    strokeWidth: 2,
                    dashArray: const [6, 4],
                  ),
              ],
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    final edge = i == 0 || i == points.length - 1;
                    if (!edge) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '$monthLabel ${points[i].day}',
                        style: TextStyle(fontSize: 12, color: t.muted),
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: points[i].cents.toDouble(),
                      width: points.length > 20 ? 8 : 12,
                      color: paceCents > 0 && points[i].cents > paceCents
                          ? t.amberBar
                          : t.primary,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
