import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/personal_background.dart';
import '../../../core/theme/personal_look.dart';

/// Puts the person's own background (colour, gradient or picture) behind the Home hero card and
/// turns its text light or dark to match. Without a background the card is left exactly as is.
class PersonalHero extends StatelessWidget {
  const PersonalHero({super.key, required this.style, required this.child});

  final BackgroundStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!style.active) return child;
    final t = context.tokens;
    final text = style.lightText ? Colors.white : const Color(0xFF0F1F1A);
    final themed = t.copyWith(
      hero: Colors.transparent,
      heroBorder: Colors.transparent,
      heroText: text,
      heroMuted: text.withValues(alpha: 0.78),
      heroTrack: text.withValues(alpha: 0.22),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: PersonalBackground(style: style),
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(extensions: [themed]),
          child: child,
        ),
      ],
    );
  }
}
