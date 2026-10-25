import '../domain/role.dart';
import '../domain/visibility.dart';

class RemoteMember {
  const RemoteMember({
    required this.userId,
    required this.role,
    required this.displayName,
    required this.joinedAt,
    this.visibility = MemberVisibility.household,
  });

  final String userId;
  final Role role;
  final String displayName;
  final DateTime joinedAt;
  final MemberVisibility visibility;
}

class RemoteHousehold {
  const RemoteHousehold({
    required this.id,
    required this.name,
    required this.currency,
    required this.ownerId,
    required this.members,
  });

  final String id;
  final String name;
  final String currency;
  final String ownerId;
  final List<RemoteMember> members;
}

/// A code that has been created and not used yet. The code itself is never stored on the
/// server (only a hash), so it is not part of this list.
class PendingInvite {
  const PendingInvite({
    required this.id,
    required this.role,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final Role role;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// A freshly created code: shown once, then only the hash remains on the server.
class CreatedInvite {
  const CreatedInvite({
    required this.code,
    required this.role,
    required this.expiresAt,
  });

  /// 8 characters without separators.
  final String code;
  final Role role;
  final DateTime expiresAt;

  /// "K7M4-QX9X": two groups of four.
  String get display => '${code.substring(0, 4)}-${code.substring(4)}';
}

enum HouseholdError {
  /// The server said no (the role does not allow it).
  forbidden,
  rateLimited,
  invalidCode,
  alreadyMember,
  offline,
  unknown,
}

class HouseholdFailure implements Exception {
  const HouseholdFailure(this.error, [this.detail]);

  final HouseholdError error;
  final String? detail;

  String get message => switch (error) {
    HouseholdError.forbidden => 'Your role does not allow that.',
    HouseholdError.rateLimited =>
      'Too many tries. Wait a few minutes and try again.',
    HouseholdError.invalidCode => 'That code did not work. It may have expired or been used. Ask for a new one.',
    HouseholdError.alreadyMember =>
      'You are already in a household. Leave it first to join another.',
    HouseholdError.offline =>
      'No connection. Check your internet and try again.',
    HouseholdError.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => message;
}

/// Everything the Family screens need from the server. Every call is checked by Row Level
/// Security on the server; a call the role may not make fails with
/// [HouseholdError.forbidden].
abstract class HouseholdRemote {
  /// The household [userId] belongs to, with its members, or `null` before they have one.
  Future<RemoteHousehold?> fetchMine(String userId);

  /// Creates a household owned by the signed-in user and returns its id.
  Future<String> createHousehold({
    required String name,
    required String currency,
    required String displayName,
  });

  Future<void> setRole(String householdId, String userId, Role role);

  /// Chooses whether [userId] sees everyone's spending or only their own. Owner and admin
  /// only, never for themselves; the server refuses anything else.
  Future<void> setVisibility(
    String householdId,
    String userId,
    MemberVisibility visibility,
  );

  /// Removes a member, or lets the signed-in person leave.
  Future<void> removeMember(String householdId, String userId);

  Future<CreatedInvite> createInvite(String householdId, Role role);

  Future<List<PendingInvite>> listInvites(String householdId);

  Future<void> revokeInvite(String inviteId);

  /// Joins with a code and returns the new household id.
  Future<String> redeemInvite(String code, {String? displayName});
}
