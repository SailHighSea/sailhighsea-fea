import 'package:flutter/material.dart';

import '../../../core/layout/dashboard_layout.dart';
import '../../../core/layout/destinations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/month_navigator.dart';

/// Month navigator and the Add button. (Family, Goals, Bills and Appearance are on the phone's
/// Settings tab.)
class HomeHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tall = mode == DashboardMode.wide;
    final longAddLabel = mode != DashboardMode.stacked;
    return Row(
      children: [
        Expanded(
          child: MonthNavigator(
            month: month,
            onPrevious: onPrevious,
            onNext: onNext,
          ),
        ),
        if (onAdd != null) ...[
          const SizedBox(width: 8),
          Semantics(
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
                  constraints: BoxConstraints(
                    minHeight: tall ? 48 : kMinTapTarget,
                  ),
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
          ),
        ],
      ],
    );
  }
}
