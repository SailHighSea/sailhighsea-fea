import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../domain/role.dart';
import '../domain/visibility.dart';
import 'household_remote.dart';

class SupabaseHouseholdRemote implements HouseholdRemote {
  SupabaseHouseholdRemote(this._client);

  final sb.SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on HouseholdFailure {
      rethrow;
    } on sb.FunctionException catch (e) {
      throw HouseholdFailure(_fromFunction(e));
    } on sb.PostgrestException catch (e) {
      // 42501 is "insufficient privilege": Row Level Security or a missing grant said no.
      if (e.code == '42501') {
        throw const HouseholdFailure(HouseholdError.forbidden);
      }
      if (e.code == '23505') {
        throw const HouseholdFailure(HouseholdError.alreadyMember);
      }
      throw HouseholdFailure(HouseholdError.unknown, e.message);
    } catch (e) {
      throw HouseholdFailure(HouseholdError.offline, e.toString());
    }
  }

  HouseholdError _fromFunction(sb.FunctionException e) {
    final details = e.details;
    final code = details is Map ? details['error'] : null;
    return switch (code) {
      'forbidden' => HouseholdError.forbidden,
      'rate_limited' => HouseholdError.rateLimited,
      'invalid_code' => HouseholdError.invalidCode,
      'already_member' => HouseholdError.alreadyMember,
      _ =>
        e.status == 429 ? HouseholdError.rateLimited : HouseholdError.unknown,
    };
  }

  @override
  Future<RemoteHousehold?> fetchMine(String userId) => _guard(() async {
    final mine = await _client
        .from('members')
        .select('household_id')
        .eq('user_id', userId)
        .maybeSingle();
    if (mine == null) return null;
    final id = mine['household_id'] as String;
    final household = await _client
        .from('households')
        .select('id, name, currency, owner_id')
        .eq('id', id)
        .single();
    final members = await _client
        .from('members')
        .select('user_id, role, display_name, joined_at, visibility')
        .eq('household_id', id)
        .order('joined_at');
    return RemoteHousehold(
      id: id,
      name: household['name'] as String,
      currency: household['currency'] as String,
      ownerId: household['owner_id'] as String,
      members: [
        for (final m in members)
          RemoteMember(
            userId: m['user_id'] as String,
            role: Role.fromDb(m['role'] as String),
            displayName: m['display_name'] as String,
            joinedAt: DateTime.parse(m['joined_at'] as String),
            visibility: MemberVisibility.fromDb(m['visibility'] as String?),
          ),
      ],
    );
  });

  @override
  Future<String> createHousehold({
    required String name,
    required String currency,
    required String displayName,
  }) => _guard(() async {
    final id = await _client.rpc<dynamic>(
      'create_household',
      params: {
        'p_name': name,
        'p_currency': currency,
        'p_display_name': displayName,
      },
    );
    return id as String;
  });

  @override
  Future<void> setRole(String householdId, String userId, Role role) =>
      _guard(() async {
        final rows = await _client
            .from('members')
            .update({'role': role.dbValue})
            .eq('household_id', householdId)
            .eq('user_id', userId)
            .select('user_id');
        // Row Level Security hides rows the role may not touch, so an empty answer means no.
        if (rows.isEmpty) {
          throw const HouseholdFailure(HouseholdError.forbidden);
        }
      });

  @override
  Future<void> setVisibility(
    String householdId,
    String userId,
    MemberVisibility visibility,
  ) => _guard(() async {
    final rows = await _client
        .from('members')
        .update({'visibility': visibility.dbValue})
        .eq('household_id', householdId)
        .eq('user_id', userId)
        .select('user_id');
    if (rows.isEmpty) {
      throw const HouseholdFailure(HouseholdError.forbidden);
    }
  });

  @override
  Future<void> removeMember(String householdId, String userId) =>
      _guard(() async {
        final rows = await _client
            .from('members')
            .delete()
            .eq('household_id', householdId)
            .eq('user_id', userId)
            .select('user_id');
        if (rows.isEmpty) {
          throw const HouseholdFailure(HouseholdError.forbidden);
        }
      });

  @override
  Future<CreatedInvite> createInvite(String householdId, Role role) =>
      _guard(() async {
        final response = await _client.functions.invoke(
          'create-invite',
          body: {'household_id': householdId, 'role': role.dbValue},
        );
        final data = response.data as Map<String, dynamic>;
        return CreatedInvite(
          code: data['code'] as String,
          role: Role.fromDb(data['role'] as String),
          expiresAt: DateTime.parse(data['expires_at'] as String),
        );
      });

  @override
  Future<List<PendingInvite>> listInvites(String householdId) =>
      _guard(() async {
        final rows = await _client
            .from('invites')
            .select('id, role, created_at, expires_at')
            .eq('household_id', householdId)
            .isFilter('used_at', null)
            .gt('expires_at', DateTime.now().toUtc().toIso8601String())
            .order('created_at', ascending: false);
        return [
          for (final r in rows)
            PendingInvite(
              id: r['id'] as String,
              role: Role.fromDb(r['role'] as String),
              createdAt: DateTime.parse(r['created_at'] as String),
              expiresAt: DateTime.parse(r['expires_at'] as String),
            ),
        ];
      });

  @override
  Future<void> revokeInvite(String inviteId) => _guard(() async {
    final rows = await _client
        .from('invites')
        .delete()
        .eq('id', inviteId)
        .select('id');
    if (rows.isEmpty) throw const HouseholdFailure(HouseholdError.forbidden);
  });

  @override
  Future<String> redeemInvite(String code, {String? displayName}) => _guard(
    () async {
      final response = await _client.functions.invoke(
        'redeem-invite',
        body: {'code': code, 'display_name': ?displayName},
      );
      return (response.data as Map<String, dynamic>)['household_id'] as String;
    },
  );
}
