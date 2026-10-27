import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/layout/dashboard_layout.dart';
import '../../../core/layout/destinations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/appearance_provider.dart';
import '../../../core/theme/appearance_settings.dart';
import '../../../core/theme/color_themes.dart';
import '../../../core/theme/header_gradient.dart';
import '../../family/member_providers.dart';
import 'home_header.dart';

/// How far the overview card reaches up into the gradient band.
const double kHeaderOverlap = 40;

/// The Home header with a gradient: the logo and name on the left, the signed-in person on the
/// right, and the month switch and Add button beneath, all on the theme's gradient.
class GradientHomeHeader extends ConsumerWidget {
  const GradientHomeHeader({
    super.key,
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onAdd,
    required this.onSelectDestination,
    required this.mode,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onAdd;
  final ValueChanged<AppDestination> onSelectDestination;
  final DashboardMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final settings = ref.watch(appearanceProvider);
    final brightness = Theme.of(context).brightness;
    final variant = brightness == Brightness.light
        ? ThemeVariant.light
        : (settings.mode == AppearanceMode.pureBlack
              ? ThemeVariant.pure
              : ThemeVariant.dark);
    final (a, b) = headerGradientFor(settings.colorTheme, variant);
    final me = ref.watch(myMemberProvider).value;
    final name = (me?.displayName.trim().isEmpty ?? true)
        ? 'You'
        : me!.displayName.trim();
    final initial = String.fromCharCode(name.runes.first).toUpperCase();
    // Inside the gradient the controls are white, whatever the theme.
    final onGradient = t.copyWith(
      text: Colors.white,
      primary: Colors.white,
      onPrimary: a,
    );
    return Semantics(
      container: true,
      label: '$kAppName, $name',
      child: Container(
        key: const ValueKey('gradient-header'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8 + kHeaderOverlap),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [a, b],
          ),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 40,
                    height: 40,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        kAppShortName,
                        style: TextStyle(
                          fontSize: 21,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Family Expenses Tracker',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // On your own the name is just "You": the picture says it, and the full app name
                // gets the room.
                if (name != 'You') ...[
                  Flexible(
                    child: Text(
                      name,
                      key: const ValueKey('header-person'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                ExcludeSemantics(
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.7),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(extensions: [onGradient]),
              child: HomeHeader(
                month: month,
                onPrevious: onPrevious,
                onNext: onNext,
                onAdd: onAdd,
                onSelectDestination: onSelectDestination,
                mode: mode,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Under the gradient band the overview is a light card with a soft shadow, as in the proposal.
/// The card keeps all its content; only its colours change.
class OverviewOnGradient extends StatelessWidget {
  const OverviewOnGradient({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final themed = t.copyWith(
      hero: t.surface,
      heroBorder: t.border,
      heroText: t.text,
      heroMuted: t.muted,
      heroTrack: t.border,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(extensions: [themed]),
        child: child,
      ),
    );
  }
}
