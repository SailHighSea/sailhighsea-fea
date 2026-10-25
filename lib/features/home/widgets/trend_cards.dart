import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/surface_card.dart';
import '../home_data.dart';

/// Horizontal dashed line drawn across a chart at the daily pace.
class DashedLine extends StatelessWidget {
  const DashedLine({
    super.key,
    required this.color,
    this.thickness = 2,
    this.dash = 6,
    this.gap = 4,
  });

  final Color color;
  final double thickness;
  final double dash;
  final double gap;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(double.infinity, thickness),
    painter: _DashPainter(color, thickness, dash, gap),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.thickness, this.dash, this.gap);

  final Color color;
  final double thickness;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.color != color || old.thickness != thickness;
}

/// How big the 7-day chart is: phone size or the roomier tablet size.
enum WeekChartSize {
  compact(
    chartHeight: 112,
    barMax: 90,
    gap: 8,
    barWidth: 0.7,
    labelSize: 11,
    padding: 16,
  ),
  roomy(
    chartHeight: 144,
    barMax: 120,
    gap: 14,
    barWidth: 0.6,
    labelSize: 12,
    padding: 20,
  );

  const WeekChartSize({
    required this.chartHeight,
    required this.barMax,
    required this.gap,
    required this.barWidth,
    required this.labelSize,
    required this.padding,
  });

  final double chartHeight;
  final double barMax;
  final double gap;
  final double barWidth;
  final double labelSize;
  final double padding;
}

/// "Last 7 days" bars with the dashed daily-pace line.
class WeekBarsCard extends StatelessWidget {
  const WeekBarsCard({
    super.key,
    required this.summary,
    required this.money,
    required this.size,
    required this.onFullDashboard,
  });

  final HomeSummary summary;
  final MoneyFormatter money;
  final WeekChartSize size;
  final VoidCallback onFullDashboard;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bars = summary.last7;
    final maxCents = bars.fold<int>(
      summary.paceCents,
      (m, b) => b.cents > m ? b.cents : m,
    );
    // Bar value labels grow with text size but stop at 1.4x so the bars keep their room.
    final labelScale = MediaQuery.textScalerOf(context)
        .scale(1)
        .clamp(1.0, 1.4);
    final barMax = math.min(
      size.barMax,
      size.chartHeight - 6 - size.labelSize * 1.35 * labelScale,
    );
    final scale = maxCents == 0 ? 0.0 : barMax / maxCents;
    final paceHeight = summary.paceCents * scale;
    final labelColor = t.muted;
    final todayLabel = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: t.text,
    );

    return SurfaceCard(
      padding: EdgeInsets.symmetric(horizontal: size.padding, vertical: 14),
      semanticLabel:
          'Last 7 days spending. ${money.formatWhole(summary.paceCents)} a day keeps you on budget.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last 7 days',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              TextLinkButton(label: 'Full dashboard', onTap: onFullDashboard),
            ],
          ),
          SizedBox(
            height: size.chartHeight,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: paceHeight,
                  child: DashedLine(color: t.text),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < bars.length; i++) ...[
                      if (i > 0) SizedBox(width: size.gap),
                      Expanded(
                        child: _Bar(
                          labelScale: labelScale,
                          value: bars[i].cents,
                          valueText: _wholeNumber(bars[i].cents),
                          height: bars[i].cents * scale,
                          widthFactor: size.barWidth,
                          color: bars[i].highlight ? t.primary : t.neutralBar,
                          labelStyle: bars[i].highlight
                              ? TextStyle(
                                  fontSize: size.labelSize,
                                  fontWeight: FontWeight.w700,
                                  color: t.text,
                                )
                              : TextStyle(
                                  fontSize: size.labelSize,
                                  color: labelColor,
                                ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < bars.length; i++) ...[
                if (i > 0) SizedBox(width: size.gap),
                Expanded(
                  child: Text(
                    bars[i].label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: bars[i].highlight
                        ? todayLabel
                        : TextStyle(fontSize: 12, color: labelColor),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Dashed line: ${money.formatWhole(summary.paceCents)} a day keeps you on budget',
            style: TextStyle(fontSize: 12, color: labelColor),
          ),
        ],
      ),
    );
  }

  /// Bar labels show whole currency units without the symbol, like the mockup (130, 50).
  String _wholeNumber(int cents) {
    final text = money.formatWhole(cents);
    return text.replaceFirst(money.currency.symbol, '');
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.valueText,
    required this.height,
    required this.widthFactor,
    required this.color,
    required this.labelStyle,
    required this.labelScale,
  });

  final int value;
  final String valueText;
  final double height;
  final double widthFactor;
  final Color color;
  final TextStyle labelStyle;
  final double labelScale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          valueText,
          style: labelStyle,
          maxLines: 1,
          textScaler: TextScaler.linear(labelScale),
        ),
        const SizedBox(height: 3),
        FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Desktop variant: every day of the month, green under the daily pace and amber over it.
class MonthBarsCard extends StatelessWidget {
  const MonthBarsCard({
    super.key,
    required this.summary,
    required this.money,
    required this.rangeTitle,
    required this.startLabel,
    required this.endLabel,
    required this.onFullDashboard,
  });

  final HomeSummary summary;
  final MoneyFormatter money;
  final String rangeTitle;
  final String startLabel;
  final String endLabel;
  final VoidCallback onFullDashboard;

  static const double _chartHeight = 130;
  static const double _barMax = 120;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bars = summary.monthDaily;
    final maxCents = bars.fold<int>(
      summary.paceCents,
      (m, b) => b.cents > m ? b.cents : m,
    );
    final scale = maxCents == 0 ? 0.0 : _barMax / maxCents;
    final paceText =
        '${money.formatWhole(summary.paceCents)} a day keeps you on budget';
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      semanticLabel: 'Daily spending, $rangeTitle. $paceText.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rangeTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              TextLinkButton(label: 'Full dashboard', onTap: onFullDashboard),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _chartHeight,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: summary.paceCents * scale,
                  child: DashedLine(color: t.text),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < bars.length; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Expanded(
                        child: Container(
                          height: bars[i].cents * scale,
                          decoration: BoxDecoration(
                            color: bars[i].cents > summary.paceCents
                                ? t.amberBar
                                : t.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(startLabel, style: TextStyle(fontSize: 12, color: t.muted)),
              Text(endLabel, style: TextStyle(fontSize: 12, color: t.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _LegendSwatch(color: t.primary, label: 'Under pace'),
              _LegendSwatch(color: t.amberBar, label: 'Over pace'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    child: DashedLine(color: t.text, dash: 3, gap: 2),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    paceText,
                    style: TextStyle(fontSize: 12, color: t.muted),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: t.muted)),
      ],
    );
  }
}
