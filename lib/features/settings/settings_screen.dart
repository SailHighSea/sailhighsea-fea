import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/destinations.dart';
import '../../core/layout/nav_icon.dart';
import '../../core/layout/page_layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/surface_card.dart';

/// The Settings tab on the phone: everything that is not a bottom tab (Family, Goals, Bills,
/// Appearance) and a shortcut to importing expenses. On the rail and sidebar these are always
/// visible, so nothing exists on one size only.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AdaptivePage(
      header: const PageHeader(title: 'Settings'),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < AppDestination.overflow.length; i++)
                _Item(
                  key: ValueKey('settings-${AppDestination.overflow[i].name}'),
                  icon: NavIcon(
                    AppDestination.overflow[i],
                    size: 22,
                    color: t.primary,
                  ),
                  label: AppDestination.overflow[i].label,
                  onTap: () => context.go(AppDestination.overflow[i].path),
                  divider: i > 0,
                ),
              _Item(
                key: const ValueKey('settings-import'),
                icon: Icon(Icons.upload_file, size: 22, color: t.primary),
                label: 'Import expenses',
                onTap: () => context.push('/import'),
                divider: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.divider,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: divider ? Border(top: BorderSide(color: t.border)) : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                SizedBox(width: 28, child: Center(child: icon)),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: t.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
