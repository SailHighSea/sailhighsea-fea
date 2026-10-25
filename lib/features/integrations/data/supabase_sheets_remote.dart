import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'sheets_remote.dart';

class SupabaseSheetsRemote implements SheetsRemote {
  SupabaseSheetsRemote(this._client);

  final sb.SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on SheetsFailure {
      rethrow;
    } on sb.FunctionException catch (e) {
      if (e.status == 403) throw const SheetsFailure(SheetsError.forbidden);
      if (e.status == 429) throw const SheetsFailure(SheetsError.rateLimited);
      throw const SheetsFailure(SheetsError.unknown);
    } on sb.PostgrestException catch (e) {
      if (e.code == '42501') throw const SheetsFailure(SheetsError.forbidden);
      throw SheetsFailure(SheetsError.unknown, e.message);
    } catch (e) {
      throw SheetsFailure(SheetsError.offline, e.toString());
    }
  }

  @override
  Future<SheetStatus> fetchStatus(String householdId) => _guard(() async {
    // The view hides the token reference and, for non-managers, the link and error text.
    final row = await _client
        .from('sheet_status')
        .select()
        .eq('household_id', householdId)
        .maybeSingle();
    if (row == null) return const SheetStatus.none();
    return SheetStatus(
      state: switch (row['status'] as String) {
        'pending' => SheetState.copying,
        'active' => SheetState.active,
        'error' => SheetState.error,
        'revoked' => SheetState.revoked,
        _ => SheetState.error,
      },
      spreadsheetUrl: row['spreadsheet_url'] as String?,
      lastError: row['last_error'] as String?,
      lastSyncedAt: row['last_synced_at'] == null
          ? null
          : DateTime.parse(row['last_synced_at'] as String).toLocal(),
      backfillTotal: row['backfill_total'] as int? ?? 0,
      pending: row['pending'] as int? ?? 0,
    );
  });

  @override
  Future<Uri> startConnect(String householdId) => _guard(() async {
    final response = await _client.functions.invoke(
      'sheets-connect',
      body: {'action': 'start', 'household_id': householdId},
    );
    final url = (response.data as Map<String, dynamic>)['url'] as String;
    return Uri.parse(url);
  });

  @override
  Future<void> syncNow(String householdId) => _guard(() async {
    await _client.functions.invoke(
      'sheets-sync',
      body: {'household_id': householdId},
    );
  });

  @override
  Future<void> disconnect(String householdId) => _guard(() async {
    await _client.functions.invoke(
      'sheets-connect',
      body: {'action': 'disconnect', 'household_id': householdId},
    );
  });
}
