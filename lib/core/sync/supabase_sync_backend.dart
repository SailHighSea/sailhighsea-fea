import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'sync_backend.dart';

/// Talks to Supabase. Row Level Security on the server decides what each role may write;
/// this class only turns "insufficient privilege" into [SyncRejectedException] and network
/// trouble into [SyncOfflineException].
class SupabaseSyncBackend implements SyncBackend {
  SupabaseSyncBackend(this._client);

  final sb.SupabaseClient _client;

  /// Columns a client may change on an existing row (see the grants in the migrations).
  static const _updatable = {
    'categories': ['name', 'color', 'icon', 'sort', 'deleted_at'],
    'expenses': [
      'amount_cents',
      'category_id',
      'note',
      'spent_on',
      'receipt_path',
      'deleted_at',
    ],
    'budgets': ['month', 'category_id', 'amount_cents', 'deleted_at'],
    'goals': [
      'name',
      'target_cents',
      'saved_cents',
      'monthly_cents',
      'due_on',
      'deleted_at',
    ],
    'goal_contributions': ['amount_cents', 'contributed_on', 'deleted_at'],
    'bills': [
      'name',
      'amount_cents',
      'due_day',
      'repeat',
      'next_due_on',
      'last_paid_on',
      'deleted_at',
    ],
  };

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on sb.PostgrestException catch (e) {
      // 42501: Row Level Security or a missing grant said no.
      if (e.code == '42501') throw SyncRejectedException(e.message);
      // Anything else is a server answer we cannot fix by waiting; surface it as an error.
      throw StateError('${e.code}: ${e.message}');
    } on sb.AuthException catch (e) {
      throw SyncOfflineException(e.message);
    } on Exception catch (e) {
      throw SyncOfflineException(e.toString());
    }
  }

  @override
  Future<List<RemoteRow>> pull(
    String table,
    String householdId, {
    String? since,
    required int limit,
  }) => _guard(() async {
    var query = _client.from(table).select().eq('household_id', householdId);
    if (since != null) query = query.gte('updated_at', since);
    final rows = await query.order('updated_at', ascending: true).limit(limit);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  });

  @override
  Future<RemoteRow?> fetchOne(String table, String householdId, String id) =>
      _guard(() async {
        final row = await _client
            .from(table)
            .select()
            .eq('household_id', householdId)
            .eq('id', id)
            .maybeSingle();
        return row == null ? null : Map<String, dynamic>.from(row);
      });

  @override
  Future<RemoteRow> push(String table, RemoteRow row) => _guard(() async {
    final changes = {
      for (final column in _updatable[table]!) column: row[column],
    };
    // Update first: an existing row may belong to someone else (an editor edits a family
    // member's expense), and the insert policy only allows your own `created_by`.
    final updated = await _client
        .from(table)
        .update(changes)
        .eq('household_id', row['household_id'] as String)
        .eq('id', row['id'] as String)
        .select();
    if (updated.isNotEmpty) return Map<String, dynamic>.from(updated.first);
    // Nothing matched: either the row is new or the role may not update it. An insert tells
    // the two apart (a viewer is refused with 42501).
    final inserted = await _client.from(table).insert(row).select().single();
    return Map<String, dynamic>.from(inserted);
  });

  @override
  Stream<SyncSignal> signals(String householdId) {
    late final StreamController<SyncSignal> controller;
    sb.RealtimeChannel? channel;
    controller = StreamController<SyncSignal>(
      onListen: () {
        final c = _client.channel('household-$householdId');
        for (final table in const [
          'expenses',
          'categories',
          'budgets',
          'goals',
          'goal_contributions',
          'bills',
          'members',
        ]) {
          c.onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            filter: sb.PostgresChangeFilter(
              type: sb.PostgresChangeFilterType.eq,
              column: 'household_id',
              value: householdId,
            ),
            callback: (_) => controller.add(
              table == 'members' ? SyncSignal.membership : SyncSignal.data,
            ),
          );
        }
        c.subscribe((status, error) {
          // Catch up on whatever was missed while the channel was down.
          if (status == sb.RealtimeSubscribeStatus.subscribed) {
            controller.add(SyncSignal.data);
          }
        });
        channel = c;
      },
      onCancel: () async {
        final c = channel;
        if (c != null) await _client.removeChannel(c);
      },
    );
    return controller.stream;
  }
}
