import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/sync/sync_engine.dart';
import 'package:family_expenses/features/bills/data/bill_repository.dart';
import 'package:family_expenses/features/bills/domain/bill_calculations.dart';
import 'package:family_expenses/features/budgets/data/budget_repository.dart';
import 'package:family_expenses/features/budgets/domain/budget_calculations.dart';
import 'package:family_expenses/features/family/data/household_repository.dart';
import 'package:family_expenses/features/goals/data/goal_repository.dart';
import 'package:family_expenses/features/goals/domain/goal_calculations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync.dart';

const _hid = 'h1';

class _Phone {
  _Phone(FakeSyncServer server, this.userId) {
    db = AppDatabase(NativeDatabase.memory());
    budgets = BudgetRepository(db, householdId: _hid);
    goals = GoalRepository(db, householdId: _hid);
    bills = BillRepository(db, householdId: _hid);
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
  late final BudgetRepository budgets;
  late final GoalRepository goals;
  late final BillRepository bills;
  late final SyncEngine engine;

  Future<List<BudgetRow>> budgetRows() => budgets.watchAll().first;
  Future<List<GoalRow>> goalRows() => goals.watchGoals().first;
  Future<List<GoalContributionRow>> contributions() =>
      goals.watchContributions().first;
  Future<List<BillRow>> billRows() => bills.watchAll().first;
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

  setUp(() {
    server = FakeSyncServer(householdId: _hid)..seedDefaultCategories();
    server.roles.addAll({
      'maya': 'owner',
      'amir': 'admin',
      'ben': 'editor',
      'vik': 'viewer',
    });
  });
  tearDown(() async {
    for (final p in phones) {
      p.engine.dispose();
      await p.db.close();
    }
    phones.clear();
  });

  group('budgets', () {
    test(
      'the same budget set on two phones is one row, last write wins',
      () async {
        final a = phone('maya');
        final b = phone('amir');
        await a.engine.syncNow();
        await b.engine.syncNow();
        await a.budgets.setBudget(DateTime(2026, 10), 'default-food', 80000);
        await b.budgets.setBudget(DateTime(2026, 10), 'default-food', 90000);
        await a.engine.syncNow();
        await b.engine.syncNow();
        await a.engine.syncNow();

        expect(server.rows('budgets'), hasLength(1));
        expect(
          server.row('budgets', 'b:2026-10:default-food')!['amount_cents'],
          90000,
        );
        expect((await a.budgetRows()).single.amountCents, 90000);
        expect((await a.budgetRows()).single.dirty, isFalse);
      },
    );

    test(
      'removing a budget reaches the other phone and later months follow',
      () async {
        final a = phone('maya');
        final b = phone('amir');
        await a.budgets.setBudget(DateTime(2026, 9), 'default-food', 80000);
        await a.engine.syncNow();
        await b.engine.syncNow();
        expect(
          effectiveBudgets(
            await b.budgetRows(),
            DateTime(2026, 10),
          )['default-food'],
          80000,
          reason: 'carries over to October',
        );

        await a.budgets.remove(DateTime(2026, 10), 'default-food');
        await a.engine.syncNow();
        await b.engine.syncNow();
        final onB = await b.budgetRows();
        expect(
          effectiveBudgets(onB, DateTime(2026, 10)).containsKey('default-food'),
          isFalse,
        );
        expect(
          effectiveBudgets(onB, DateTime(2026, 9))['default-food'],
          80000,
          reason: 'September keeps it',
        );

        await a.budgets.setBudget(DateTime(2026, 10), 'default-food', 70000);
        await a.engine.syncNow();
        await b.engine.syncNow();
        expect(
          effectiveBudgets(
            await b.budgetRows(),
            DateTime(2026, 10),
          )['default-food'],
          70000,
        );
      },
    );

    test(
      'a view-only member cannot push a budget: the server refuses and says so',
      () async {
        final v = phone('vik');
        await v.engine.syncNow();
        await v.budgets.setBudget(DateTime(2026, 10), null, 250000);
        await v.engine.syncNow();
        expect(server.rows('budgets'), isEmpty);
        expect(
          await v.budgetRows(),
          isEmpty,
          reason: 'put back to the server version',
        );
        final issues = await v.db.select(v.db.syncIssues).get();
        expect(issues.single.summary, 'Budget 2500.00');
        expect(v.engine.status.issues, 1);
      },
    );

    test(
      'an editor cannot push goals, bills or contributions either',
      () async {
        final e = phone('ben');
        await e.engine.syncNow();
        final goal = await e.goals.add(name: 'Trip', targetCents: 1000);
        await e.goals.addMoney(goal, cents: 100, addedBy: 'ben');
        await e.bills.add(
          name: 'Rent',
          amountCents: 500,
          nextDueOn: DateTime(2026, 11),
        );
        await e.engine.syncNow();
        expect(server.rows('goals'), isEmpty);
        expect(server.rows('goal_contributions'), isEmpty);
        expect(server.rows('bills'), isEmpty);
        expect(await e.db.select(e.db.syncIssues).get(), hasLength(3));
      },
    );
  });

  group('goals', () {
    test('money added on two phones at once all counts', () async {
      final a = phone('maya');
      final b = phone('amir');
      final id = await a.goals.add(
        name: 'Trip',
        targetCents: 300000,
        savedCents: 100000,
        monthlyCents: 15000,
      );
      await a.engine.syncNow();
      await b.engine.syncNow();

      await a.goals.addMoney(id, cents: 10000, addedBy: 'maya');
      await b.goals.addMoney(id, cents: 20000, addedBy: 'amir');
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.engine.syncNow();

      for (final p in [a, b]) {
        final views = buildGoalViews(
          goals: await p.goalRows(),
          contributions: await p.contributions(),
          now: DateTime(2026, 10, 23),
        );
        expect(
          views.single.savedCents,
          130000,
          reason: 'opening 1,000 + 100 + 200 on ${p.userId}',
        );
      }
      expect(server.rows('goal_contributions'), hasLength(2));
    });

    test(
      'editing and deleting a goal syncs; contributions follow the goal',
      () async {
        final a = phone('maya');
        final b = phone('amir');
        final id = await a.goals.add(name: 'Laptop', targetCents: 180000);
        await a.engine.syncNow();
        await b.engine.syncNow();
        await a.goals.update(
          id,
          name: 'New laptop',
          targetCents: 200000,
          savedCents: 0,
          monthlyCents: 10000,
        );
        await a.engine.syncNow();
        await b.engine.syncNow();
        expect((await b.goalRows()).single.name, 'New laptop');
        expect((await b.goalRows()).single.monthlyCents, 10000);

        await a.goals.softDelete(id);
        await a.engine.syncNow();
        await b.engine.syncNow();
        expect(
          buildGoalViews(
            goals: await b.goalRows(),
            contributions: const [],
            now: DateTime(2026, 10, 23),
          ),
          isEmpty,
        );
      },
    );
  });

  group('bills', () {
    test('mark paid moves the due date on the other phone; undo too', () async {
      final a = phone('maya');
      final b = phone('amir');
      final id = await a.bills.add(
        name: 'Electricity',
        amountCents: 9640,
        nextDueOn: DateTime(2026, 10, 28),
      );
      await a.engine.syncNow();
      await b.engine.syncNow();

      await a.bills.markPaid(id);
      await a.engine.syncNow();
      await b.engine.syncNow();
      final paid = (await b.billRows()).single;
      expect(paid.nextDueOn, isNot('2026-10-28'));
      expect(paid.lastPaidOn, isNotNull);

      await a.bills.setDates(id, nextDueOn: '2026-10-28', lastPaidOn: null);
      await a.engine.syncNow();
      await b.engine.syncNow();
      final undone = (await b.billRows()).single;
      expect(undone.nextDueOn, '2026-10-28');
      expect(undone.lastPaidOn, isNull);
    });

    test('bills made offline are sent when the phone is back online', () async {
      final a = phone('maya');
      await a.engine.syncNow();
      server.offline = true;
      await a.bills.add(
        name: 'Internet',
        amountCents: 4990,
        nextDueOn: DateTime(2026, 10, 30),
        repeat: BillRepeat.monthly,
      );
      await a.engine.syncNow();
      expect(a.engine.status.pending, 1);
      server.offline = false;
      await a.engine.syncNow();
      expect(a.engine.status.pending, 0);
      expect(server.rows('bills').single['next_due_on'], '2026-10-30');
      expect(server.rows('bills').single['repeat'], 'monthly');
    });
  });

  group('before sign-in', () {
    test('budgets, goals, bills and contributions come along into the new household', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final budgets = BudgetRepository(db);
      final goals = GoalRepository(db);
      final bills = BillRepository(db);
      await budgets.setBudget(DateTime(2026, 10), null, 250000);
      final goal = await goals.add(name: 'Trip', targetCents: 1000);
      await goals.addMoney(goal, cents: 100, addedBy: 'You');
      await bills.add(
        name: 'Rent',
        amountCents: 500,
        nextDueOn: DateTime(2026, 11),
      );
      await db
          .update(db.budgets)
          .write(const BudgetsCompanion(dirty: Value(false)));

      await HouseholdRepository(db)
          .adoptLocalData(householdId: 'h9', userId: 'maya', everything: true);

      final b = (await db.select(db.budgets).get()).single;
      expect(b.householdId, 'h9');
      expect(b.dirty, isTrue, reason: 'queued for the server');
      expect((await db.select(db.goals).get()).single.householdId, 'h9');
      expect((await db.select(db.bills).get()).single.householdId, 'h9');
      final c = (await db.select(db.goalContributions).get()).single;
      expect(c.householdId, 'h9');
      expect(c.addedBy, 'maya', reason: '"You" becomes the signed-in person');
    });
  });
}
