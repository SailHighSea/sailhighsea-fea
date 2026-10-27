import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/destinations.dart';
import '../../core/layout/nav_icon.dart';
import '../../core/layout/page_layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/surface_card.dart';
import '../profile/profile_avatar.dart';
import '../profile/profile_provider.dart';
import '../profile/profile_sheet.dart';

/// The Settings tab on the phone: everything that is not a bottom tab (Family, Goals, Bills,
/// Appearance) and a shortcut to importing expenses. On the rail and sidebar these are always
/// visible, so nothing exists on one size only.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final name = ref.watch(displayNameProvider);
    return AdaptivePage(
      header: const PageHeader(title: 'Settings'),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _Item(
            key: const ValueKey('settings-profile'),
            icon: const ProfileAvatar(size: 40),
            label: 'Edit profile: $name',
            onTap: () => showProfileSheet(context),
            divider: false,
            title: name,
            subtitle: 'Edit your name and picture',
          ),
        ),
        const SizedBox(height: 12),
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
    this.title,
    this.subtitle,
  });

  /// Shown instead of [label] (which stays the spoken name) with a line under it.
  final String? title;
  final String? subtitle;

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
                SizedBox(
                  width: subtitle == null ? 28 : 40,
                  child: Center(child: icon),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 13, color: t.muted),
                        ),
                    ],
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
