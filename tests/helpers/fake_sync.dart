import 'dart:async';

import 'package:family_expenses/core/sync/sync_backend.dart';

/// An in-memory server with the rules the real one has: it stamps `updated_at` itself (a
/// clock that only moves forward, whatever the devices think), stamps soft deletes, and
/// refuses writes from viewers.
class FakeSyncServer {
  FakeSyncServer({this.householdId = 'h1'});

  final String householdId;

  /// Table name to id to row.
  final Map<String, Map<String, RemoteRow>> tables = {
    'categories': {},
    'expenses': {},
    'budgets': {},
    'goals': {},
    'goal_contributions': {},
    'bills': {},
  };

  /// Role per user id: `owner`, `admin`, `editor`, `viewer`. A user not listed has left.
  final Map<String, String> roles = {};

  /// Members who see only their own spending (owner and admin are never listed).
  final Set<String> ownOnly = {};

  /// When true every call fails like a dead network.
  bool offline = false;

  /// Everything pushed, in order, as `table:id`.
  final List<String> pushLog = [];
  int pullCalls = 0;

  // Starts at the real time: a device that pulls an empty household remembers its own clock
  // as the cursor, so a server clock in the past would hide every later row.
  DateTime _clock = DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
    isUtc: true,
  );
  final _signals = StreamController<SyncSignal>.broadcast();

  String _stamp() {
    _clock = _clock.add(const Duration(seconds: 1));
    return _clock.toIso8601String();
  }

  /// The six defaults, as `create_household` seeds them.
  void seedDefaultCategories() {
    const defaults = [
      ('default-food', 'Food', 'food'),
      ('default-bills', 'Bills', 'bills'),
      ('default-transport', 'Transport', 'transport'),
      ('default-fun', 'Fun', 'fun'),
      ('default-health', 'Health', 'health'),
      ('default-other', 'Other', 'other'),
    ];
    for (var i = 0; i < defaults.length; i++) {
      tables['categories']![defaults[i].$1] = {
        'id': defaults[i].$1,
        'household_id': householdId,
        'name': defaults[i].$2,
        'color': defaults[i].$3,
        'icon': null,
        'sort': i,
        'updated_at': _stamp(),
        'deleted_at': null,
      };
    }
  }

  List<RemoteRow> rows(String table) => [...tables[table]!.values];

  RemoteRow? row(String table, String id) => tables[table]![id];

  void emit(SyncSignal signal) => _signals.add(signal);

  /// Changes made by someone else (another device) straight on the server.
  void write(String table, RemoteRow row) {
    final id = row['id'] as String;
    final existing = tables[table]![id];
    final stamp = _stamp();
    final deletedAt = row['deleted_at'] == null
        ? null
        : (existing?['deleted_at'] ?? stamp);
    tables[table]![id] = {
      ...?existing,
      ...row,
      'updated_at': stamp,
      'deleted_at': deletedAt,
    };
    _signals.add(SyncSignal.data);
  }

  SyncBackend backendFor(String userId) => _FakeBackend(this, userId);
}

class _FakeBackend implements SyncBackend {
  _FakeBackend(this._server, this._userId);

  final FakeSyncServer _server;
  final String _userId;

  void _checkOnline() {
    if (_server.offline) throw const SyncOfflineException('no network');
  }

  String? get _role => _server.roles[_userId];

  /// Expenses: owner, admin, editor. Everything else (categories, budgets, goals, bills):
  /// owner and admin, like the Row Level Security policies.
  bool _canWrite(String table) => table == 'expenses'
      ? const {'owner', 'admin', 'editor'}.contains(_role)
      : const {'owner', 'admin'}.contains(_role);

  /// The select policies: an own-only member sees only the expenses they added, and a
  /// person's allowance (a budget with `user_id`) is visible to that person and to managers.
  bool _canSee(String table, RemoteRow row) {
    if (_role == null) return false;
    final manager = const {'owner', 'admin'}.contains(_role);
    if (table == 'expenses' && !manager && _server.ownOnly.contains(_userId)) {
      return row['created_by'] == _userId;
    }
    if (table == 'budgets' && !manager && row['user_id'] != null) {
      return row['user_id'] == _userId;
    }
    return true;
  }

  @override
  Future<List<RemoteRow>> pull(
    String table,
    String householdId, {
    String? since,
    required int limit,
  }) async {
    _checkOnline();
    _server.pullCalls++;
    if (_role == null) return const [];
    final from = since == null ? null : DateTime.parse(since);
    final rows =
        _server
            .rows(table)
            .where(
              (r) =>
                  _canSee(table, r) &&
                  (from == null ||
                      !DateTime.parse(r['updated_at'] as String)
                          .isBefore(from)),
            )
            .toList()
          ..sort(
            (a, b) =>
                DateTime.parse(a['updated_at'] as String)
                    .compareTo(DateTime.parse(b['updated_at'] as String)),
          );
    return rows.take(limit).map((r) => {...r}).toList();
  }

  @override
  Future<RemoteRow?> fetchOne(
    String table,
    String householdId,
    String id,
  ) async {
    _checkOnline();
    if (_role == null) return null;
    final r = _server.row(table, id);
    return r == null || !_canSee(table, r) ? null : {...r};
  }

  @override
  Future<RemoteRow> push(String table, RemoteRow row) async {
    _checkOnline();
    if (!_canWrite(table)) throw const SyncRejectedException('42501');
    final id = row['id'] as String;
    if (table == 'expenses' && _server.row(table, id) == null) {
      if (row['created_by'] != _userId) {
        throw const SyncRejectedException('created_by must be you');
      }
    }
    _server.pushLog.add('$table:$id');
    _server.write(table, row);
    return {..._server.row(table, id)!};
  }

  @override
  Stream<SyncSignal> signals(String householdId) => _server._signals.stream;
}
