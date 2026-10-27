import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/app_info.dart';
import '../../../core/layout/dashboard_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/appearance_provider.dart';
import '../../../core/theme/appearance_settings.dart';
import '../../../core/theme/color_themes.dart';
import '../../../core/theme/header_gradient.dart';
import '../../../core/widgets/glass.dart';
import '../../family/member_providers.dart';

/// How far the overview card reaches up into the gradient band.
const double kHeaderOverlap = 56;

/// The full-width band at the top of Home: the logo and name on the left, the signed-in person on
/// the right, on the theme's gradient. On a phone it runs under the status bar.
class GradientBand extends ConsumerWidget {
  const GradientBand({super.key, required this.mode});

  final DashboardMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final top = MediaQuery.viewPaddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White clock and icons on the gradient.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Semantics(
        container: true,
        label: '$kAppName, $name',
        child: Container(
          key: const ValueKey('gradient-header'),
          padding: EdgeInsets.fromLTRB(20, top + 14, 20, kHeaderOverlap + 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [a, b],
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/icon/icon.png',
                  width: 44,
                  height: 44,
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      kAppShortName,
                      style: TextStyle(
                        fontSize: 22,
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
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // On your own the name is just "You": the picture says it, and the app name gets
              // the room.
              if (name != 'You') ...[
                Flexible(
                  child: Text(
                    name,
                    key: const ValueKey('header-person'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              ExcludeSemantics(
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.75),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top row of the overview card: the month switch with "October Budget Overview" and how far
/// through the month it is.
class OverviewTitle extends StatelessWidget {
  const OverviewTitle({
    super.key,
    required this.month,
    required this.now,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final DateTime now;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final thisMonth = month.year == now.year && month.month == now.month;
    final past = DateTime(
      month.year,
      month.month,
    ).isBefore(DateTime(now.year, now.month));
    final total = DateUtils.getDaysInMonth(month.year, month.month);
    final label = DateFormat(
      month.year == now.year ? 'MMMM' : 'MMMM yyyy',
      'en_US',
    ).format(month);
    final sub = thisMonth
        ? 'Day ${now.day} of $total'
        : (past ? 'Whole month' : 'Not started yet');
    Widget arrow(IconData icon, String label, VoidCallback onTap) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: kMinTapTarget,
          height: kMinTapTarget,
          child: Icon(icon, color: t.heroText, size: 22),
        ),
      ),
    );
    return Row(
      children: [
        arrow(Icons.chevron_left, 'Previous month', onPrevious),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label Budget Overview',
                key: const ValueKey('overview-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.heroText,
                ),
              ),
              Text(sub, style: TextStyle(fontSize: 12.5, color: t.heroMuted)),
            ],
          ),
        ),
        arrow(Icons.chevron_right, 'Next month', onNext),
      ],
    );
  }
}

/// The overview is a light card with a soft shadow, lifted over the band. It keeps all its
/// content; only its colours change.
class OverviewOnGradient extends StatelessWidget {
  const OverviewOnGradient({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final glass = GlassScope.of(context);
    final themed = t.copyWith(
      // On glass the card is see-through: the glass box below supplies the tint.
      hero: glass ? Colors.transparent : t.surface,
      heroBorder: Colors.transparent,
      heroText: t.text,
      heroMuted: t.muted,
      heroTrack: t.border,
    );
    if (glass) {
      return GlassBox(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Theme(
          data: Theme.of(context).copyWith(extensions: [themed]),
          child: child,
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 8),
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

/// "+ Add" floating over the bottom right of Home.
class HomeAddButton extends StatelessWidget {
  const HomeAddButton({super.key, required this.onTap, required this.long});

  final VoidCallback onTap;

  /// Wide windows get the full "+ Add expense".
  final bool long;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Add expense',
      excludeSemantics: true,
      child: Material(
        color: t.primary,
        elevation: 6,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(AppRadii.button),
        child: InkWell(
          key: const ValueKey('home-add'),
          borderRadius: BorderRadius.circular(AppRadii.button),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Center(
                widthFactor: 1,
                child: Text(
                  long ? '+ Add expense' : '+ Add',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
