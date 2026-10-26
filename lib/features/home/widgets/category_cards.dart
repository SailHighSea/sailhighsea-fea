import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/category_style.dart';
import '../../../core/widgets/surface_card.dart';
import '../home_data.dart';

String _changeLabel(CategoryCompare c) {
  final p = c.changePercent;
  if (p == null) return c.cents > 0 ? 'new' : '';
  if (p == 0) return 'same';
  return '${p > 0 ? '+' : '−'}${p.abs()}%';
}

/// "Categories vs last month": a bar per category in its colour, a tick where the category stood
/// at the same point last month, and a chip with the change.
class CategoryCompareCard extends StatelessWidget {
  const CategoryCompareCard({
    super.key,
    required this.items,
    required this.money,
    this.horizontalPadding = 16,
    this.limit = 6,
  });

  final List<CategoryCompare> items;
  final MoneyFormatter money;
  final double horizontalPadding;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = items.take(limit).toList();
    final maxCents = shown.fold<int>(
      1,
      (m, c) => [m, c.cents, c.previousCents].reduce((a, b) => a > b ? a : b),
    );
    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 14,
      ),
      semanticLabel:
          'Categories against last month: ${shown.map((c) => '${c.name} ${money.formatWhole(c.cents)}, last month ${money.formatWhole(c.previousCents)}').join('; ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Compared with last month',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Text(
              'No spending to compare yet',
              style: TextStyle(fontSize: 13, color: t.muted),
            )
          else
            for (final c in shown) ...[
              _CompareRow(item: c, maxCents: maxCents, money: money),
              const SizedBox(height: 12),
            ],
          if (shown.isNotEmpty)
            Row(
              children: [
                Container(
                  width: 3,
                  height: 12,
                  decoration: BoxDecoration(
                    color: t.text.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Same time last month',
                  style: TextStyle(fontSize: 12, color: t.muted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.item,
    required this.maxCents,
    required this.money,
  });

  final CategoryCompare item;
  final int maxCents;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.categoryColor(item.colorKey);
    final change = _changeLabel(item);
    final p = item.changePercent;
    final up = (p ?? 1) > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
            Text(
              money.formatWhole(item.cents),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            if (change.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  change,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: p == 0 ? t.muted : (up ? t.rose : t.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            double at(int cents) => (cents / maxCents).clamp(0.0, 1.0) * w;
            return SizedBox(
              height: 14,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 1,
                    height: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 1,
                    height: 12,
                    width: at(item.cents).clamp(item.cents > 0 ? 6.0 : 0.0, w),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  if (item.previousCents > 0)
                    Positioned(
                      left: (at(item.previousCents) - 1.5).clamp(0.0, w - 3),
                      top: -2,
                      width: 3,
                      height: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.text.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Small tiles, two or three across: the category's icon in its colour, the name, the amount and
/// a bar. Reads at a glance and each tile is a comfortable tap target.
class CategoryTilesCard extends StatelessWidget {
  const CategoryTilesCard({
    super.key,
    required this.items,
    required this.money,
    this.horizontalPadding = 16,
    this.columns,
    this.limit = 6,
  });

  final List<CategoryCompare> items;
  final MoneyFormatter money;
  final double horizontalPadding;

  /// Fixed column count; by default two, or three when there is room.
  final int? columns;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = items.where((c) => c.cents > 0).take(limit).toList();
    final maxCents = shown.fold<int>(1, (m, c) => c.cents > m ? c.cents : m);
    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 14,
      ),
      semanticLabel:
          'Categories: ${shown.map((c) => '${c.name} ${money.formatWhole(c.cents)}').join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'By category',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Text(
              'No categories to show yet',
              style: TextStyle(fontSize: 13, color: t.muted),
            )
          else
            LayoutBuilder(
              builder: (context, box) {
                final cols = columns ?? (box.maxWidth >= 460 ? 3 : 2);
                const gap = 10.0;
                final w = (box.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final c in shown)
                      SizedBox(
                        width: w,
                        child: _Tile(item: c, maxCents: maxCents, money: money),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.maxCents,
    required this.money,
  });

  final CategoryCompare item;
  final int maxCents;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.categoryColor(item.colorKey);
    return Container(
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(minHeight: 92),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(
                  categoryIconData(item.icon),
                  size: 16,
                  color: t.surface,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            money.formatWhole(item.cents),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Container(
                  height: 8,
                  width: box.maxWidth,
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Container(
                  height: 8,
                  width:
                      (item.cents / maxCents).clamp(0.0, 1.0) * box.maxWidth < 6
                      ? 6
                      : (item.cents / maxCents).clamp(0.0, 1.0) * box.maxWidth,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
