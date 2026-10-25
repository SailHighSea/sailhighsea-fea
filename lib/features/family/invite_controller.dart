import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/household_remote.dart';
import 'domain/role.dart';
import 'member_providers.dart';

class InviteState {
  const InviteState({
    this.role = Role.editor,
    this.created,
    this.busy = false,
    this.error,
  });

  /// Role the next code will carry.
  final Role role;

  /// The code just created. It is shown once; the server keeps only a hash.
  final CreatedInvite? created;
  final bool busy;
  final String? error;

  InviteState copyWith({
    Role? role,
    CreatedInvite? created,
    bool clearCreated = false,
    bool? busy,
    String? error,
    bool clearError = false,
  }) => InviteState(
    role: role ?? this.role,
    created: clearCreated ? null : (created ?? this.created),
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
  );
}

/// State of the "Invite someone" card.
class InviteController extends Notifier<InviteState> {
  @override
  InviteState build() => const InviteState();

  /// Picking another role drops the code on screen: a code carries one role for good.
  void setRole(Role role) {
    if (role == state.role) return;
    state = InviteState(role: role);
  }

  Future<void> create() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final created = await ref
          .read(householdControllerProvider)
          .createInvite(state.role);
      state = state.copyWith(created: created, busy: false);
      ref.invalidate(pendingInvitesProvider);
    } on HouseholdFailure catch (e) {
      state = state.copyWith(busy: false, error: e.message);
    }
  }

  Future<String?> revoke(String inviteId) async {
    try {
      await ref.read(householdControllerProvider).revokeInvite(inviteId);
      ref.invalidate(pendingInvitesProvider);
      return null;
    } on HouseholdFailure catch (e) {
      return e.message;
    }
  }
}

final inviteControllerProvider =
    NotifierProvider.autoDispose<InviteController, InviteState>(
      InviteController.new,
    );

/// Codes that were created and not used or expired yet (their text is not recoverable).
final pendingInvitesProvider = FutureProvider.autoDispose<List<PendingInvite>>((
  ref,
) async {
  if (!ref.watch(permissionsProvider).canInvite) return const [];
  if (ref.watch(householdRemoteProvider) == null) return const [];
  try {
    return await ref.read(householdControllerProvider).invites();
  } on HouseholdFailure {
    return const [];
  }
});
