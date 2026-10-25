import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/theme/appearance_provider.dart';

/// Asks the device to confirm who is holding it (fingerprint, face, PIN, Windows Hello).
/// Hardware-specific, so it sits behind an interface (rule 1).
abstract interface class AppLockService {
  /// False where the device has no screen lock to ask (and on Linux).
  Future<bool> isSupported();

  Future<bool> authenticate(String reason);
}

class LocalAuthLockService implements AppLockService {
  LocalAuthLockService([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final appLockServiceProvider = Provider<AppLockService>(
  (ref) => LocalAuthLockService(),
);

/// Whether the device can lock at all (drives whether the switch is offered).
final appLockSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(appLockServiceProvider).isSupported(),
);

const _kEnabled = 'privacy.appLock';

/// How long the app may be in the background before it asks again.
const appLockGrace = Duration(seconds: 30);

class AppLockState {
  const AppLockState({required this.enabled, required this.locked});
  final bool enabled;
  final bool locked;
}

/// The lock setting and whether the app is locked right now. Starts locked when enabled; locks
/// again when the app comes back after [appLockGrace] away.
class AppLockController extends Notifier<AppLockState> {
  DateTime? _leftAt;

  @override
  AppLockState build() {
    final enabled =
        ref.watch(sharedPreferencesProvider).getBool(_kEnabled) ?? false;
    return AppLockState(enabled: enabled, locked: enabled);
  }

  /// Turns the lock on only after the person proves they can unlock (so they are not locked out).
  Future<bool> enable() async {
    final ok = await ref
        .read(appLockServiceProvider)
        .authenticate('Turn on the app lock');
    if (!ok || !ref.mounted) return false;
    await ref.read(sharedPreferencesProvider).setBool(_kEnabled, true);
    state = const AppLockState(enabled: true, locked: false);
    return true;
  }

  Future<void> disable() async {
    await ref.read(sharedPreferencesProvider).setBool(_kEnabled, false);
    state = const AppLockState(enabled: false, locked: false);
  }

  Future<bool> unlock() async {
    final ok = await ref
        .read(appLockServiceProvider)
        .authenticate('Unlock Family Expenses');
    if (ok && ref.mounted) {
      state = AppLockState(enabled: state.enabled, locked: false);
    }
    return ok;
  }

  void onLifecycle(AppLifecycleState s, DateTime now) {
    if (!state.enabled) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _leftAt ??= now;
    } else if (s == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && now.difference(left) >= appLockGrace) {
        state = const AppLockState(enabled: true, locked: true);
      }
    }
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);
