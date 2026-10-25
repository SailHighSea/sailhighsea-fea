import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/sync/sync_engine.dart';
import 'package:family_expenses/core/sync/sync_status.dart';
import 'package:family_expenses/core/sync/synced_table.dart';
import 'package:family_expenses/features/expenses/data/category_repository.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync.dart';

const _hid = 'h1';

/// One phone: its own database, clock and sync engine against the shared fake server.
class _Device {
  _Device(this.server, this.userId, {Duration skew = Duration.zero}) {
    db = AppDatabase(NativeDatabase.memory());
    clock = () => DateTime.now().add(skew);
    expenses = ExpenseRepository(db, clock: clock, householdId: _hid);
    categories = CategoryRepository(db, clock: clock, householdId: _hid);
    engine = SyncEngine(
      db: db,
      backend: server.backendFor(userId),
      householdId: _hid,
      userId: userId,
      clock: clock,
      pullOverlap: Duration.zero,
    );
  }

  final FakeSyncServer server;
  final String userId;
  late final AppDatabase db;
  late final DateTime Function() clock;
  late final ExpenseRepository expenses;
  late final CategoryRepository categories;
  late final SyncEngine engine;

  Future<String> add(int cents, {String note = '', DateTime? day}) =>
      expenses.add(
        amountCents: cents,
        categoryId: 'default-food',
        spentOn: day ?? DateTime(2026, 10, 20),
        note: note,
        createdBy: userId,
      );

  Future<List<ExpenseRow>> live() =>
      (db.select(db.expenses)..where((e) => e.deletedAt.isNull())).get();

  Future<ExpenseRow> byId(String id) =>
      (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();

  Future<void> close() async {
    engine.dispose();
    await db.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeSyncServer server;
  final devices = <_Device>[];

  _Device device(String userId, {Duration skew = Duration.zero}) {
    final d = _Device(server, userId, skew: skew);
    devices.add(d);
    return d;
  }

  setUp(() {
    server = FakeSyncServer(householdId: _hid)..seedDefaultCategories();
    server.roles.addAll({'maya': 'owner', 'ben': 'editor', 'vik': 'viewer'});
  });
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
    devices.clear();
  });

  group('push and pull', () {
    test('first sync downloads the household and reports progress', () async {
      final phone = device('maya');
      final seen = <SyncStatus>[];
      phone.engine.statuses.listen(seen.add);

      await phone.engine.syncNow();

      final cats = await phone.categories.getAll();
      expect(cats.map((c) => c.id), contains('default-food'));
      expect(cats, hasLength(6));
      expect(
        seen.any((s) => s.initial && s.phase == SyncPhase.syncing),
        isTrue,
        reason: 'the first pull is reported as an initial sync',
      );
      expect(seen.any((s) => s.pulled >= 6), isTrue);
      expect(phone.engine.status.phase, SyncPhase.synced);
      expect(phone.engine.status.initial, isFalse);
    });

    test(
      'a local expense reaches the server, clean, with server time',
      () async {
        final phone = device('maya');
        final id = await phone.add(1250, note: 'Lunch');
        await phone.engine.syncNow();

        final remote = server.row('expenses', id)!;
        expect(remote['amount_cents'], 1250);
        expect(remote['created_by'], 'maya');
        final local = await phone.byId(id);
        expect(local.dirty, isFalse);
        expect(
          local.updatedAt.toUtc().toIso8601String(),
          DateTime.parse(remote['updated_at'] as String).toIso8601String(),
          reason: 'the local copy takes the server timestamp',
        );
      },
    );

    test('categories are pushed before the expenses that use them', () async {
      final phone = device('maya');
      await phone.engine.syncNow();
      final cat = await phone.categories.add('Pets');
      await phone.expenses.add(
        amountCents: 900,
        categoryId: cat.id,
        spentOn: DateTime(2026, 10, 21),
        createdBy: 'maya',
      );
      server.pushLog.clear();
      await phone.engine.syncNow();
      expect(server.pushLog.first, startsWith('categories:'));
      expect(server.pushLog.last, startsWith('expenses:'));
    });

    test(
      'entries made before sign-in are sent as the signed-in person',
      () async {
        final phone = device('maya');
        final id = await phone.expenses.add(
          amountCents: 300,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 20),
          createdBy: 'You',
        );
        await phone.engine.syncNow();
        expect(server.row('expenses', id)!['created_by'], 'maya');
      },
    );
  });

  group('two devices', () {
    test('an edit on one device appears on the other', () async {
      final a = device('maya');
      final b = device('ben');
      await a.engine.syncNow();
      await b.engine.syncNow();

      final id = await a.add(2000, note: 'Groceries');
      await a.engine.syncNow();
      await b.engine.syncNow();

      expect((await b.byId(id)).amountCents, 2000);

      await b.expenses.update(
        id,
        amountCents: 2500,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 20),
        note: 'Groceries and milk',
      );
      await b.engine.syncNow();
      await a.engine.syncNow();
      final onA = await a.byId(id);
      expect(onA.amountCents, 2500);
      expect(onA.note, 'Groceries and milk');
    });

    test('deletes propagate as soft deletes', () async {
      final a = device('maya');
      final b = device('ben');
      final id = await a.add(700);
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(await b.live(), hasLength(1));

      await a.expenses.softDelete(id);
      await a.engine.syncNow();
      await b.engine.syncNow();

      expect(await b.live(), isEmpty);
      final row = await b.byId(id);
      expect(row.deletedAt, isNotNull, reason: 'kept as a tombstone');
      expect(server.row('expenses', id)!['deleted_at'], isNotNull);
    });

    test('undo of a delete propagates too', () async {
      final a = device('maya');
      final b = device('ben');
      final id = await a.add(700);
      await a.engine.syncNow();
      await a.expenses.softDelete(id);
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.expenses.restore(id);
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(await b.live(), hasLength(1));
    });

    test(
      'same expense edited on both: the later arrival wins, nothing breaks',
      () async {
        final a = device('maya');
        final b = device('ben');
        final id = await a.add(1000, note: 'Dinner');
        await a.engine.syncNow();
        await b.engine.syncNow();

        await a.expenses.update(
          id,
          amountCents: 1100,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 20),
          note: 'Dinner A',
        );
        await b.expenses.update(
          id,
          amountCents: 1200,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 20),
          note: 'Dinner B',
        );
        await a.engine.syncNow();
        await b.engine.syncNow(); // arrives last
        await a.engine.syncNow();

        expect(server.row('expenses', id)!['note'], 'Dinner B');
        expect((await a.byId(id)).note, 'Dinner B');
        expect((await b.byId(id)).note, 'Dinner B');
        expect((await a.byId(id)).dirty, isFalse);
      },
    );

    test('a pull never overwrites a change still waiting to be sent', () async {
      final a = device('maya');
      final b = device('ben');
      final id = await a.add(1000, note: 'Dinner');
      await a.engine.syncNow();
      await b.engine.syncNow();

      server.write('expenses', {
        'id': id,
        'household_id': _hid,
        'note': 'changed elsewhere',
        'amount_cents': 1,
      });
      // b edits offline while the server already changed.
      server.offline = true;
      await b.expenses.update(
        id,
        amountCents: 1500,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 20),
        note: 'my edit',
      );
      await b.engine.syncNow();
      expect(b.engine.status.phase, SyncPhase.offline);
      server.offline = false;
      await b.engine.syncNow();

      expect(server.row('expenses', id)!['note'], 'my edit');
      expect((await b.byId(id)).note, 'my edit');
    });

    test('a device with a wrong clock does not decide who wins', () async {
      final fast = device('maya', skew: const Duration(days: 400));
      final slow = device('ben', skew: const Duration(days: -400));
      final id = await fast.add(1000, note: 'first');
      await fast.engine.syncNow();
      await slow.engine.syncNow();

      // Both edit; the slow clock's edit reaches the server last.
      await fast.expenses.update(
        id,
        amountCents: 1000,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 20),
        note: 'from the fast clock',
      );
      await slow.expenses.update(
        id,
        amountCents: 1000,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 20),
        note: 'from the slow clock',
      );
      await fast.engine.syncNow();
      await slow.engine.syncNow();
      await fast.engine.syncNow();

      expect(server.row('expenses', id)!['note'], 'from the slow clock');
      expect((await fast.byId(id)).note, 'from the slow clock');
      final stamp = DateTime.parse(
        server.row('expenses', id)!['updated_at'] as String,
      );
      expect(stamp.year, 2026, reason: 'timestamps are the server\'s');
    });
  });

  group('offline', () {
    test('edits made offline are kept and sent after reconnect', () async {
      final phone = device('maya');
      await phone.engine.syncNow();
      server.offline = true;

      final id1 = await phone.add(100, note: 'one');
      final id2 = await phone.add(200, note: 'two');
      await phone.expenses.softDelete(id1);
      await phone.engine.syncNow();

      expect(phone.engine.status.phase, SyncPhase.offline);
      expect(phone.engine.status.pending, 2);
      expect(await phone.live(), hasLength(1), reason: 'the app keeps working');
      expect(server.row('expenses', id2), isNull);

      server.offline = false;
      await phone.engine.syncNow();

      expect(phone.engine.status.phase, SyncPhase.synced);
      expect(phone.engine.status.pending, 0);
      expect(server.row('expenses', id2)!['note'], 'two');
      expect(server.row('expenses', id1)!['deleted_at'], isNotNull);
    });

    test(
      'an edit made while a push is running is not marked as sent',
      () async {
        final phone = device('maya');
        final id = await phone.add(100, note: 'v1');
        await phone.engine.syncNow();

        // Simulate: snapshot taken, then edited before acknowledge.
        final pending = await ExpensesSync().pending(phone.db, _hid, 'maya');
        expect(pending, isEmpty);
        await phone.expenses.update(
          id,
          amountCents: 100,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 20),
          note: 'v2',
        );
        final dirty = await ExpensesSync().pending(phone.db, _hid, 'maya');
        await phone.expenses.update(
          id,
          amountCents: 100,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 20),
          note: 'v3',
        );
        await ExpensesSync().acknowledge(phone.db, dirty.single, {
          ...server.row('expenses', id)!,
          'note': 'v2',
        });
        expect((await phone.byId(id)).note, 'v3');
        expect((await phone.byId(id)).dirty, isTrue);
      },
    );

    test('backoff doubles from 2 seconds up to 5 minutes', () {
      expect(
        [for (var i = 1; i <= 10; i++) backoffDelay(i).inSeconds],
        [2, 4, 8, 16, 32, 64, 128, 256, 300, 300],
      );
    });
  });

  group('roles', () {
    test(
      'a view-only member cannot write: the server refuses and it is surfaced',
      () async {
        final phone = device('vik');
        await phone.engine.syncNow();
        final id = await phone.add(999, note: 'sneaky');
        await phone.engine.syncNow();

        expect(
          server.row('expenses', id),
          isNull,
          reason: 'server rejected it',
        );
        expect(
          await phone.live(),
          isEmpty,
          reason: 'and it is not kept locally',
        );
        final issues = await phone.db.select(phone.db.syncIssues).get();
        expect(issues.single.summary, 'sneaky, 9.99');
        expect(phone.engine.status.issues, 1);
        expect(phone.engine.status.pending, 0, reason: 'not retried forever');
      },
    );

    test('demoted while offline: queued edits are refused and the server version returns', () async {
      final phone = device('ben');
      final other = device('maya');
      final keep = await other.add(500, note: 'original');
      await other.engine.syncNow();
      await phone.engine.syncNow();

      server.offline = true;
      await phone.expenses.update(
        keep,
        amountCents: 777,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 20),
        note: 'my offline edit',
      );
      final fresh = await phone.add(123, note: 'new offline');
      await phone.engine.syncNow();
      expect(phone.engine.status.pending, 2);

      server.roles['ben'] = 'viewer'; // demoted meanwhile
      server.offline = false;
      var roleRefreshes = 0;
      final engine = SyncEngine(
        db: phone.db,
        backend: server.backendFor('ben'),
        householdId: _hid,
        userId: 'ben',
        pullOverlap: Duration.zero,
        onRoleChanged: () async => roleRefreshes++,
      );
      await engine.syncNow();
      engine.dispose();

      expect(server.row('expenses', keep)!['note'], 'original');
      final back = await phone.byId(keep);
      expect(back.note, 'original', reason: 'put back to the server version');
      expect(back.dirty, isFalse);
      expect(
        await (phone.db.select(
          phone.db.expenses,
        )..where((e) => e.id.equals(fresh))).get(),
        isEmpty,
      );
      final issues = await phone.db.select(phone.db.syncIssues).get();
      expect(
        issues.map((i) => i.summary),
        containsAll(['my offline edit, 7.77', 'new offline, 1.23']),
      );
      expect(roleRefreshes, greaterThan(0), reason: 'roles are reloaded');
      expect(engine.status.issues, 2);
    });

    test('dismissing clears the surfaced issues', () async {
      final phone = device('vik');
      await phone.engine.syncNow();
      await phone.add(5, note: 'x');
      await phone.engine.syncNow();
      expect(phone.engine.status.issues, 1);
      await phone.engine.dismissIssues();
      expect(await phone.db.select(phone.db.syncIssues).get(), isEmpty);
      expect(phone.engine.status.issues, 0);
    });

    test('a person removed from the household cannot push or read', () async {
      final phone = device('ben');
      await phone.engine.syncNow();
      server.roles.remove('ben');
      final id = await phone.add(10);
      await phone.engine.syncNow();
      expect(server.row('expenses', id), isNull);
      expect(await phone.live(), isEmpty);
      expect(phone.engine.status.issues, 1);
    });
  });

  group('live updates', () {
    test('a signal from the server pulls the other device\'s change', () async {
      final a = device('maya');
      final b = device('ben');
      await a.engine.syncNow();
      await b.engine.syncNow();
      b.engine.start();
      addTearDown(() {});

      final id = await a.add(4200, note: 'live');
      await a.engine.syncNow(); // server emits a data signal

      for (var i = 0; i < 100 && (await b.live()).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect((await b.byId(id)).amountCents, 4200);
    });

    test('a local edit is pushed on its own after the debounce', () async {
      final phone = device('maya');
      phone.engine.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final id = await phone.add(321, note: 'auto');
      for (var i = 0; i < 100 && server.row('expenses', id) == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(server.row('expenses', id)!['amount_cents'], 321);
    });
  });

  test('first pull of an empty household still finishes', () async {
    server.tables['categories']!.clear();
    final phone = device('maya');
    await phone.engine.syncNow();
    expect(phone.engine.status.phase, SyncPhase.synced);
    expect(phone.engine.status.initial, isFalse);
    // The database seeds nothing for 'h1', so there is nothing local either.
    expect(await phone.categories.getAll(), isEmpty);
    expect(
      await phone.db.select(phone.db.syncState).get(),
      hasLength(6),
      reason: 'a cursor is remembered per table',
    );
  });
}
