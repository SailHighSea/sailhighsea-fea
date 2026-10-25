import 'dart:async';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'sync_backend.dart';
import 'sync_status.dart';
import 'synced_table.dart';

/// Keeps one household's local database and the server in step (rule 5: local first).
///
/// * The UI only ever reads and writes Drift. Writes mark rows `dirty`.
/// * A sync run pushes dirty rows (categories first, then expenses), then pulls everything
///   that changed since the saved cursor.
/// * Time is the server's: it stamps `updated_at` on every write, so a wrong device clock
///   cannot win a conflict. Last write wins by the order writes reach the server. A local
///   change that is still waiting is never overwritten by a pull; it is pushed next.
/// * Failures to reach the server back off (2, 4, 8 ... 300 seconds) and the queue stays
///   put. A write the server refuses because of the role is taken out of the queue, the row
///   goes back to the server's version, and a [SyncIssues] row says what was lost.
class SyncEngine {
  SyncEngine({
    required this._db,
    required this._backend,
    required this.householdId,
    required this.userId,
    List<SyncedTable>? tables,
    this.pageSize = 500,
    this.pullOverlap = const Duration(seconds: 5),
    this.debounce = const Duration(milliseconds: 300),
    this.refreshEvery = const Duration(minutes: 1),
    DateTime Function()? clock,
    this.onRoleChanged,
  }) : _clock = clock ?? DateTime.now {
    this.tables = tables ?? buildSyncedTables();
  }

  final AppDatabase _db;
  final SyncBackend _backend;
  final DateTime Function() _clock;
  final String householdId;
  final String userId;
  late final List<SyncedTable> tables;
  final int pageSize;

  /// Pulls start this far before the cursor, so rows whose transaction committed late are
  /// not missed. Applying a row twice is harmless.
  final Duration pullOverlap;
  final Duration debounce;

  /// Safety net while everything is quiet: pull again this often even without a signal.
  final Duration refreshEvery;

  /// Called when the server refused a write or reported a membership change, so the app can
  /// reload the member list and the role the screens use.
  final Future<void> Function()? onRoleChanged;

  final _controller = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus();
  StreamSubscription<SyncSignal>? _signals;
  StreamSubscription<Set<TableUpdate>>? _localChanges;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  Timer? _refreshTimer;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;
  int _failures = 0;

  SyncStatus get status => _status;

  /// The current status, then every change.
  Stream<SyncStatus> get statuses async* {
    yield _status;
    yield* _controller.stream;
  }

  /// Starts live updates and runs a first sync.
  void start() {
    _signals = _backend
        .signals(householdId)
        .listen(
          (signal) {
            if (signal == SyncSignal.membership) _notifyRoleChanged();
            _schedule();
          },
          onError: (Object _) {
            // The live channel dropped. The retry and refresh timers keep things moving.
          },
        );
    _localChanges = _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            for (final t in tables) ...t.watched(_db),
          ]),
        )
        .listen((_) => _onLocalChange());
    _refreshTimer = Timer.periodic(refreshEvery, (_) => _schedule());
    unawaited(syncNow());
  }

  Future<void> _onLocalChange() async {
    if (_disposed) return;
    final pending = await _pendingCount();
    if (pending > 0 && !_disposed) {
      // Keep the indicator honest right away, then push soon.
      _emit(_status.copyWith(pending: pending));
      _schedule();
    }
  }

  void _schedule() {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
  }

  /// Pushes and pulls now. Calls that arrive during a run are folded into one more run.
  Future<void> syncNow() async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _retryTimer?.cancel();
    try {
      do {
        _again = false;
        await _runOnce();
      } while (_again && !_disposed);
    } finally {
      _running = false;
    }
  }

  Future<void> _runOnce() async {
    final firstTime = await _isFirstPull();
    _emit(
      _status.copyWith(
        phase: SyncPhase.syncing,
        initial: firstTime,
        pulled: 0,
        pending: await _pendingCount(),
      ),
    );
    try {
      await _push();
      await _pull();
      _failures = 0;
      _emit(
        _status.copyWith(
          phase: SyncPhase.synced,
          initial: false,
          pending: await _pendingCount(),
          issues: await _issueCount(),
          lastSyncedAt: _clock(),
        ),
      );
    } on SyncOfflineException {
      await _failed(SyncPhase.offline);
    } on Object {
      await _failed(SyncPhase.error);
    }
  }

  Future<void> _failed(SyncPhase phase) async {
    _failures++;
    _emit(
      _status.copyWith(
        phase: phase,
        initial: false,
        pending: await _pendingCount(),
        issues: await _issueCount(),
      ),
    );
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(backoffDelay(_failures), () => unawaited(syncNow()));
  }

  // ---------------------------------------------------------------- push

  Future<void> _push() async {
    var refused = false;
    for (final table in tables) {
      final changes = await table.pending(_db, householdId, userId);
      for (final change in changes) {
        try {
          final stored = await _backend.push(table.name, change.json);
          await table.acknowledge(_db, change, stored);
        } on SyncRejectedException {
          refused = true;
          await _refuse(table, change);
        }
      }
    }
    if (refused) _notifyRoleChanged();
  }

  /// The server said no: remember what was lost, then put the row back to what the server
  /// has (or remove it when the server never had it).
  Future<void> _refuse(SyncedTable table, PendingChange change) async {
    await _db
        .into(_db.syncIssues)
        .insert(
          SyncIssuesCompanion.insert(
            householdId: householdId,
            syncTable: table.name,
            rowId: change.id,
            summary: change.summary,
            createdAt: _clock(),
          ),
        );
    RemoteRow? server;
    try {
      server = await _backend.fetchOne(table.name, householdId, change.id);
    } on SyncOfflineException {
      // Cannot tell; stop retrying the refused write but fix the row on the next pull.
      server = null;
      await table.markClean(_db, change);
      return;
    }
    if (server == null) {
      await table.discard(_db, change);
    } else {
      await table.applyRemote(_db, [server], force: true);
    }
  }

  // ---------------------------------------------------------------- pull

  String _cursorKey(SyncedTable table) => 'cursor:$householdId:${table.name}';

  Future<String?> _cursor(SyncedTable table) async {
    final row = await (_db.select(
      _db.syncState,
    )..where((s) => s.key.equals(_cursorKey(table)))).getSingleOrNull();
    return row?.value;
  }

  Future<bool> _isFirstPull() async {
    for (final table in tables) {
      if (await _cursor(table) == null) return true;
    }
    return false;
  }

  Future<void> _pull() async {
    for (final table in tables) {
      var cursor = await _cursor(table);
      while (true) {
        final since = cursor == null
            ? null
            : DateTime.parse(cursor)
                  .subtract(pullOverlap)
                  .toUtc()
                  .toIso8601String();
        final rows = await _backend.pull(
          table.name,
          householdId,
          since: since,
          limit: pageSize,
        );
        await table.applyRemote(_db, rows);
        final newest = _newest(rows);
        final moved =
            newest != null &&
            (cursor == null ||
                DateTime.parse(newest).isAfter(DateTime.parse(cursor)));
        if (moved) {
          cursor = newest;
          await _db
              .into(_db.syncState)
              .insertOnConflictUpdate(
                SyncStateCompanion.insert(
                  key: _cursorKey(table),
                  value: newest,
                ),
              );
        } else if (cursor == null) {
          // An empty household: remember that the first pull is done.
          cursor = _clock().toUtc().toIso8601String();
          await _db
              .into(_db.syncState)
              .insertOnConflictUpdate(
                SyncStateCompanion.insert(
                  key: _cursorKey(table),
                  value: cursor,
                ),
              );
        }
        _emit(_status.copyWith(pulled: _status.pulled + rows.length));
        // A short page is the last one. A full page that did not move the cursor would
        // repeat forever, so stop (the next run continues).
        if (rows.length < pageSize || !moved) break;
      }
    }
  }

  String? _newest(List<RemoteRow> rows) {
    String? best;
    DateTime? bestTime;
    for (final r in rows) {
      final text = r['updated_at'] as String?;
      if (text == null) continue;
      final time = DateTime.parse(text);
      if (bestTime == null || time.isAfter(bestTime)) {
        best = text;
        bestTime = time;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------- helpers

  Future<int> _pendingCount() async {
    var total = 0;
    for (final table in tables) {
      total += await table.pendingCount(_db, householdId);
    }
    return total;
  }

  Future<int> _issueCount() async {
    final count = _db.syncIssues.id.count();
    final query = _db.selectOnly(_db.syncIssues)
      ..addColumns([count])
      ..where(_db.syncIssues.householdId.equals(householdId));
    return (await query.getSingle()).read(count) ?? 0;
  }

  /// Changes the server refused and the person has not dismissed.
  Stream<List<SyncIssueRow>> watchIssues() =>
      (_db.select(_db.syncIssues)
            ..where((i) => i.householdId.equals(householdId))
            ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]))
          .watch();

  Future<void> dismissIssues() async {
    await (_db.delete(
      _db.syncIssues,
    )..where((i) => i.householdId.equals(householdId))).go();
    _emit(_status.copyWith(issues: 0));
  }

  void _notifyRoleChanged() {
    final callback = onRoleChanged;
    if (callback != null) unawaited(callback().catchError((Object _) {}));
  }

  void _emit(SyncStatus next) {
    if (_disposed || next == _status) return;
    _status = next;
    _controller.add(next);
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _refreshTimer?.cancel();
    unawaited(_signals?.cancel());
    unawaited(_localChanges?.cancel());
    unawaited(_controller.close());
  }
}
