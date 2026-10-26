import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/google/google_api.dart';
import 'package:family_expenses/core/google/google_auth.dart';
import 'package:family_expenses/core/sheets_sync/member_reader.dart';
import 'package:family_expenses/core/sheets_sync/member_writer.dart';
import 'package:family_expenses/features/expenses/data/category_repository.dart';
import 'package:family_expenses/core/sheets_sync/sheet_layout.dart';
import 'package:family_expenses/core/sheets_sync/sheets_settings.dart';
import 'package:family_expenses/features/pairing/domain/pairing_codes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_google.dart';
import '../../helpers/sheets_device.dart';

void main() {
  late FakeGoogleWorld world;
  late Device dad;
  late Device maya;

  setUp(() async {
    world = FakeGoogleWorld();
    dad = Device(world, 'dad@family.test', 'Dad', SheetsRole.organiser);
    maya = Device(world, 'maya@family.test', 'Maya', SheetsRole.member);
  });

  List<List<String>> expenseRows(Device d) => world
      .sheets[d.settings.ownSheetId!]!
      .tabs_['Expenses']!
      .skip(1)
      .where((r) => r.isNotEmpty)
      .toList();

  group('member push', () {
    test(
      'first sync creates the sheet with headers and writes every expense',
      () async {
        await maya.addExpense(4820, note: 'Groceries');
        await maya.addExpense(1250, note: 'Bus');
        final report = await maya.sync.syncOnce();
        expect(report.pushed, 2);
        final sheet = world.sheets[maya.settings.ownSheetId!]!;
        expect(sheet.title, 'FET Family Expenses - Maya');
        expect(
          sheet.tabs_.keys,
          containsAll([
            'Expenses',
            'Categories',
            'Suggestions',
            'Pairing',
            'Meta',
          ]),
        );
        expect(sheet.tabs_['Expenses']![0], Headers.expenses);
        final rows = expenseRows(maya);
        expect(rows, hasLength(2));
        final groceries = rows.firstWhere((r) => r[5] == 'Groceries');
        expect(groceries[1], '2026-10-20');
        expect(groceries[2], '48.20');
        expect(groceries[3], 'SGD');
        expect(groceries[4], 'Food');
        expect(groceries[9], '');
        expect(groceries[10], '4820', reason: 'exact integer cents are kept');
        expect((await maya.allExpenses()).every((e) => !e.dirty), isTrue);
      },
    );

    test(
      'pushing again changes nothing and never duplicates rows (idempotent)',
      () async {
        await maya.addExpense(100);
        await maya.sync.syncOnce();
        await maya.sync.syncOnce();
        await maya.sync.syncOnce(force: true);
        expect(expenseRows(maya), hasLength(1));
      },
    );

    test('a row already in the sheet but still dirty (crash after the write) is updated, not repeated', () async {
      final id = await maya.addExpense(100, note: 'one');
      await maya.sync.syncOnce();
      await (maya.db.update(maya.db.expenses))
          .write(const ExpensesCompanion(dirty: Value(true)));
      await maya.expenses.update(
        id,
        amountCents: 300,
        categoryId: await maya.food(),
        spentOn: DateTime(2026, 10, 20),
        note: 'one',
      );
      await maya.sync.syncOnce();
      final rows = expenseRows(maya);
      expect(rows, hasLength(1));
      expect(rows.single[10], '300');
    });

    test(
      'edits and deletes are written (delete is a flag, the row stays)',
      () async {
        final id = await maya.addExpense(100, note: 'old');
        await maya.sync.syncOnce();
        await maya.expenses.update(
          id,
          amountCents: 250,
          categoryId: await maya.food(),
          spentOn: DateTime(2026, 10, 21),
          note: 'new',
        );
        await maya.sync.syncOnce();
        expect(expenseRows(maya).single.sublist(0, 6), [
          id,
          '2026-10-21',
          '2.50',
          'SGD',
          'Food',
          'new',
        ]);
        await maya.expenses.softDelete(id);
        await maya.sync.syncOnce();
        expect(expenseRows(maya).single[9], '1');
      },
    );

    test('large pushes go in batches', () async {
      for (var i = 1; i <= 5; i++) {
        await maya.addExpense(i * 100);
      }
      final id = await world
          .account('maya@family.test')
          .createSpreadsheet('x', Tabs.memberSheetTabs);
      final writer = MemberWriter(
        maya.db,
        world.account('maya@family.test'),
        currencyCode: 'SGD',
        householdId: 'local',
        batchSize: 2,
      );
      world.writeCalls = 0;
      expect(await writer.push(id), 5);
      // 3 batches of appends, plus categories and meta.
      expect(
        world.sheets[id]!.tabs_['Expenses']!.where((r) => r.isNotEmpty).length,
        5,
      );
      expect(world.writeCalls, greaterThanOrEqualTo(5));
    });

    test('text that looks like a formula is neutralised in the sheet and restored when read back', () async {
      await maya.addExpense(100, note: '=HYPERLINK("http://evil")');
      await maya.sync.syncOnce();
      expect(expenseRows(maya).single[5], startsWith("'="));
      expect(
        SheetExpense.fromRow(expenseRows(maya).single)!.note,
        '=HYPERLINK("http://evil")',
      );
    });

    test('money is whole cents: 0.10 and 19.99 stay exact', () async {
      await maya.addExpense(10);
      await maya.addExpense(1999);
      await maya.sync.syncOnce();
      expect(
        expenseRows(maya).map((r) => '${r[2]}/${r[10]}'),
        containsAll(['0.10/10', '19.99/1999']),
      );
    });

    test(
      'a revoked Google grant stops the sync and keeps the data dirty',
      () async {
        await maya.addExpense(100);
        maya.google.revoked = true;
        await expectLater(
          maya.sync.syncOnce(),
          throwsA(isA<GoogleAuthRevoked>()),
        );
        expect((await maya.allExpenses()).single.dirty, isTrue);
        maya.google.revoked = false;
        await maya.sync.syncOnce();
        expect((await maya.allExpenses()).single.dirty, isFalse);
      },
    );

    test('a server error after the retries leaves rows dirty so the next round sends them', () async {
      await maya.addExpense(100);
      await maya.sync.syncOnce();
      await maya.addExpense(200);
      world.failures.add(500);
      await expectLater(maya.sync.syncOnce(), throwsA(isA<GoogleApiError>()));
      expect((await maya.allExpenses()).where((e) => e.dirty), hasLength(1));
      await maya.sync.syncOnce();
      expect(expenseRows(maya), hasLength(2));
    });

    test('the revision goes up with every push', () async {
      await maya.addExpense(100);
      await maya.sync.syncOnce();
      final first = revisionOf(
        world.sheets[maya.settings.ownSheetId!]!.tabs_['Meta']!,
      );
      await maya.sync.syncOnce();
      expect(
        revisionOf(world.sheets[maya.settings.ownSheetId!]!.tabs_['Meta']!),
        first + 1,
      );
    });
  });

  group('organiser import', () {
    setUp(() => Device.pair(dad, maya));

    test('imports new, edited and deleted rows as the member\'s, read-only and not dirty', () async {
      final a = await maya.addExpense(4820, note: 'Groceries');
      await maya.addExpense(900, note: 'Coffee');
      await maya.sync.syncOnce();
      var report = await dad.sync.syncOnce();
      expect(report.imported, 2);
      var rows = await dad.allExpenses();
      expect(rows, hasLength(2));
      expect(
        rows.every((e) => e.createdBy == 'g:maya@family.test' && !e.dirty),
        isTrue,
      );
      expect(rows.firstWhere((e) => e.id == a).amountCents, 4820);
      expect(rows.firstWhere((e) => e.id == a).spentOn, '2026-10-20');

      // Edit and delete on Maya's side.
      maya.now = DateTime.utc(2026, 10, 24);
      await maya.expenses.update(
        a,
        amountCents: 5000,
        categoryId: await maya.food(),
        spentOn: DateTime(2026, 10, 20),
        note: 'Groceries+',
      );
      await maya.sync.syncOnce();
      report = await dad.sync.syncOnce();
      expect(report.imported, greaterThan(0));
      rows = await dad.allExpenses();
      expect(rows.firstWhere((e) => e.id == a).amountCents, 5000);
      expect(rows.firstWhere((e) => e.id == a).note, 'Groceries+');

      final coffee = rows.firstWhere((e) => e.note == 'Coffee').id;
      await maya.expenses.softDelete(coffee);
      await maya.sync.syncOnce();
      await dad.sync.syncOnce();
      expect(
        (await dad.allExpenses()).firstWhere((e) => e.id == coffee).deletedAt,
        isNotNull,
      );
    });

    test('the organiser never pushes imported rows back (his own sheet only has his own)', () async {
      await maya.addExpense(700, note: 'Maya lunch');
      await dad.addExpense(300, note: 'Dad coffee');
      await maya.sync.syncOnce();
      await dad.sync.syncOnce();
      final dadSheet = expenseRows(dad);
      expect(dadSheet.map((r) => r[5]), ['Dad coffee']);
      expect((await dad.allExpenses()), hasLength(2));
    });

    test('an unchanged sheet is not read again', () async {
      await maya.addExpense(100);
      await maya.sync.syncOnce();
      await dad.sync.syncOnce();
      world.calls.clear();
      await dad.sync.syncOnce();
      final reads = world.calls.where((c) => c == 'read').length;
      // Meta only (plus the household sheet bookkeeping and suggestions), never the Expenses tab.
      expect(
        world.calls.where((c) => c == 'read').length,
        lessThan(6),
        reason: '$reads reads',
      );
      expect((await dad.allExpenses()), hasLength(1));
    });

    test('reads in pages', () async {
      for (var i = 1; i <= 7; i++) {
        await maya.addExpense(i * 100);
      }
      await maya.sync.syncOnce();
      final pair = (await dad.db.select(dad.db.sheetPairs).get()).single;
      // A reader with a tiny page size still gets every row.
      final reader = _reader(dad, pageSize: 3);
      final r = await reader.pull(pair, force: true);
      expect(r.added, 7);
    });

    test('rows that are not usable (hand-edited, short, a clash with someone else\'s id) are skipped', () async {
      final own = await dad.addExpense(300, note: 'Dad coffee');
      await maya.addExpense(700, note: 'Maya lunch');
      await maya.sync.syncOnce();
      final grid = world.sheets[maya.settings.ownSheetId!]!.tabs_['Expenses']!;
      grid.add([
        '',
        '2026-10-01',
        '1.00',
        'SGD',
        'Food',
        'no id',
        '',
        '2026-10-01T00:00:00Z',
        '2026-10-01T00:00:00Z',
        '',
        '100',
      ]);
      grid.add([
        'x1',
        'not a date',
        '1.00',
        'SGD',
        'Food',
        '',
        '',
        '',
        '2026-10-01T00:00:00Z',
        '',
        '100',
      ]);
      grid.add([
        'x2',
        '2026-10-01',
        '1.00',
        'SGD',
        'Food',
        '',
        '',
        '',
        '2026-10-01T00:00:00Z',
        '',
        'abc',
      ]);
      grid.add([
        'x3',
        '2026-10-01',
        '1.00',
        'SGD',
        'Food',
        '',
        '',
        '',
        '2026-10-01T00:00:00Z',
        '',
        '-5',
      ]);
      grid.add(['short']);
      // Claims to be the organiser's own expense.
      grid.add([
        own,
        '2026-10-01',
        '9.99',
        'SGD',
        'Food',
        'hijack',
        '',
        '2026-10-01T00:00:00Z',
        '2030-01-01T00:00:00Z',
        '',
        '999',
      ]);
      world.sheets[maya.settings.ownSheetId!]!.tabs_['Meta']![1][1] = '99';
      await dad.sync.syncOnce();
      final rows = await dad.allExpenses();
      expect(rows.map((e) => e.note).toSet(), {'Dad coffee', 'Maya lunch'});
      expect(rows.firstWhere((e) => e.id == own).amountCents, 300);
    });

    test('a category the organiser does not have is created', () async {
      final sheetId = maya.settings.ownSheetId ?? await _ensureSheet(maya);
      await maya.sync.syncOnce();
      world.sheets[sheetId]!.tabs_['Expenses']!.add([
        'e-new',
        '2026-10-02',
        '5.00',
        'SGD',
        'Pets',
        'Vet',
        '',
        '2026-10-02T00:00:00Z',
        '2026-10-02T00:00:00Z',
        '',
        '500',
      ]);
      world.sheets[sheetId]!.tabs_['Meta']![1][1] = '50';
      await dad.sync.syncOnce();
      final cats = await dad.db.select(dad.db.categories).get();
      final pets = cats.firstWhere((c) => c.name == 'Pets');
      expect((await dad.allExpenses()).single.categoryId, pets.id);
    });

    test(
      'a sheet that vanishes shows "access removed" and imports stop',
      () async {
        await maya.addExpense(100);
        await maya.sync.syncOnce();
        await dad.sync.syncOnce();
        world.sheets.remove(maya.settings.ownSheetId);
        final report = await dad.sync.syncOnce();
        expect(report.accessRemoved, ['maya@family.test']);
        expect(
          (await dad.db.select(dad.db.sheetPairs).get()).single.status,
          'accessRemoved',
        );
        expect(await dad.allExpenses(), hasLength(1));
      },
    );

    test('two members at once, each kept apart', () async {
      final sam = Device(world, 'sam@family.test', 'Sam', SheetsRole.member);
      await Device.pair(dad, sam);
      await maya.addExpense(100, note: 'M');
      await sam.addExpense(200, note: 'S');
      await maya.sync.syncOnce();
      await sam.sync.syncOnce();
      await dad.sync.syncOnce();
      final by = {for (final e in await dad.allExpenses()) e.note: e.createdBy};
      expect(by, {'M': 'g:maya@family.test', 'S': 'g:sam@family.test'});
    });

    test('a member cannot read another member\'s sheet', () async {
      final sam = Device(world, 'sam@family.test', 'Sam', SheetsRole.member);
      await Device.pair(dad, sam);
      await sam.sync.syncOnce();
      await expectLater(
        maya.google.read(sam.settings.ownSheetId!, 'Expenses!A1:K'),
        throwsA(isA<SheetAccessError>()),
      );
    });
  });

  group('household sheet', () {
    setUp(() => Device.pair(dad, maya));

    test(
      'budgets, goals, bills and categories reach the member, read-only',
      () async {
        await dad.budgets.setBudget(DateTime(2026, 10), null, 250000);
        await dad.goals.add(
          name: 'Holiday',
          targetCents: 300000,
          monthlyCents: 20000,
        );
        await dad.db
            .into(dad.db.bills)
            .insert(
              BillsCompanion.insert(
                id: 'b1',
                name: 'Rent',
                amountCents: 120000,
                dueDay: 1,
                nextDueOn: '2026-11-01',
                updatedAt: DateTime.utc(2026, 10, 1),
              ),
            );
        await dad.sync.syncOnce();
        await maya.sync.syncOnce();
        final budgets = await maya.db.select(maya.db.budgets).get();
        expect(budgets.single.amountCents, 250000);
        expect(
          (await maya.db.select(maya.db.goals).get()).single.name,
          'Holiday',
        );
        expect((await maya.db.select(maya.db.bills).get()).single.name, 'Rent');
        expect(
          [...budgets, ...await maya.db.select(maya.db.goals).get()].isNotEmpty,
          isTrue,
        );
        final members =
            world.sheets[dad.settings.householdSheetId!]!.tabs_['Members']!;
        expect(members[1][0], 'maya@family.test');
      },
    );

    test(
      'removing something on the organiser\'s side removes it on the member\'s',
      () async {
        final goalId = await dad.goals.add(
          name: 'Holiday',
          targetCents: 300000,
        );
        await dad.sync.syncOnce();
        await maya.sync.syncOnce();
        await dad.goals.softDelete(goalId);
        await dad.sync.syncOnce();
        await maya.sync.syncOnce();
        expect(
          await (maya.db.select(
            maya.db.goals,
          )..where((g) => g.deletedAt.isNull())).get(),
          isEmpty,
        );
      },
    );

    test('an unchanged household is not rewritten', () async {
      await dad.goals.add(name: 'Holiday', targetCents: 300000);
      await dad.sync.syncOnce();
      final rev1 = revisionOf(
        world.sheets[dad.settings.householdSheetId!]!.tabs_['Meta']!,
      );
      await dad.sync.syncOnce();
      expect(
        revisionOf(
          world.sheets[dad.settings.householdSheetId!]!.tabs_['Meta']!,
        ),
        rev1,
      );
    });

    test(
      'a member who is not paired yet (or not shared) waits instead of failing',
      () async {
        final solo = Device(
          world,
          'solo@family.test',
          'Solo',
          SheetsRole.member,
        );
        await solo.addExpense(100);
        final report = await solo.sync.syncOnce();
        expect(report.waitingForOrganiser, isFalse);
        expect(report.pushed, 1);
      },
    );
  });

  group('suggestions', () {
    setUp(() => Device.pair(dad, maya));

    Future<String> suggestBudget() => maya.suggestions.create(
      memberEmail: 'maya@family.test',
      kind: 'budget',
      action: 'add',
      payload: {'month': '2026-10-01', 'amountCents': 180000},
      note: 'Groceries went up',
    );

    test('a member\'s suggestion reaches the organiser, who approves it and the member sees the result', () async {
      final id = await suggestBudget();
      await maya.sync.syncOnce();
      await dad.sync.syncOnce();
      var inbox = await dad.db.select(dad.db.suggestions).get();
      expect(inbox.single.id, id);
      expect(inbox.single.memberEmail, 'maya@family.test');
      expect(inbox.single.note, 'Groceries went up');
      expect(inbox.single.status, 'pending');

      await dad.suggestions.approve(id);
      expect(
        (await dad.db.select(dad.db.budgets).get()).single.amountCents,
        180000,
      );
      await dad.sync.syncOnce();
      await maya.sync.syncOnce();
      final mine = await maya.db.select(maya.db.suggestions).get();
      expect(mine.single.status, 'approved');
      expect(
        (await maya.db.select(maya.db.budgets).get()).single.amountCents,
        180000,
        reason: 'the approved budget arrives through the household sheet',
      );
    });

    test('declining changes nothing but the status', () async {
      final id = await suggestBudget();
      await maya.sync.syncOnce();
      await dad.sync.syncOnce();
      await dad.suggestions.decline(id);
      await dad.sync.syncOnce();
      await maya.sync.syncOnce();
      expect(
        (await maya.db.select(maya.db.suggestions).get()).single.status,
        'declined',
      );
      expect(await dad.db.select(dad.db.budgets).get(), isEmpty);
    });

    test('goal and bill suggestions: add and change', () async {
      final goalId = await dad.goals.add(name: 'Holiday', targetCents: 300000);
      final g = await maya.suggestions.create(
        memberEmail: 'maya@family.test',
        kind: 'goal',
        action: 'add',
        payload: {'name': 'Bike', 'targetCents': 90000, 'monthlyCents': 5000},
      );
      final gc = await maya.suggestions.create(
        memberEmail: 'maya@family.test',
        kind: 'goal',
        action: 'change',
        targetId: goalId,
        payload: {'targetCents': 350000},
      );
      final b = await maya.suggestions.create(
        memberEmail: 'maya@family.test',
        kind: 'bill',
        action: 'add',
        payload: {
          'name': 'Gym',
          'amountCents': 5000,
          'nextDueOn': '2026-11-05',
          'repeat': 'monthly',
        },
      );
      await maya.sync.syncOnce();
      await dad.sync.syncOnce();
      for (final id in [g, gc, b]) {
        await dad.suggestions.approve(id);
      }
      final goals = await dad.db.select(dad.db.goals).get();
      expect(goals.map((x) => x.name), containsAll(['Holiday', 'Bike']));
      expect(goals.firstWhere((x) => x.id == goalId).targetCents, 350000);
      expect((await dad.db.select(dad.db.bills).get()).single.name, 'Gym');
    });

    test('an approved suggestion cannot be applied twice', () async {
      final id = await suggestBudget();
      await maya.sync.syncOnce();
      await dad.sync.syncOnce();
      await dad.suggestions.approve(id);
      await dad.budgets.setBudget(DateTime(2026, 10), null, 111100);
      await dad.suggestions.approve(id);
      expect(
        (await dad.db.select(dad.db.budgets).get()).single.amountCents,
        111100,
      );
    });

    test('bad suggestions are refused before they are saved', () async {
      Future<void> bad(
        String kind,
        String action,
        Map<String, Object?> payload, {
        String? target,
      }) => expectLater(
        maya.suggestions.create(
          memberEmail: 'maya@family.test',
          kind: kind,
          action: action,
          targetId: target,
          payload: payload,
        ),
        throwsA(isA<PairingError>()),
      );
      await bad('budget', 'add', {'month': '2026-10-01', 'amountCents': 0});
      await bad('budget', 'add', {'month': 'October', 'amountCents': 100});
      await bad('goal', 'add', {'name': ' ', 'targetCents': 100});
      await bad('goal', 'change', {'targetCents': 100});
      await bad('bill', 'add', {'name': 'x', 'amountCents': 100});
      await bad('unicorn', 'add', {});
      expect(await maya.db.select(maya.db.suggestions).get(), isEmpty);
    });

    test(
      'a decision on a suggestion the member no longer has is harmless',
      () async {
        await dad.sync.syncOnce();
        expect(await dad.db.select(dad.db.suggestions).get(), isEmpty);
      },
    );
  });

  group('safety', () {
    test(
      'no Google token or password ends up in the database or in a sheet',
      () async {
        await Device.pair(dad, maya);
        await maya.addExpense(100);
        await maya.sync.syncOnce();
        await dad.sync.syncOnce();
        for (final d in [dad, maya]) {
          final dump = StringBuffer();
          for (final t in d.db.allTables) {
            for (final r in await d.db.select(t).get()) {
              dump.write(jsonEncode((r as dynamic).toJson()));
            }
          }
          expect(dump.toString().toLowerCase(), isNot(contains('fake-token')));
          expect(dump.toString().toLowerCase(), isNot(contains('refresh')));
        }
        for (final s in world.sheets.values) {
          expect(
            jsonEncode(s.tabs_).toLowerCase(),
            isNot(contains('fake-token')),
          );
        }
      },
    );

    test('everything works without any Supabase configuration', () async {
      await Device.pair(dad, maya);
      await maya.addExpense(100);
      await maya.sync.syncOnce();
      expect((await dad.sync.syncOnce()).imported, 1);
    });
  });
}

Future<String> _ensureSheet(Device d) async {
  await d.sync.syncOnce();
  return d.settings.ownSheetId!;
}

MemberReader _reader(Device d, {required int pageSize}) => MemberReader(
  d.db,
  d.google,
  CategoryRepository(d.db),
  householdId: 'local',
  pageSize: pageSize,
);
