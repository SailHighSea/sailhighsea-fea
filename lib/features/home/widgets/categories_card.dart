import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/surface_card.dart';
import '../home_data.dart';

/// Stacked share bar plus a two-column legend of the top categories.
class TopCategoriesCard extends StatelessWidget {
  const TopCategoriesCard({
    super.key,
    required this.categories,
    required this.money,
    this.horizontalPadding = 16,
  });

  final List<CategorySpend> categories;
  final MoneyFormatter money;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = categories.where((c) => c.cents > 0).toList();
    final legend = [
      for (final c in shown)
        _LegendEntry(
          color: t.categoryColor(c.colorKey),
          name: c.name,
          value: money.formatWhole(c.cents),
        ),
    ];
    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 14,
      ),
      semanticLabel:
          'Top categories: ${shown.map((c) => '${c.name} ${money.formatWhole(c.cents)}').join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Top categories',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 10),
          if (shown.isEmpty)
            Text(
              'No spending yet this month',
              style: TextStyle(fontSize: 13, color: t.muted),
            )
          else ...[
            SizedBox(
              height: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: shown[i].cents,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.categoryColor(shown[i].colorKey),
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(i == 0 ? 7 : 0),
                            right: Radius.circular(
                              i == shown.length - 1 ? 7 : 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            for (var row = 0; row < legend.length; row += 2) ...[
              if (row > 0) const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: legend[row]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: row + 1 < legend.length
                        ? legend[row + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.name,
    required this.value,
  });

  final Color color;
  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: t.text),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
      ],
    );
  }
}
