import 'dart:async';

import 'package:family_expenses/core/google/google_api.dart';
import 'package:family_expenses/core/google/google_auth.dart';

/// In-memory Google: spreadsheets with owners and read-only sharing, shared by every fake account
/// in a test, so two phones can really exchange data through "Drive".
class FakeGoogleWorld {
  final sheets = <String, FakeSheet>{};
  int _next = 1;
  int writeCalls = 0;
  int readCalls = 0;
  final calls = <String>[];

  /// Make the next calls fail with this HTTP status (after the retries a real client would do).
  final failures = <int>[];

  FakeGoogle account(String email, {String? name, bool signedIn = true}) =>
      FakeGoogle(this, email, name, signedIn);
}

class FakeSheet {
  FakeSheet(this.owner, this.title, List<String> tabs) {
    for (final t in tabs) {
      tabs_[t] = [];
    }
  }
  final String owner;
  final String title;
  final readers = <String>{};
  final tabs_ = <String, List<List<String>>>{};
}

class FakeGoogle implements SheetsApi, DriveApi, GoogleAuthService {
  FakeGoogle(this.world, this.email, [this.name, this.signedIn = true]);

  final FakeGoogleWorld world;
  final String email;
  final String? name;
  bool revoked = false;
  final _changes = StreamController<GoogleAccount?>.broadcast();
  bool signedIn;

  // ---- GoogleAuthService ----
  @override
  GoogleAccount? get account =>
      signedIn ? GoogleAccount(email: email, name: name) : null;
  @override
  Stream<GoogleAccount?> get changes async* {
    yield account;
    yield* _changes.stream;
  }

  @override
  Future<void> signIn() async {
    signedIn = true;
    revoked = false;
    _changes.add(account);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    _changes.add(null);
  }

  @override
  Future<String> accessToken() async {
    if (revoked) {
      signedIn = false;
      _changes.add(null);
      throw const GoogleAuthRevoked();
    }
    return 'fake-token-for-$email';
  }

  // ---- helpers ----
  Future<void> _gate(String call) async {
    await accessToken();
    world.calls.add(call);
    if (world.failures.isNotEmpty) {
      final code = world.failures.removeAt(0);
      if (code == 401) throw const GoogleAuthRevoked();
      if (code == 403 || code == 404) throw SheetAccessError(code);
      throw GoogleApiError(code, 'injected');
    }
  }

  FakeSheet _readable(String id) {
    final s = world.sheets[id];
    if (s == null) throw const SheetAccessError(404);
    if (s.owner != email && !s.readers.contains(email)) {
      throw const SheetAccessError(403);
    }
    return s;
  }

  FakeSheet _writable(String id) {
    final s = world.sheets[id];
    if (s == null) throw const SheetAccessError(404);
    if (s.owner != email) throw const SheetAccessError(403);
    return s;
  }

  static final _re = RegExp(
    r'^([^!]+)(?:!([A-Z]+)(\d+)?(?::([A-Z]+)(\d+)?)?)?$',
  );
  int _col(String c) => c.codeUnitAt(0) - 65;

  // ---- SheetsApi ----
  @override
  Future<String> createSpreadsheet(String title, List<String> tabs) async {
    await _gate('create');
    final id = 'sheet-${world._next++}';
    world.sheets[id] = FakeSheet(email, title, tabs);
    return id;
  }

  @override
  Future<void> addTab(String sheetId, String tab) async {
    await _gate('addTab');
    _writable(sheetId).tabs_.putIfAbsent(tab, () => []);
  }

  @override
  Future<void> writeRanges(
    String sheetId,
    Map<String, List<List<String>>> data,
  ) async {
    await _gate('write');
    world.writeCalls++;
    final s = _writable(sheetId);
    for (final e in data.entries) {
      final m = _re.firstMatch(e.key)!;
      final grid = s.tabs_[m[1]!] ?? (throw StateError('no tab ${m[1]}'));
      final r0 = (int.parse(m[3] ?? '1')) - 1;
      final c0 = _col(m[2] ?? 'A');
      for (var i = 0; i < e.value.length; i++) {
        while (grid.length <= r0 + i) {
          grid.add([]);
        }
        final row = grid[r0 + i];
        for (var j = 0; j < e.value[i].length; j++) {
          while (row.length <= c0 + j) {
            row.add('');
          }
          row[c0 + j] = e.value[i][j];
        }
      }
    }
  }

  @override
  Future<void> appendRows(
    String sheetId,
    String tab,
    List<List<String>> rows,
  ) async {
    await _gate('append');
    world.writeCalls++;
    final s = _writable(sheetId);
    final grid = s.tabs_[tab] ?? (throw StateError('no tab $tab'));
    // After the last non-empty row.
    while (grid.isNotEmpty && grid.last.every((c) => c.isEmpty)) {
      grid.removeLast();
    }
    grid.addAll([
      for (final r in rows) [...r],
    ]);
  }

  @override
  Future<void> clear(String sheetId, String range) async {
    await _gate('clear');
    final s = _writable(sheetId);
    final m = _re.firstMatch(range)!;
    final grid = s.tabs_[m[1]!] ?? (throw StateError('no tab ${m[1]}'));
    final r0 = int.parse(m[3] ?? '1') - 1;
    final r1 = m[5] == null ? grid.length - 1 : int.parse(m[5]!) - 1;
    final c0 = _col(m[2] ?? 'A');
    final c1 = m[4] == null ? 1000 : _col(m[4]!);
    for (var r = r0; r <= r1 && r < grid.length; r++) {
      for (var c = c0; c <= c1 && c < grid[r].length; c++) {
        grid[r][c] = '';
      }
    }
  }

  @override
  Future<List<List<String>>> read(String sheetId, String range) async {
    await _gate('read');
    world.readCalls++;
    final s = _readable(sheetId);
    final m = _re.firstMatch(range)!;
    final grid = s.tabs_[m[1]!] ?? (throw StateError('no tab ${m[1]}'));
    final r0 = int.parse(m[3] ?? '1') - 1;
    final r1 = m[5] == null ? grid.length - 1 : int.parse(m[5]!) - 1;
    final c0 = _col(m[2] ?? 'A');
    final c1 = m[4] == null ? 100000 : _col(m[4]!);
    final out = <List<String>>[];
    for (var r = r0; r <= r1 && r < grid.length; r++) {
      final row = grid[r];
      final cells = <String>[
        for (var c = c0; c <= c1 && c < row.length; c++) row[c],
      ];
      while (cells.isNotEmpty && cells.last.isEmpty) {
        cells.removeLast();
      }
      out.add(cells);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out;
  }

  // ---- DriveApi ----
  @override
  Future<void> shareReadOnly(String fileId, String email) async {
    await _gate('share');
    _writable(fileId).readers.add(email);
  }

  @override
  Future<void> unshare(String fileId, String email) async {
    await _gate('unshare');
    _writable(fileId).readers.remove(email);
  }
}
