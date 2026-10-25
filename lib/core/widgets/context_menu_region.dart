import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class ContextMenuItem {
  const ContextMenuItem(
    this.label,
    this.onSelected, {
    this.destructive = false,
  });

  final String label;
  final VoidCallback onSelected;

  /// Drawn in the warning colour (Delete).
  final bool destructive;
}

/// A right-click (or long-press) menu for a row or card. The same actions are always also
/// reachable some other way (tap, swipe, row menu), so this only adds a shortcut for mouse
/// and keyboard users. [enabled] false turns the menu off.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({
    super.key,
    required this.items,
    required this.child,
    this.enabled = true,
  });

  final List<ContextMenuItem> items;
  final Widget child;
  final bool enabled;

  Future<void> _show(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final t = context.tokens;
    final chosen = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final item in items)
          PopupMenuItem<VoidCallback>(
            value: item.onSelected,
            height: kMinTapTarget,
            child: Text(
              item.label,
              style: TextStyle(color: item.destructive ? t.rose : t.text),
            ),
          ),
      ],
    );
    chosen?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled || items.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // A shortcut for mouse users; every action is reachable another way, so no semantics.
      excludeFromSemantics: true,
      onSecondaryTapUp: (d) => _show(context, d.globalPosition),
      onLongPressStart: (d) => _show(context, d.globalPosition),
      child: child,
    );
  }
}
