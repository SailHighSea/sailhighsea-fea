import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../layout/window_class.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// "‹ October 2026 ›". The arrows sit 10px left of the page margin like the mockups, so
/// the group may use that extra room before the title has to shrink.
class MonthNavigator extends StatelessWidget {
  const MonthNavigator({
    super.key,
    required this.month,
    required this.onPrevious,
    required this.onNext,
    this.titleSize,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final double? titleSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = DateFormat('MMMM yyyy', 'en_US').format(month);
    final size = titleSize ?? context.layout.titleSize;
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: kMinTapTarget,
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          maxWidth: constraints.maxWidth + 10,
          child: Transform.translate(
            offset: const Offset(-10, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MonthButton(
                  icon: Icons.chevron_left_rounded,
                  label: 'Previous month',
                  onTap: onPrevious,
                ),
                Flexible(
                  child: Semantics(
                    header: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: size,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ),
                  ),
                ),
                _MonthButton(
                  icon: Icons.chevron_right_rounded,
                  label: 'Next month',
                  onTap: onNext,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: kMinTapTarget,
          height: kMinTapTarget,
          child: Icon(icon, size: 28, color: context.tokens.text),
        ),
      ),
    );
  }
}
