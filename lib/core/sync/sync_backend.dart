/// A row as the server sends and receives it (column name to JSON value).
typedef RemoteRow = Map<String, dynamic>;

/// The server cannot be reached (no network, timeout, server down). Nothing is lost: the
/// change stays queued locally and is tried again.
class SyncOfflineException implements Exception {
  const SyncOfflineException([this.detail]);

  final String? detail;

  @override
  String toString() => 'Offline${detail == null ? '' : ': $detail'}';
}

/// The server refused a write because of the person's role (Row Level Security). Retrying
/// will not help; the change is dropped from the queue and shown to the person.
class SyncRejectedException implements Exception {
  const SyncRejectedException([this.detail]);

  final String? detail;

  @override
  String toString() => 'Rejected${detail == null ? '' : ': $detail'}';
}

/// Why the engine woke up on its own.
enum SyncSignal {
  /// Someone changed expenses or categories in this household.
  data,

  /// The household's members or their roles changed.
  membership,
}

/// Everything the sync engine needs from a server. [SupabaseSyncBackend] is the real one;
/// tests use an in-memory fake with the same rules (server stamps `updated_at`).
abstract class SyncBackend {
  /// Rows of [table] in [householdId] with `updated_at >= since` (all rows when `null`),
  /// oldest first, at most [limit]. Deleted rows are included so deletes propagate.
  Future<List<RemoteRow>> pull(
    String table,
    String householdId, {
    String? since,
    required int limit,
  });

  /// One row, or `null` when the server has none (or the person may not see it).
  Future<RemoteRow?> fetchOne(String table, String householdId, String id);

  /// Writes [row] (update if it exists, insert if not) and returns the stored row with the
  /// server's `updated_at`. Throws [SyncRejectedException] when the role does not allow it
  /// and [SyncOfflineException] when the server cannot be reached.
  Future<RemoteRow> push(String table, RemoteRow row);

  /// Live notifications for [householdId]. Only a hint to pull; the data comes from [pull].
  Stream<SyncSignal> signals(String householdId);
}
