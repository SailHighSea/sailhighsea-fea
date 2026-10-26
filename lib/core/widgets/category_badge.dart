import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/category_style.dart';

/// A category's icon in its colour on a soft round tile.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({
    super.key,
    required this.icon,
    required this.colorKey,
    this.size = 40,
  });

  final String? icon;
  final String colorKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = t.categoryColor(colorKey);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(categoryIconData(icon), size: size * 0.55, color: c),
      ),
    );
  }
}
