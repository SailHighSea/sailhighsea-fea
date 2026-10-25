import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/google/google_api.dart';
import '../../core/google/google_auth.dart';
import '../../core/sheets_sync/sheets_settings.dart';
import '../../core/sheets_sync/sheets_sync.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/time.dart';
import '../bills/bill_providers.dart';
import '../budgets/budget_providers.dart';
import '../goals/goal_providers.dart';
import 'pairing_service.dart';
import 'suggestion_service.dart';

/// The name used for this person in sheets and codes.
final sheetsMyNameProvider = Provider<String>((ref) {
  final saved = ref.watch(sheetsSettingsProvider).displayName.trim();
  if (saved.isNotEmpty) return saved;
  final a = ref.watch(googleAccountProvider).value;
  if (a == null) return '';
  final n = a.name?.trim();
  return (n != null && n.isNotEmpty) ? n : a.email.split('@').first;
});

final pairingServiceProvider = Provider<PairingService?>((ref) {
  final sheets = ref.watch(sheetsApiProvider);
  final drive = ref.watch(driveApiProvider);
  final account = ref.watch(googleAccountProvider).value;
  if (!ref.watch(isSheetsModeProvider) ||
      sheets == null ||
      drive == null ||
      account == null) {
    return null;
  }
  final controller = ref.read(sheetsSettingsProvider.notifier);
  return PairingService(
    db: ref.watch(databaseProvider),
    sheets: sheets,
    drive: drive,
    settings: () => ref.read(sheetsSettingsProvider),
    updateSettings: controller.update,
    myEmail: () => account.email,
    myName: () => ref.read(sheetsMyNameProvider),
    currencyCode: ref.watch(appearanceProvider).currencyCode,
    clock: ref.watch(clockProvider),
  );
});

final suggestionServiceProvider = Provider<SuggestionService>(
  (ref) => SuggestionService(
    ref.watch(databaseProvider),
    budgets: ref.watch(budgetRepositoryProvider),
    goals: ref.watch(goalRepositoryProvider),
    bills: ref.watch(billRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final sheetPairsProvider = StreamProvider<List<SheetPairRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.sheetPairs,
  )..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
});

final suggestionsListProvider = StreamProvider<List<SuggestionRow>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.suggestions,
  )..orderBy([(s) => OrderingTerm.desc(s.createdAt)])).watch();
});

final pendingSuggestionCountProvider = Provider<int>(
  (ref) => (ref.watch(suggestionsListProvider).value ?? const [])
      .where((s) => s.status == 'pending')
      .length,
);

class SheetsSyncState {
  const SheetsSyncState({
    this.syncing = false,
    this.lastSyncedAt,
    this.report,
    this.needsReconnect = false,
    this.error,
  });

  final bool syncing;
  final DateTime? lastSyncedAt;
  final SheetsSyncReport? report;

  /// Google access was removed or expired: show "Reconnect".
  final bool needsReconnect;

  /// A message safe to show ("Offline", "Google is busy").
  final String? error;
}

class SheetsSyncController extends Notifier<SheetsSyncState> {
  @override
  SheetsSyncState build() => const SheetsSyncState();

  SheetsSyncCoordinator? _coordinator() {
    final sheets = ref.read(sheetsApiProvider);
    final account = ref.read(googleAccountProvider).value;
    if (!ref.read(isSheetsModeProvider) || sheets == null || account == null) {
      return null;
    }
    return SheetsSyncCoordinator(
      db: ref.read(databaseProvider),
      sheets: sheets,
      settings: () => ref.read(sheetsSettingsProvider),
      updateSettings: ref.read(sheetsSettingsProvider.notifier).update,
      myEmail: () => account.email,
      myName: () => ref.read(sheetsMyNameProvider),
      currencyCode: ref.read(appearanceProvider).currencyCode,
      clock: ref.read(clockProvider),
    );
  }

  /// One round now. Never throws: problems become [SheetsSyncState.error] or `needsReconnect`.
  Future<void> syncNow({bool force = false}) async {
    if (state.syncing) return;
    final c = _coordinator();
    if (c == null) return;
    state = SheetsSyncState(
      syncing: true,
      lastSyncedAt: state.lastSyncedAt,
      report: state.report,
    );
    try {
      final report = await c.syncOnce(force: force);
      if (!ref.mounted) return;
      state = SheetsSyncState(
        lastSyncedAt: ref.read(clockProvider)(),
        report: report,
      );
    } on GoogleAuthRevoked {
      if (ref.mounted) {
        state = SheetsSyncState(
          lastSyncedAt: state.lastSyncedAt,
          needsReconnect: true,
        );
      }
    } on GoogleApiError {
      if (ref.mounted) {
        state = SheetsSyncState(
          lastSyncedAt: state.lastSyncedAt,
          error: 'Google is busy. Will try again.',
        );
      }
    } on Object {
      // Offline or a hiccup: the local data is untouched and the next round retries.
      if (ref.mounted) {
        state = SheetsSyncState(
          lastSyncedAt: state.lastSyncedAt,
          error: 'Offline. Will try again.',
        );
      }
    }
  }
}

final sheetsSyncProvider =
    NotifierProvider<SheetsSyncController, SheetsSyncState>(
      SheetsSyncController.new,
    );

/// How often the app syncs while it is open. `null` (tests) means never on its own.
final sheetsSyncIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(minutes: 5),
);

/// Keeps syncing for as long as the app runs in Sheets mode: on start, when the account or role
/// changes, and every few minutes.
final sheetsAutoSyncProvider = Provider<void>((ref) {
  if (!ref.watch(isSheetsModeProvider)) return;
  final account = ref.watch(googleAccountProvider).value;
  final role = ref.watch(sheetsSettingsProvider.select((s) => s.role));
  if (account == null || role == null) return;
  final interval = ref.watch(sheetsSyncIntervalProvider);
  if (interval == null) return;
  final controller = ref.read(sheetsSyncProvider.notifier);
  Future.microtask(controller.syncNow);
  final timer = Timer.periodic(interval, (_) => controller.syncNow());
  ref.onDispose(timer.cancel);
});
