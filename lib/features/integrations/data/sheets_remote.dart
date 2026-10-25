enum SheetState {
  /// No Sheet linked.
  notConnected,

  /// Linked; the first copy of all expenses is still running.
  copying,
  active,

  /// The last run failed. It is retried by itself.
  error,

  /// Google no longer accepts the saved permission. The owner has to connect again.
  revoked,
}

class SheetStatus {
  const SheetStatus({
    this.state = SheetState.notConnected,
    this.spreadsheetUrl,
    this.lastSyncedAt,
    this.lastError,
    this.backfillTotal = 0,
    this.pending = 0,
  });

  const SheetStatus.none() : this();

  final SheetState state;

  /// Only owner and admins get these two from the server.
  final String? spreadsheetUrl;
  final String? lastError;

  final DateTime? lastSyncedAt;

  /// Expenses the first copy had to send, and how many are still waiting.
  final int backfillTotal;
  final int pending;

  bool get isConnected => state != SheetState.notConnected;

  /// 0..1 while the first copy runs; null when there is nothing to show.
  double? get progress {
    if (state != SheetState.copying || backfillTotal <= 0) return null;
    final done = (backfillTotal - pending).clamp(0, backfillTotal);
    return done / backfillTotal;
  }

  int get copied => (backfillTotal - pending).clamp(0, backfillTotal);
}

enum SheetsError { forbidden, rateLimited, offline, unknown }

class SheetsFailure implements Exception {
  const SheetsFailure(this.error, [this.detail]);

  final SheetsError error;
  final String? detail;

  String get message => switch (error) {
    SheetsError.forbidden => 'Only the owner can do that.',
    SheetsError.rateLimited => 'Too many tries. Wait a few minutes.',
    SheetsError.offline => 'No connection. Check your internet and try again.',
    SheetsError.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => message;
}

/// Everything the Google Sheet card needs from the server. The Google token never reaches
/// the app: connecting opens Google's consent page in a browser, and the server finishes the
/// exchange.
abstract class SheetsRemote {
  Future<SheetStatus> fetchStatus(String householdId);

  /// Google's consent page for the owner. The app opens it in a browser.
  Future<Uri> startConnect(String householdId);

  /// Writes the queue to the Sheet now instead of waiting. Owner and admins.
  Future<void> syncNow(String householdId);

  /// Revokes the token at Google and forgets the link. The Sheet stays in the owner's Drive.
  Future<void> disconnect(String householdId);
}
