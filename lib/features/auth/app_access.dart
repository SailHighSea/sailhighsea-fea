import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../family/member_providers.dart';
import 'auth_providers.dart';

/// Where the person is on the way into the app.
enum AppAccess {
  /// Supabase is not configured: one person, no sign-in, everything stays on this device.
  localOnly,

  /// Checking the saved session and the household.
  starting,
  signedOut,

  /// Signed in for the first time: create a household or join with a code.
  needsHousehold,
  ready,
}

/// Pulls the household from the server once a person is signed in. Failures (offline) are
/// ignored: the local copy keeps the app usable.
final sessionBootstrapProvider = FutureProvider<void>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return;
  try {
    await ref.read(householdControllerProvider).refresh();
  } on Object {
    // Offline or a server hiccup; the cached household, if any, is used.
  }
});

final accessProvider = Provider<AppAccess>((ref) {
  if (ref.watch(authServiceProvider) == null) return AppAccess.localOnly;
  final user = ref.watch(authUserProvider);
  if (user.isLoading) return AppAccess.starting;
  if (user.value == null) return AppAccess.signedOut;
  final boot = ref.watch(sessionBootstrapProvider);
  final member = ref.watch(myMemberProvider);
  // A cached membership opens the app straight away, even offline.
  if (member.value != null) return AppAccess.ready;
  if (boot.isLoading || member.isLoading) return AppAccess.starting;
  return AppAccess.needsHousehold;
});
