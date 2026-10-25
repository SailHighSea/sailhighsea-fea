import 'package:flutter/material.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';

/// Category tiles, three per row, plus a dashed "+ New" tile.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    this.onAdd,
    this.columns = 3,
    this.scrollable = false,
    this.tileColor,
  });

  final List<CategoryRow> categories;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// `null` hides the "+ New" tile (only owner and admin manage categories).
  final VoidCallback? onAdd;
  final int columns;

  /// One horizontally scrolling row (the fold panel) instead of a grid.
  final bool scrollable;

  /// Tile background when not selected (the fold panel uses a grey tile on white).
  final Color? tileColor;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget Function(double width)>[
      for (final c in categories)
        (w) => _Tile(
          width: w,
          label: c.name,
          selected: c.id == selectedId,
          background: tileColor,
          onTap: () => onSelect(c.id),
        ),
      if (onAdd != null)
        (w) => _Tile(
          width: w,
          label: '+ New',
          selected: false,
          dashed: true,
          onTap: onAdd!,
        ),
    ];
    if (scrollable) {
      return SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tiles.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => tiles[i](104),
        ),
      );
    }
    return Semantics(
      container: true,
      label: 'Category',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final tile in tiles) tile(width)],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.width,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dashed = false,
    this.background,
  });

  final double width;
  final String label;
  final bool selected;
  final bool dashed;
  final Color? background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fill = selected
        ? t.navActiveBackground
        : (dashed ? t.background : (background ?? t.surface));
    final textColor = selected ? t.navActiveText : t.text;
    final child = Semantics(
      button: true,
      selected: selected,
      label: dashed ? 'New category' : label,
      excludeSemantics: true,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinTapTarget + 12),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: selected ? Border.all(color: t.primary, width: 2) : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      width: width,
      child: dashed
          ? CustomPaint(
              foregroundPainter: _DashedBorderPainter(t.grey),
              child: child,
            )
          : child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + 6), paint);
        distance += 10;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
