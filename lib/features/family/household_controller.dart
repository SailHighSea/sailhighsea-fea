import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../auth/auth_service.dart';
import 'data/household_remote.dart';
import 'data/household_repository.dart';
import 'domain/role.dart';
import 'member_providers.dart';

/// Household actions: each one asks the server (which enforces the roles), then refreshes
/// the local copy the screens read. Failures arrive as [HouseholdFailure].
class HouseholdController {
  HouseholdController(this._ref);

  final Ref _ref;

  HouseholdRemote get _remote {
    final remote = _ref.read(householdRemoteProvider);
    if (remote == null) throw const HouseholdFailure(HouseholdError.offline);
    return remote;
  }

  AuthUser get _user {
    final user = _ref.read(authServiceProvider)?.currentUser;
    if (user == null) throw const HouseholdFailure(HouseholdError.forbidden);
    return user;
  }

  HouseholdRepository get _repo => _ref.read(householdRepositoryProvider);

  String get _householdId {
    final id = _ref.read(activeHouseholdProvider).value?.id;
    if (id == null) throw const HouseholdFailure(HouseholdError.forbidden);
    return id;
  }

  /// Pulls the household and members from the server into the local copy. When the server
  /// says the person has no household (removed, left, deleted) the local copy is cleared.
  Future<void> refresh() async {
    final user = _user;
    final remote = await _remote.fetchMine(user.id);
    if (remote == null) {
      final mine = await _repo.watchMine(user.id).first;
      if (mine != null) await _repo.forget(mine.id);
      return;
    }
    await _repo.replaceFromRemote(remote);
  }

  /// First sign-in: create the household and make this person its owner. Anything entered
  /// before signing in moves into it.
  Future<void> createHousehold({
    required String name,
    required String displayName,
    required String currency,
  }) async {
    final user = _user;
    final id = await _remote.createHousehold(
      name: name.trim(),
      currency: currency,
      displayName: displayName.trim(),
    );
    await _repo.adoptLocalData(
      householdId: id,
      userId: user.id,
      everything: true,
    );
    await refresh();
  }

  /// Joins with an invite code (any case, with or without the dash).
  Future<void> join(String code) async {
    final user = _user;
    final id = await _remote.redeemInvite(code, displayName: user.nameOrEmail);
    await _repo.adoptLocalData(
      householdId: id,
      userId: user.id,
      everything: false,
    );
    await refresh();
  }

  Future<void> setRole(String userId, Role role) async {
    await _remote.setRole(_householdId, userId, role);
    await refresh();
  }

  Future<void> removeMember(String userId) async {
    await _remote.removeMember(_householdId, userId);
    await refresh();
  }

  /// The signed-in person leaves the household (not allowed for the owner).
  Future<void> leave() async {
    await _remote.removeMember(_householdId, _user.id);
    await refresh();
  }

  Future<CreatedInvite> createInvite(Role role) =>
      _remote.createInvite(_householdId, role);

  Future<List<PendingInvite>> invites() => _remote.listInvites(_householdId);

  Future<void> revokeInvite(String inviteId) => _remote.revokeInvite(inviteId);
}
