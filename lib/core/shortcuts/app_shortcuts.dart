import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/adaptive_sheet.dart';
import '../layout/destinations.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// One keyboard shortcut as shown in the help: the keys, and what they do.
class ShortcutInfo {
  const ShortcutInfo(this.keys, this.description);
  final String keys;
  final String description;
}

bool get _isMac => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// "Ctrl" on Windows and Linux, the command key on macOS.
String get modifierLabel => _isMac ? '⌘' : 'Ctrl';

/// Every shortcut, for the help sheet. Bindings below are generated from the same ideas so
/// the list does not drift.
List<ShortcutInfo> shortcutHelp() => [
  ShortcutInfo('$modifierLabel+N', 'Add an expense'),
  ShortcutInfo('$modifierLabel+1', 'Home'),
  ShortcutInfo('$modifierLabel+2', 'Budgets'),
  ShortcutInfo('$modifierLabel+3', 'Insights'),
  ShortcutInfo('$modifierLabel+4', 'Goals'),
  ShortcutInfo('$modifierLabel+5', 'Bills'),
  ShortcutInfo('$modifierLabel+6', 'Family'),
  ShortcutInfo('$modifierLabel+,', 'Appearance'),
  ShortcutInfo('$modifierLabel+F', 'Search expenses'),
  ShortcutInfo('$modifierLabel+/', 'Show this list'),
  const ShortcutInfo('Esc', 'Close, or go back to Home'),
  const ShortcutInfo('Tab', 'Move to the next control'),
];

/// Keyboard shortcuts for the whole app (desktop, and any tablet with a keyboard). Features
/// pass what each shortcut does, so this file knows no screens except the destinations.
class AppShortcuts extends StatelessWidget {
  const AppShortcuts({
    super.key,
    required this.child,
    required this.onAdd,
    required this.onGo,
    required this.onFind,
    required this.onHelp,
    required this.onEscape,
  });

  final Widget child;
  final VoidCallback onAdd;
  final ValueChanged<AppDestination> onGo;
  final VoidCallback onFind;
  final VoidCallback onHelp;
  final VoidCallback onEscape;

  static const _numbered = [
    AppDestination.home,
    AppDestination.budgets,
    AppDestination.insights,
    AppDestination.goals,
    AppDestination.bills,
    AppDestination.family,
  ];

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
  ];

  @override
  Widget build(BuildContext context) {
    Map<ShortcutActivator, VoidCallback> both(
      LogicalKeyboardKey key,
      VoidCallback action,
    ) => {
      SingleActivator(key, control: true): action,
      SingleActivator(key, meta: true): action,
    };
    return CallbackShortcuts(
      bindings: {
        ...both(LogicalKeyboardKey.keyN, onAdd),
        for (var i = 0; i < _numbered.length; i++)
          ...both(_digits[i], () => onGo(_numbered[i])),
        ...both(
          LogicalKeyboardKey.comma,
          () => onGo(AppDestination.appearance),
        ),
        ...both(LogicalKeyboardKey.keyF, onFind),
        ...both(LogicalKeyboardKey.slash, onHelp),
        const SingleActivator(LogicalKeyboardKey.escape): onEscape,
      },
      child: child,
    );
  }
}

/// A sheet (bottom sheet or dialog) listing the shortcuts.
Future<void> showShortcutHelp(BuildContext context) =>
    showAdaptiveSheet<void>(context, builder: (_) => const _ShortcutHelp());

class _ShortcutHelp extends StatelessWidget {
  const _ShortcutHelp();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: const ValueKey('shortcut-help'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Keyboard shortcuts',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final s in shortcutHelp())
          Semantics(
            container: true,
            label: '${s.keys}: ${s.description}',
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: t.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.chipBorder),
                    ),
                    child: Text(
                      s.keys,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      s.description,
                      style: TextStyle(fontSize: 15, color: t.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
