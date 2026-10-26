import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/theme/app_tokens.dart';
import '../expenses/expense_form_screen.dart' show PrimaryPillButton;
import 'app_lock.dart';

/// Covers the whole app with a lock screen while it is locked, and re-locks after time away.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child, this.clock = DateTime.now});

  final Widget child;
  final DateTime Function() clock;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      ref.read(appLockProvider.notifier).onLifecycle(state, widget.clock());

  Future<void> _unlock() => ref.read(appLockProvider.notifier).unlock();

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    if (lock.locked && !_asked) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unlock();
      });
    }
    if (!lock.locked) _asked = false;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Kept in the tree so nothing is lost, but not drawn or reachable while locked.
        Offstage(
          offstage: lock.locked,
          child: TickerMode(enabled: !lock.locked, child: widget.child),
        ),
        if (lock.locked) const _LockScreen(),
      ],
    );
  }
}

class _LockScreen extends ConsumerWidget {
  const _LockScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    return Material(
      color: t.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: t.primary),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      '$kAppShortName is locked',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Unlock with your fingerprint, face or device PIN.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: t.muted),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryPillButton(
                      key: const ValueKey('unlock'),
                      label: 'Unlock',
                      onTap: () => ref.read(appLockProvider.notifier).unlock(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
