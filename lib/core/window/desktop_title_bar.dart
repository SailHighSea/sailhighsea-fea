import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'window_controls.dart';

/// The window's title bar drawn in the app's own colours, so it follows Light, Dark and Pure
/// black and the colour theme. Drag it to move the window, double-click to maximize. Windows and
/// Linux get minimize, maximize and close on the right; macOS keeps its own round buttons on the
/// left and this bar leaves room for them.
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({
    super.key,
    required this.controls,
    this.platform,
    this.title = 'Family Expenses',
  });

  final WindowControls controls;

  /// Defaults to the running platform; tests choose one.
  final TargetPlatform? platform;
  final String title;

  static const double heightFor = 44;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> {
  bool _maximized = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    widget.controls.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
    _sub = widget.controls.maximizedChanges.listen((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final platform = widget.platform ?? defaultTargetPlatform;
    final mac = platform == TargetPlatform.macOS;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Material(
        color: t.background,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: SizedBox(
            height: DesktopTitleBar.heightFor,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    key: const ValueKey('title-bar-drag'),
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => widget.controls.startDragging(),
                    onDoubleTap: widget.controls.toggleMaximize,
                    child: Padding(
                      // Room for the three round macOS buttons.
                      padding: EdgeInsets.only(left: mac ? 80 : 14),
                      child: Align(
                        alignment: mac
                            ? Alignment.center
                            : Alignment.centerLeft,
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!mac) ...[
                  _CaptionButton(
                    key: const ValueKey('title-minimize'),
                    label: 'Minimize',
                    icon: Icons.remove,
                    onTap: widget.controls.minimize,
                  ),
                  _CaptionButton(
                    key: const ValueKey('title-maximize'),
                    label: _maximized ? 'Restore' : 'Maximize',
                    icon: _maximized ? Icons.filter_none : Icons.crop_square,
                    iconSize: _maximized ? 14 : 16,
                    onTap: widget.controls.toggleMaximize,
                  ),
                  _CaptionButton(
                    key: const ValueKey('title-close'),
                    label: 'Close',
                    icon: Icons.close,
                    onTap: widget.controls.close,
                    danger: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconSize = 16,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Close turns red under the pointer, like the system one; the others tint with the theme.
    final hoverColor = widget.danger
        ? const Color(0xFFC42B1C)
        : t.text.withValues(alpha: 0.08);
    final iconColor = widget.danger && _hover ? Colors.white : t.text;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 48,
            height: DesktopTitleBar.heightFor,
            color: _hover ? hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
