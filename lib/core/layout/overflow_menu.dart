import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'destinations.dart';
import 'nav_icon.dart';
import 'window_class.dart';

/// The phone header's menu for destinations that are not bottom tabs (Family, Goals,
/// Bills, Appearance). On the rail and sidebar those are always visible, so this draws
/// nothing there; every item still exists on every size.
class OverflowMenuButton extends StatelessWidget {
  const OverflowMenuButton({super.key, required this.onSelect});

  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    if (!context.layout.isCompact) return const SizedBox.shrink();
    final t = context.tokens;
    return PopupMenuButton<AppDestination>(
      tooltip: 'Menu: family, goals, bills, appearance',
      onSelected: onSelect,
      offset: const Offset(0, kMinTapTarget),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        for (final d in AppDestination.overflow)
          PopupMenuItem<AppDestination>(
            value: d,
            height: kMinTapTarget,
            child: Row(
              children: [
                NavIcon(d, size: 20, color: t.muted),
                const SizedBox(width: 12),
                Text(d.label),
              ],
            ),
          ),
      ],
      child: Container(
        width: kMinTapTarget,
        height: kMinTapTarget,
        decoration: BoxDecoration(
          color: t.surface,
          shape: BoxShape.circle,
          border: Border.all(color: t.chipBorder),
        ),
        child: Icon(Icons.group_outlined, size: 22, color: t.text),
      ),
    );
  }
}
