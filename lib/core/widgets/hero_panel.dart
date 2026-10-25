import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// The dark rounded summary card at the top of Goals and Bills (same colours as the Home
/// hero in every theme).
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.action,
  });

  final String label;
  final String value;
  final String? caption;

  /// A button placed beside the numbers.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: t.heroMuted)),
        const SizedBox(height: 4),
        Semantics(
          label: '$label $value',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: t.heroText,
              ),
            ),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(caption!, style: TextStyle(fontSize: 14, color: t.heroMuted)),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.hero,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: action == null
          ? SizedBox(width: double.infinity, child: text)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [text, const SizedBox(height: 14), action!],
            ),
    );
  }
}
