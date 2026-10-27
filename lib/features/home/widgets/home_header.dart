import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/dashboard_layout.dart';
import '../../../core/layout/destinations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/month_navigator.dart';
import '../../profile/profile_avatar.dart';
import '../../profile/profile_provider.dart';
import '../../profile/profile_sheet.dart';

/// Month navigator and the Add button. (Family, Goals, Bills and Appearance are on the phone's
/// Settings tab.)
class HomeHeader extends ConsumerWidget {
  const HomeHeader({
    super.key,
    required this.month,
    required this.onPrevious,
    required this.onNext,
    this.onAdd,
    required this.onSelectDestination,
    required this.mode,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// `null` hides the button (view-only members cannot add expenses).
  final VoidCallback? onAdd;
  final ValueChanged<AppDestination> onSelectDestination;

  /// Phone stacks get the short "+ Add"; wider layouts the full "+ Add expense".
  final DashboardMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final tall = mode == DashboardMode.wide;
    final longAddLabel = mode != DashboardMode.stacked;
    final stacked = mode == DashboardMode.stacked;
    final name = ref.watch(displayNameProvider);

    // Your picture and name: tap to edit the profile.
    final person = Semantics(
      button: true,
      label: 'Edit profile: $name',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('header-avatar'),
        borderRadius: BorderRadius.circular(28),
        onTap: () => showProfileSheet(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProfileAvatar(size: 40),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  name,
                  key: const ValueKey('header-person'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final months = MonthNavigator(
      month: month,
      onPrevious: onPrevious,
      onNext: onNext,
    );
    final add = onAdd == null ? null : _add(context, t, tall, longAddLabel);
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: person),
              ),
              if (add != null) ...[const SizedBox(width: 8), add],
            ],
          ),
          const SizedBox(height: 4),
          months,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: months),
        const SizedBox(width: 12),
        Flexible(child: person),
        if (add != null) ...[const SizedBox(width: 12), add],
      ],
    );
  }

  Widget _add(BuildContext context, AppTokens t, bool tall, bool longAddLabel) {
    return Semantics(
      button: true,
      label: 'Add expense',
      excludeSemantics: true,
      child: Material(
        color: t.primary,
        borderRadius: BorderRadius.circular(AppRadii.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.button),
          onTap: onAdd,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tall ? 48 : kMinTapTarget),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tall ? 24 : (longAddLabel ? 20 : 16),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  longAddLabel ? '+ Add expense' : '+ Add',
                  style: TextStyle(
                    fontSize: longAddLabel ? 15 : 14,
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
