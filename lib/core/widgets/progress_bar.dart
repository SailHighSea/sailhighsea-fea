import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// A rounded progress bar. [fraction] is 0 to 1; [color] defaults to the primary colour.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.fraction,
    this.height = 8,
    this.color,
  });

  final double fraction;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: t.border)),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color ?? t.primary,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
