enum SyncPhase {
  /// Everything on this device is on the server and the other way round.
  synced,
  syncing,

  /// The server cannot be reached. Changes are kept and sent later.
  offline,

  /// The server answered with an error we could not handle. Will be retried.
  error,
}

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.synced,
    this.pending = 0,
    this.issues = 0,
    this.initial = false,
    this.pulled = 0,
    this.lastSyncedAt,
  });

  final SyncPhase phase;

  /// Local changes not on the server yet.
  final int pending;

  /// Changes the server refused and the person has not dismissed yet.
  final int issues;

  /// True while this device downloads the household for the first time.
  final bool initial;

  /// Rows downloaded so far in this run (for the first-time progress text).
  final int pulled;
  final DateTime? lastSyncedAt;

  SyncStatus copyWith({
    SyncPhase? phase,
    int? pending,
    int? issues,
    bool? initial,
    int? pulled,
    DateTime? lastSyncedAt,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    pending: pending ?? this.pending,
    issues: issues ?? this.issues,
    initial: initial ?? this.initial,
    pulled: pulled ?? this.pulled,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );

  /// Short label for the indicator.
  String get label {
    if (initial && phase == SyncPhase.syncing) {
      return pulled == 0 ? 'Getting your household' : 'Getting $pulled items';
    }
    return switch (phase) {
      SyncPhase.syncing => 'Syncing',
      SyncPhase.offline =>
        pending == 0 ? 'Offline' : 'Offline, $pending waiting',
      SyncPhase.error => 'Sync problem',
      SyncPhase.synced => 'Synced',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.pending == pending &&
      other.issues == issues &&
      other.initial == initial &&
      other.pulled == pulled &&
      other.lastSyncedAt == lastSyncedAt;

  @override
  int get hashCode =>
      Object.hash(phase, pending, issues, initial, pulled, lastSyncedAt);
}

/// Seconds to wait after the [failures]-th failure in a row: 2, 4, 8 ... up to 5 minutes.
Duration backoffDelay(int failures) {
  final n = failures < 1 ? 1 : failures;
  final seconds = 2 << (n - 1 > 8 ? 8 : n - 1);
  return Duration(seconds: seconds > 300 ? 300 : seconds);
}
