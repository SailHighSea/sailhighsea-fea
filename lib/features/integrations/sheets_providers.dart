import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../family/member_providers.dart';
import 'data/sheets_remote.dart';

/// `null` while Supabase is not configured. `main()` and tests override it.
final sheetsRemoteProvider = Provider<SheetsRemote?>((ref) => null);

/// Opens a link in the person's browser. Tests replace it.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// True from the moment the owner is sent to Google until the server reports the connection
/// (or they give up). While true the status is checked every few seconds.
class SheetConnecting extends Notifier<bool> {
  DateTime? _since;

  @override
  bool build() => false;

  void begin() {
    _since = DateTime.now();
    state = true;
  }

  void cancel() {
    _since = null;
    state = false;
  }

  /// Gives up waiting after five minutes (checked on each status poll, so no timer).
  void expireIfOld() {
    final since = _since;
    if (state &&
        since != null &&
        DateTime.now().difference(since) > const Duration(minutes: 5)) {
      cancel();
    }
  }
}

final sheetConnectingProvider = NotifierProvider<SheetConnecting, bool>(
  SheetConnecting.new,
);

/// How often the status is read: quickly while something is happening, slowly otherwise.
Duration sheetPollInterval(SheetStatus status, {required bool connecting}) {
  if (connecting || status.state == SheetState.copying) {
    return const Duration(seconds: 3);
  }
  return const Duration(seconds: 20);
}

/// Live status of the Google Sheet connection for the active household. Failures (offline)
/// keep the last known status.
final sheetStatusProvider = StreamProvider<SheetStatus>((ref) async* {
  final remote = ref.watch(sheetsRemoteProvider);
  final household = ref.watch(activeHouseholdProvider).value;
  if (remote == null || household == null) {
    yield const SheetStatus.none();
    return;
  }
  var alive = true;
  ref.onDispose(() => alive = false);
  var last = const SheetStatus.none();
  while (alive) {
    try {
      last = await remote.fetchStatus(household.id);
      if (last.isConnected && ref.read(sheetConnectingProvider)) {
        ref.read(sheetConnectingProvider.notifier).cancel();
      }
    } on SheetsFailure {
      // Offline or a hiccup: keep showing what we knew.
    }
    if (!alive) break;
    ref.read(sheetConnectingProvider.notifier).expireIfOld();
    yield last;
    final wait = sheetPollInterval(
      last,
      connecting: ref.read(sheetConnectingProvider),
    );
    await Future<void>.delayed(wait);
  }
});

/// Actions behind the card's buttons.
class SheetActions {
  SheetActions(this._ref);

  final Ref _ref;

  SheetsRemote get _remote {
    final remote = _ref.read(sheetsRemoteProvider);
    if (remote == null) throw const SheetsFailure(SheetsError.offline);
    return remote;
  }

  String get _householdId {
    final id = _ref.read(activeHouseholdProvider).value?.id;
    if (id == null) throw const SheetsFailure(SheetsError.forbidden);
    return id;
  }

  /// Sends the owner to Google. The server finishes the connection when they agree.
  Future<void> connect() async {
    final url = await _remote.startConnect(_householdId);
    final opened = await _ref.read(urlOpenerProvider)(url);
    if (!opened) throw const SheetsFailure(SheetsError.unknown);
    _ref.read(sheetConnectingProvider.notifier).begin();
  }

  Future<void> syncNow() async {
    await _remote.syncNow(_householdId);
    _ref.invalidate(sheetStatusProvider);
  }

  Future<void> disconnect() async {
    await _remote.disconnect(_householdId);
    _ref.read(sheetConnectingProvider.notifier).cancel();
    _ref.invalidate(sheetStatusProvider);
  }

  Future<void> open(String url) async {
    await _ref.read(urlOpenerProvider)(Uri.parse(url));
  }
}

final sheetActionsProvider = Provider<SheetActions>(SheetActions.new);
