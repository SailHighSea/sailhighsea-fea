import 'dart:async';

import 'package:family_expenses/features/auth/auth_service.dart';
import 'package:family_expenses/features/family/data/household_remote.dart';
import 'package:family_expenses/features/family/domain/role.dart';
import 'package:family_expenses/features/family/domain/visibility.dart';

/// Stands in for Supabase Auth in widget tests.
class FakeAuthService implements AuthService {
  FakeAuthService({AuthUser? user}) {
    _user = user;
  }

  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();

  /// Accounts that can sign in: email to password.
  final Map<String, String> accounts = {'maya@example.com': 'secret-pass-1'};
  final List<String> calls = [];

  /// Set to make the next call fail with this message.
  String? failNextWith;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get changes async* {
    yield _user;
    yield* _controller.stream;
  }

  void _setUser(AuthUser? user) {
    _user = user;
    _controller.add(user);
  }

  void _maybeFail() {
    final message = failNextWith;
    if (message != null) {
      failNextWith = null;
      throw AuthFailure(message);
    }
  }

  AuthUser _userFor(String email) =>
      AuthUser(id: 'user-${email.split('@').first}', email: email);

  @override
  Future<void> signInWithPassword(String email, String password) async {
    calls.add('password:$email');
    _maybeFail();
    if (accounts[email.trim()] != password) {
      throw const AuthFailure('That email and password do not match.');
    }
    _setUser(_userFor(email.trim()));
  }

  @override
  Future<bool> signUpWithPassword(String email, String password) async {
    calls.add('signup:$email');
    _maybeFail();
    accounts[email.trim()] = password;
    _setUser(_userFor(email.trim()));
    return true;
  }

  @override
  Future<void> sendEmailCode(String email) async {
    calls.add('send-code:$email');
    _maybeFail();
  }

  @override
  Future<void> verifyEmailCode(String email, String code) async {
    calls.add('verify:$email:$code');
    _maybeFail();
    if (code != '123456') {
      throw const AuthFailure('That code is wrong or has expired.');
    }
    _setUser(_userFor(email.trim()));
  }

  @override
  Future<void> signInWithOAuth(OAuthProviderKind provider) async {
    calls.add('oauth:${provider.name}');
    _maybeFail();
    _setUser(const AuthUser(id: 'user-oauth', email: 'oauth@example.com'));
  }

  @override
  Future<void> signOut() async {
    calls.add('sign-out');
    _setUser(null);
  }
}

/// An in-memory "server" for widget tests. It applies the same role rules as the SQL
/// policies in `supabase/migrations` (the real thing is covered by `supabase/tests`), so a
/// call the UI should not make is rejected with [HouseholdError.forbidden].
class FakeHouseholdRemote implements HouseholdRemote {
  FakeHouseholdRemote({this.actingUserId = 'user-maya', this.household});

  /// The person making the calls (what the server reads from the JWT).
  String actingUserId;

  final List<String> calls = [];

  /// Make [fetchMine] fail as if offline, so the screens keep showing their cached copy.
  bool offline = false;
  final Map<String, Role> _codes = {};
  final List<PendingInvite> _pending = [];
  int _counter = 0;

  /// Codes the fake will hand out, in order.
  final List<String> nextCodes = ['K7M4QX9X', 'P3R8WZ2N', 'B5D6FH7J'];

  DateTime Function() clock = DateTime.now;

  RemoteHousehold? household;

  Role? _roleOf(String userId) {
    for (final m in household?.members ?? const <RemoteMember>[]) {
      if (m.userId == userId) return m.role;
    }
    return null;
  }

  bool get _actorIsManager {
    final role = _roleOf(actingUserId);
    return role == Role.owner || role == Role.admin;
  }

  void _replaceMember(
    String userId,
    Role role, {
    MemberVisibility? visibility,
  }) {
    final h = household!;
    household = RemoteHousehold(
      id: h.id,
      name: h.name,
      currency: h.currency,
      ownerId: h.ownerId,
      members: [
        for (final m in h.members)
          if (m.userId == userId)
            RemoteMember(
              userId: m.userId,
              role: role,
              displayName: m.displayName,
              joinedAt: m.joinedAt,
              visibility: visibility ?? m.visibility,
            )
          else
            m,
      ],
    );
  }

  @override
  Future<RemoteHousehold?> fetchMine(String userId) async {
    calls.add('fetch:$userId');
    if (offline) throw const HouseholdFailure(HouseholdError.offline);
    return _roleOf(userId) == null ? null : household;
  }

  @override
  Future<String> createHousehold({
    required String name,
    required String currency,
    required String displayName,
  }) async {
    calls.add('create:$name:$displayName:$currency');
    if (_roleOf(actingUserId) != null) {
      throw const HouseholdFailure(HouseholdError.alreadyMember);
    }
    household = RemoteHousehold(
      id: 'household-1',
      name: name,
      currency: currency,
      ownerId: actingUserId,
      members: [
        RemoteMember(
          userId: actingUserId,
          role: Role.owner,
          displayName: displayName,
          joinedAt: DateTime(2026, 10, 12),
        ),
      ],
    );
    return 'household-1';
  }

  @override
  Future<void> setRole(String householdId, String userId, Role role) async {
    calls.add('set-role:$userId:${role.dbValue}');
    final target = _roleOf(userId);
    final allowed =
        _actorIsManager &&
        target != null &&
        target != Role.owner &&
        userId != actingUserId &&
        Role.assignable.contains(role);
    if (!allowed) throw const HouseholdFailure(HouseholdError.forbidden);
    _replaceMember(userId, role);
  }

  @override
  Future<void> setVisibility(
    String householdId,
    String userId,
    MemberVisibility visibility,
  ) async {
    calls.add('set-visibility:$userId:${visibility.dbValue}');
    final target = _roleOf(userId);
    final allowed =
        _actorIsManager &&
        userId != actingUserId &&
        (target == Role.editor || target == Role.viewer);
    if (!allowed) throw const HouseholdFailure(HouseholdError.forbidden);
    _replaceMember(userId, target!, visibility: visibility);
  }

  @override
  Future<void> removeMember(String householdId, String userId) async {
    calls.add('remove:$userId');
    final target = _roleOf(userId);
    final self = userId == actingUserId;
    final allowed =
        target != null &&
        target != Role.owner &&
        ((self) || (_actorIsManager && !self));
    if (!allowed) throw const HouseholdFailure(HouseholdError.forbidden);
    final h = household!;
    household = RemoteHousehold(
      id: h.id,
      name: h.name,
      currency: h.currency,
      ownerId: h.ownerId,
      members: [
        for (final m in h.members)
          if (m.userId != userId) m,
      ],
    );
  }

  @override
  Future<CreatedInvite> createInvite(String householdId, Role role) async {
    calls.add('create-invite:${role.dbValue}');
    if (!_actorIsManager || !Role.invitable.contains(role)) {
      throw const HouseholdFailure(HouseholdError.forbidden);
    }
    final code = nextCodes[_counter++ % nextCodes.length];
    _codes[code] = role;
    final now = clock();
    _pending.insert(
      0,
      PendingInvite(
        id: 'invite-$_counter',
        role: role,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
      ),
    );
    return CreatedInvite(
      code: code,
      role: role,
      expiresAt: now.add(const Duration(hours: 24)),
    );
  }

  @override
  Future<List<PendingInvite>> listInvites(String householdId) async {
    calls.add('list-invites');
    if (!_actorIsManager) return const [];
    return List.of(_pending);
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    calls.add('revoke:$inviteId');
    if (!_actorIsManager) {
      throw const HouseholdFailure(HouseholdError.forbidden);
    }
    _pending.removeWhere((p) => p.id == inviteId);
  }

  /// Joins [userId] with a code, as the edge function would.
  @override
  Future<String> redeemInvite(String code, {String? displayName}) async {
    calls.add('redeem:$code');
    if (_roleOf(actingUserId) != null) {
      throw const HouseholdFailure(HouseholdError.alreadyMember);
    }
    final role = _codes.remove(code);
    if (role == null || household == null) {
      throw const HouseholdFailure(HouseholdError.invalidCode);
    }
    final h = household!;
    household = RemoteHousehold(
      id: h.id,
      name: h.name,
      currency: h.currency,
      ownerId: h.ownerId,
      members: [
        ...h.members,
        RemoteMember(
          userId: actingUserId,
          role: role,
          displayName: displayName ?? 'Member',
          joinedAt: DateTime(2026, 10, 24),
        ),
      ],
    );
    return h.id;
  }
}

/// The household from the Family mockup: You (owner), Maya (admin), Sam (view only).
RemoteHousehold sampleHousehold({
  String ownerId = 'user-you',
  List<RemoteMember>? extra,

  /// User ids set to "only their own" spending (editors and viewers only).
  Set<String> ownOnly = const {},
}) {
  MemberVisibility visibilityOf(String id) =>
      ownOnly.contains(id) ? MemberVisibility.own : MemberVisibility.household;
  return RemoteHousehold(
    id: 'household-1',
    name: 'Our household',
    currency: 'SGD',
    ownerId: ownerId,
    members: [
      RemoteMember(
        userId: ownerId,
        role: Role.owner,
        displayName: 'You',
        joinedAt: DateTime(2026, 9, 1),
      ),
      RemoteMember(
        userId: 'user-maya',
        role: Role.admin,
        displayName: 'Maya',
        joinedAt: DateTime(2026, 10, 12),
      ),
      RemoteMember(
        userId: 'user-sam',
        role: Role.viewer,
        displayName: 'Sam',
        joinedAt: DateTime(2026, 10, 15),
        visibility: visibilityOf('user-sam'),
      ),
      RemoteMember(
        userId: 'user-ed',
        role: Role.editor,
        displayName: 'Ed',
        joinedAt: DateTime(2026, 10, 16),
        visibility: visibilityOf('user-ed'),
      ),
      ...?extra,
    ],
  );
}
