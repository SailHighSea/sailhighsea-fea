import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/sync/sync_engine.dart';
import 'package:family_expenses/features/budgets/data/budget_repository.dart';
import 'package:family_expenses/features/budgets/domain/budget_calculations.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/family/data/household_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync.dart';

const _hid = 'h1';

class _Phone {
  _Phone(FakeSyncServer server, this.userId) {
    db = AppDatabase(NativeDatabase.memory());
    expenses = ExpenseRepository(db, householdId: _hid);
    budgets = BudgetRepository(db, householdId: _hid);
    engine = SyncEngine(
      db: db,
      backend: server.backendFor(userId),
      householdId: _hid,
      userId: userId,
      pullOverlap: Duration.zero,
    );
  }

  final String userId;
  late final AppDatabase db;
  late final ExpenseRepository expenses;
  late final BudgetRepository budgets;
  late final SyncEngine engine;

  Future<List<String>> creators() async =>
      ((await db.select(db.expenses).get()).map((e) => e.createdBy!).toList()
        ..sort());
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeSyncServer server;
  final phones = <_Phone>[];

  _Phone phone(String user) {
    final p = _Phone(server, user);
    phones.add(p);
    return p;
  }

  void spent(String id, String by) => server.write('expenses', {
    'id': id,
    'household_id': _hid,
    'amount_cents': 100,
    'category_id': 'default-food',
    'note': '',
    'spent_on': '2026-10-05',
    'created_by': by,
    'receipt_path': null,
    'deleted_at': null,
  });

  setUp(() {
    server = FakeSyncServer(householdId: _hid)..seedDefaultCategories();
    server.roles.addAll({
      'maya': 'owner',
      'amir': 'admin',
      'ben': 'editor',
      'vik': 'viewer',
    });
    spent('e-maya', 'maya');
    spent('e-amir', 'amir');
    spent('e-ben', 'ben');
    spent('e-vik', 'vik');
  });
  tearDown(() async {
    for (final p in phones) {
      p.engine.dispose();
      await p.db.close();
    }
    phones.clear();
  });

  group('what each phone receives', () {
    test('an own-only member never receives anyone else\'s expenses', () async {
      server.ownOnly.add('ben');
      final ben = phone('ben');
      await ben.engine.syncNow();
      expect(await ben.creators(), ['ben']);
    });

    test(
      'household-visibility members, owner and admin receive everything',
      () async {
        for (final user in ['vik', 'maya', 'amir']) {
          final p = phone(user);
          await p.engine.syncNow();
          expect(await p.creators(), [
            'amir',
            'ben',
            'maya',
            'vik',
          ], reason: user);
        }
      },
    );

    test(
      'owner and admin see everything even if they were listed own-only',
      () async {
        server.ownOnly.addAll({'maya', 'amir'});
        final admin = phone('amir');
        await admin.engine.syncNow();
        expect((await admin.creators()).length, 4);
      },
    );

    test('an own-only member adds an expense, it syncs, and still only theirs arrive', () async {
      server.ownOnly.add('ben');
      final ben = phone('ben');
      await ben.engine.syncNow();
      final id = await ben.expenses.add(
        amountCents: 250,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 6),
        createdBy: 'ben',
      );
      await ben.engine.syncNow();
      expect(server.row('expenses', id), isNotNull);
      spent('later-maya', 'maya'); // someone else keeps adding
      await ben.engine.syncNow();
      expect(await ben.creators(), ['ben', 'ben']);
    });

    test('the owner sees the own-only member\'s new expense', () async {
      server.ownOnly.add('ben');
      final ben = phone('ben');
      final owner = phone('maya');
      await ben.engine.syncNow();
      await ben.expenses.add(
        amountCents: 250,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 6),
        createdBy: 'ben',
      );
      await ben.engine.syncNow();
      await owner.engine.syncNow();
      expect((await owner.creators()).where((c) => c == 'ben').length, 2);
    });

    test(
      'an own-only member\'s own writes are accepted, nothing is refused',
      () async {
        server.ownOnly.add('ben');
        final ben = phone('ben');
        await ben.engine.syncNow();
        await ben.expenses.add(
          amountCents: 1,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 6),
          createdBy: 'ben',
        );
        await ben.engine.syncNow();
        expect(ben.engine.status.issues, 0);
        expect(await ben.creators(), ['ben', 'ben']);
      },
    );
  });

  group('allowances', () {
    void allowance(String user, int cents) => server.write('budgets', {
      'id': 'b:2026-10:user:$user',
      'household_id': _hid,
      'month': '2026-10-01',
      'category_id': null,
      'user_id': user,
      'amount_cents': cents,
      'deleted_at': null,
    });

    test('a person receives their own allowance, not anyone else\'s; managers receive all', () async {
      allowance('vik', 20000);
      allowance('ben', 30000);
      server.write('budgets', {
        'id': 'b:2026-10:overall',
        'household_id': _hid,
        'month': '2026-10-01',
        'category_id': null,
        'user_id': null,
        'amount_cents': 250000,
        'deleted_at': null,
      });
      final vik = phone('vik');
      final admin = phone('amir');
      await vik.engine.syncNow();
      await admin.engine.syncNow();
      final seenByVik = await vik.budgets.watchAll().first;
      expect(effectiveAllowances(seenByVik, DateTime(2026, 10)), {
        'vik': 20000,
      });
      expect(effectiveBudgets(seenByVik, DateTime(2026, 10)), {null: 250000});
      expect(
        effectiveAllowances(
          await admin.budgets.watchAll().first,
          DateTime(2026, 10),
        ),
        {'vik': 20000, 'ben': 30000},
      );
    });

    test(
      'the owner sets an allowance on one phone and it reaches the member',
      () async {
        final owner = phone('maya');
        final vik = phone('vik');
        await owner.engine.syncNow();
        await owner.budgets.setAllowance(DateTime(2026, 10), 'vik', 15000);
        await owner.engine.syncNow();
        await vik.engine.syncNow();
        expect(
          effectiveAllowances(
            await vik.budgets.watchAll().first,
            DateTime(2026, 10),
          ),
          {'vik': 15000},
        );
        expect(server.row('budgets', 'b:2026-10:user:vik')!['user_id'], 'vik');

        await owner.budgets.removeAllowance(DateTime(2026, 10), 'vik');
        await owner.engine.syncNow();
        await vik.engine.syncNow();
        expect(
          effectiveAllowances(
            await vik.budgets.watchAll().first,
            DateTime(2026, 10),
          ),
          isEmpty,
        );
      },
    );

    test('a member cannot set an allowance: the server refuses', () async {
      final vik = phone('vik');
      await vik.engine.syncNow();
      await vik.budgets.setAllowance(DateTime(2026, 10), 'vik', 999999);
      await vik.engine.syncNow();
      expect(server.rows('budgets'), isEmpty);
      expect(vik.engine.status.issues, 1);
    });
  });

  group('switching a member to own only', () {
    test('what was pulled before is removed from the device', () async {
      final ben = phone('ben');
      await ben.engine.syncNow();
      expect(await ben.creators(), ['amir', 'ben', 'maya', 'vik']);

      server.ownOnly.add('ben');
      await HouseholdRepository(ben.db)
          .purgeOthersExpenses(householdId: _hid, userId: 'ben');
      expect(await ben.creators(), ['ben']);

      await ben.engine.syncNow();
      expect(await ben.creators(), [
        'ben',
      ], reason: 'and they do not come back');
    });

    test(
      'the member\'s own entries, including ones made before sign-in, are kept',
      () async {
        final ben = phone('ben');
        await ben.engine.syncNow();
        await ben.expenses.add(
          amountCents: 5,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 7),
          createdBy: 'You',
        );
        await HouseholdRepository(ben.db)
            .purgeOthersExpenses(householdId: _hid, userId: 'ben');
        final left = (await ben.db.select(ben.db.expenses).get())
            .map((e) => e.createdBy)
            .toSet();
        expect(left, {'ben', 'You'});
      },
    );

    test('other households are not touched', () async {
      final ben = phone('ben');
      await ben.engine.syncNow();
      await ben.db
          .into(ben.db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: 'other',
              householdId: const Value('elsewhere'),
              amountCents: 1,
              categoryId: 'default-food',
              spentOn: '2026-10-01',
              createdBy: const Value('stranger'),
              updatedAt: DateTime(2026),
            ),
          );
      await HouseholdRepository(ben.db)
          .purgeOthersExpenses(householdId: _hid, userId: 'ben');
      expect(
        (await ben.db.select(ben.db.expenses).get()).any(
          (e) => e.id == 'other',
        ),
        isTrue,
      );
    });
  });

  test(
    'a version 4 database upgrades to 5 and keeps its members and budgets',
    () async {
      final dir = Directory.systemTemp.createTempSync('migration5');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/app.db');

      var db = AppDatabase(NativeDatabase(file));
      await db.select(db.categories).get();
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              householdId: 'h',
              userId: 'u',
              role: 'viewer',
              displayName: 'Vik',
              joinedAt: DateTime(2026),
            ),
          );
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              id: 'b:2026-10:overall',
              month: '2026-10-01',
              amountCents: 250000,
              updatedAt: DateTime(2026),
            ),
          );
      await db.close();

      // Reopen it as Phase 5 shipped it: no visibility or user_id column, user_version 4.
      db = AppDatabase(
        NativeDatabase(
          file,
          setup: (raw) => raw
            ..execute('ALTER TABLE members DROP COLUMN visibility')
            ..execute('ALTER TABLE budgets DROP COLUMN user_id')
            ..execute('PRAGMA user_version = 4'),
        ),
      );
      addTearDown(db.close);
      final member = (await db.select(db.members).get()).single;
      expect(member.displayName, 'Vik');
      expect(
        member.visibility,
        'household',
        reason: 'nothing changes for existing members',
      );
      final budget = (await db.select(db.budgets).get()).single;
      expect(budget.userId, isNull);
    },
  );
}
