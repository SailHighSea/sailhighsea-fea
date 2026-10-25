import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../family/member_providers.dart';
import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/db/tables.dart';
import '../../core/time.dart';
import '../../core/sync/sync_backend.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/sync_status.dart';

/// `null` while Supabase is not configured. `main()` and tests override it.
final syncBackendProvider = Provider<SyncBackend?>((ref) => null);

/// Runs while a person is signed in and has a household. `null` in local-only mode and before
/// the household exists; the app then simply keeps everything on the device.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final backend = ref.watch(syncBackendProvider);
  final userId = ref.watch(currentUserIdProvider);
  final householdId = ref.watch(activeHouseholdIdProvider);
  if (backend == null || userId == null || householdId == localHouseholdId) {
    return null;
  }
  final engine = SyncEngine(
    db: ref.watch(databaseProvider),
    backend: backend,
    householdId: householdId,
    userId: userId,
    clock: ref.watch(clockProvider),
    // A refused write or a roles change: reload members so buttons match the new role.
    onRoleChanged: () => ref.read(householdControllerProvider).refresh(),
  );
  ref.onDispose(engine.dispose);
  engine.start();
  return engine;
});

/// What the sync indicator shows. `null` means there is nothing to sync (local-only).
final syncStatusProvider = StreamProvider<SyncStatus?>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return Stream.value(null);
  return engine.statuses;
});

/// Changes the server refused and the person has not dismissed yet.
final syncIssuesProvider = StreamProvider<List<SyncIssueRow>>((ref) {
  final engine = ref.watch(syncEngineProvider);
  if (engine == null) return Stream.value(const []);
  return engine.watchIssues();
});
