import 'dart:convert';

import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/core/money/currency.dart';
import 'package:family_expenses/features/backup/backup_service.dart';
import 'package:family_expenses/features/bills/data/bill_repository.dart';
import 'package:family_expenses/features/budgets/data/budget_repository.dart';
import 'package:family_expenses/features/expenses/data/category_rule_repository.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/goals/data/goal_repository.dart';
import 'package:family_expenses/features/import/category_guess.dart';
import 'package:family_expenses/features/import/import_parser.dart';
import 'package:family_expenses/features/import/import_service.dart';
import 'package:family_expenses/features/privacy/csv_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_member.dart';
import '../../helpers/test_app.dart';

final _sgd = currencyByCode('SGD');
final _today = DateTime(2026, 10, 23);

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

Future<void> _fill(AppDatabase db) async {
  final now = DateTime.utc(2026, 10, 20);
  await ExpenseRepository(db, clock: () => now).add(
    amountCents: 4820,
    categoryId: 'default-food',
    spentOn: DateTime(2026, 10, 20),
    note: 'Groceries',
    createdBy: 'You',
  );
  await ExpenseRepository(db, clock: () => now).add(
    amountCents: 1999,
    categoryId: 'default-fun',
    spentOn: DateTime(2026, 10, 21),
    note: 'Game',
  );
  await BudgetRepository(
    db,
    clock: () => now,
  ).setBudget(DateTime(2026, 10), null, 250000);
  final goal = await GoalRepository(
    db,
    clock: () => now,
  ).add(name: 'Holiday', targetCents: 300000);
  await GoalRepository(db, clock: () => now).addMoney(goal, cents: 5000);
  await BillRepository(
    db,
    clock: () => now,
  ).add(name: 'Rent', amountCents: 120000, nextDueOn: DateTime(2026, 11, 1));
  await CategoryRuleRepository(
    db,
    clock: () => now,
  ).remember('NTUC FAIRPRICE #12', 'default-food');
}

void main() {
  setUpAll(loadTestFonts);

  group('backup file', () {
    test('export then restore on a fresh install brings everything back, exact to the cent', () async {
      final a = _db();
      await _fill(a);
      final json = await BackupService(a, currencyCode: 'SGD').export();
      final doc = jsonDecode(json) as Map<String, dynamic>;
      expect(doc['format'], 'family-expenses-backup');
      expect((doc['expenses'] as List).length, 2);

      final b = _db();
      final svc = BackupService(b, currencyCode: 'SGD');
      final counts = svc.inspect(json);
      expect(
        (counts.expenses, counts.goals, counts.bills, counts.budgets),
        (2, 1, 1, 1),
      );
      final done = await svc.restore(json);
      expect(done.expenses, 2);
      final rows = await b.select(b.expenses).get();
      expect(rows.map((e) => e.amountCents).toSet(), {4820, 1999});
      expect(rows.map((e) => e.note).toSet(), {'Groceries', 'Game'});
      expect(
        rows.every((e) => e.dirty),
        isTrue,
        reason: 'restored data is marked for syncing',
      );
      expect((await b.select(b.goals).get()).single.name, 'Holiday');
      expect(
        (await b.select(b.goalContributions).get()).single.amountCents,
        5000,
      );
      expect((await b.select(b.bills).get()).single.name, 'Rent');
      expect((await b.select(b.budgets).get()).single.amountCents, 250000);
      expect(
        (await b.select(b.categoryRules).get()).single.categoryId,
        'default-food',
        reason: 'remembered shops come back too',
      );
      await a.close();
      await b.close();
    });

    test(
      'restoring twice changes nothing, and newer data on the device is kept',
      () async {
        final a = _db();
        await _fill(a);
        final json = await BackupService(a, currencyCode: 'SGD').export();
        final svc = BackupService(a, currencyCode: 'SGD');
        expect(
          (await svc.restore(json)).expenses,
          0,
          reason: 'identical rows are not rewritten',
        );
        // Edit an expense after the backup: a restore must not undo it.
        final e = (await a.select(a.expenses).get()).first;
        await ExpenseRepository(
          a,
          clock: () => DateTime.utc(2026, 11, 1),
        ).update(
          e.id,
          amountCents: 9999,
          categoryId: e.categoryId,
          spentOn: DateTime(2026, 10, 20),
          note: 'edited',
        );
        await svc.restore(json);
        expect(
          (await (a.select(
            a.expenses,
          )..where((x) => x.id.equals(e.id))).getSingle()).amountCents,
          9999,
        );
        expect(await a.select(a.expenses).get(), hasLength(2));
        await a.close();
      },
    );

    test(
      'deleted things are not backed up, and nothing is deleted by a restore',
      () async {
        final a = _db();
        await _fill(a);
        final id = (await a.select(a.expenses).get()).first.id;
        await ExpenseRepository(a).softDelete(id);
        final json = await BackupService(a, currencyCode: 'SGD').export();
        expect((jsonDecode(json)['expenses'] as List).length, 1);
        final b = _db();
        await ExpenseRepository(b).add(
          amountCents: 100,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 1),
          note: 'already here',
        );
        await BackupService(b, currencyCode: 'SGD').restore(json);
        expect(await b.select(b.expenses).get(), hasLength(2));
        await a.close();
        await b.close();
      },
    );

    test('a backup from another household is restored into this one', () async {
      final a = _db();
      await _fill(a);
      await a.customStatement(
        "UPDATE expenses SET household_id = 'some-other-household'",
      );
      final json = await BackupService(
        a,
        currencyCode: 'SGD',
        householdId: 'some-other-household',
      ).export();
      final b = _db();
      await BackupService(b, currencyCode: 'SGD').restore(json);
      expect(
        (await b.select(b.expenses).get()).every(
          (e) => e.householdId == 'local',
        ),
        isTrue,
      );
      await a.close();
      await b.close();
    });

    test('files that are not backups, are newer, or are damaged are refused and change nothing', () async {
      final b = _db();
      final svc = BackupService(b, currencyCode: 'SGD');
      for (final bad in [
        '',
        'hello',
        '[]',
        '{"format":"other","version":1}',
        '{"format":"family-expenses-backup","version":99}',
      ]) {
        expect(
          () => svc.inspect(bad),
          throwsA(isA<BackupFailure>()),
          reason: bad,
        );
      }
      const damaged =
          '{"format":"family-expenses-backup","version":1,"expenses":[{"id":"x"}]}';
      await expectLater(svc.restore(damaged), throwsA(isA<BackupFailure>()));
      expect(await b.select(b.expenses).get(), isEmpty);
      await b.close();
    });

    test('an expense with a missing category lands in Other, and a zero amount is skipped', () async {
      final b = _db();
      final doc = {
        'format': 'family-expenses-backup',
        'version': 1,
        'expenses': [
          {
            'id': 'e1',
            'householdId': 'local',
            'amountCents': 500,
            'categoryId': 'gone',
            'note': '',
            'spentOn': '2026-10-01',
            'createdBy': null,
            'receiptPath': null,
            'updatedAt': '2026-10-01T00:00:00.000Z',
            'deletedAt': null,
            'dirty': false,
          },
          {
            'id': 'e2',
            'householdId': 'local',
            'amountCents': 0,
            'categoryId': 'default-food',
            'note': '',
            'spentOn': '2026-10-01',
            'createdBy': null,
            'receiptPath': null,
            'updatedAt': '2026-10-01T00:00:00.000Z',
            'deletedAt': null,
            'dirty': false,
          },
        ],
      };
      await BackupService(b, currencyCode: 'SGD').restore(jsonEncode(doc));
      final rows = await b.select(b.expenses).get();
      expect(rows.single.categoryId, 'default-other');
      await b.close();
    });
  });

  group('remembered categories', () {
    test('a shop is remembered by its description, ignoring digits and punctuation', () async {
      final db = _db();
      final repo = CategoryRuleRepository(db);
      await repo.remember('NTUC FAIRPRICE #123, SG', 'default-food');
      expect((await repo.all()).keys, ['ntuc fairprice sg']);
      await repo.remember('12', 'default-fun');
      await repo.remember('', 'default-fun');
      expect(
        await repo.all(),
        hasLength(1),
        reason: 'a description with no shop in it is not remembered',
      );
      await repo.remember('ntuc fairprice sg', 'default-bills');
      expect((await repo.all()).values, [
        'default-bills',
      ], reason: 'the latest decision wins');
      await db.close();
    });

    test('the guesser uses a remembered shop before keywords and history, and matches longer or shorter names', () async {
      final db = _db();
      final cats = await db.select(db.categories).get();
      final g = CategoryGuesser(
        categories: cats,
        history: const {},
        rules: const {'azzco hypermarket': 'default-bills'},
      );
      expect(
        g.guess('AZZCO HYPERMARKET').categoryId,
        'default-bills',
        reason: 'beats the "hypermarket" keyword',
      );
      expect(
        g.guess('AZZCO HYPERMARKET, DOHA, 068276').categoryId,
        'default-bills',
        reason: 'a longer description of the same shop',
      );
      expect(g.guess('AZZCO HYPERMARKET, DOHA').reason, 'remembered');
      expect(
        g.guess('AZZCO').categoryId,
        isNull,
        reason: 'one word is not enough to be sure',
      );
      final deleted = CategoryGuesser(
        categories: cats.where((c) => c.id != 'default-bills').toList(),
        history: const {},
        rules: const {'azzco hypermarket': 'default-bills'},
      );
      expect(
        deleted.guess('AZZCO HYPERMARKET').categoryId,
        'default-food',
        reason: 'a deleted category is ignored',
      );
      await db.close();
    });

    test('importing remembers every confirmed category (not Other), so the next import is automatic', () async {
      final db = _db();
      final svc = ImportService(db, currency: _sgd, today: _today);
      const csv =
          'Date,Description,Currency,Amount\n2026-10-20,ALPHA BARBERSHOP DOHA 034973,SGD,15\n2026-10-21,NTUC FAIRPRICE,SGD,20\n2026-10-22,MYSTERY SHOP,SGD,5';
      var preview = await svc.previewCsv(csv);
      var guesser = await svc.loadGuesser();
      final drafts = [
        for (final r in preview.ready)
          ImportDraft(r, categoryId: guesser.guess(r.description).categoryId),
      ];
      expect(
        drafts.where((d) => d.categoryId == null),
        hasLength(2),
        reason: 'barbershop and mystery are unknown at first',
      );
      // The person chooses Health for the barber and Other for the mystery shop.
      drafts[0].categoryId = 'default-health';
      drafts[2].categoryId = 'default-other';
      await svc.importDrafts(drafts);

      final rules = await CategoryRuleRepository(db).all();
      expect(rules['alpha barbershop doha'], 'default-health');
      expect(
        rules['ntuc fairprice'],
        'default-food',
        reason: 'an automatic guess that was confirmed is remembered too',
      );
      expect(
        rules.containsKey('mystery shop'),
        isFalse,
        reason: 'Other says nothing about the shop',
      );

      // A new statement with the same shops (and different reference numbers) sorts itself.
      preview = await svc.previewCsv(
        'Date,Description,Currency,Amount\n2026-10-23,ALPHA BARBERSHOP DOHA 999111,SGD,16',
      );
      guesser = await svc.loadGuesser();
      final g = guesser.guess(preview.ready.single.description);
      expect((g.categoryId, g.reason), ('default-health', 'remembered'));
      await db.close();
    });

    testWidgets('saving an expense with a note remembers its category', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/add',
      );
      final db = c.read(databaseProvider);
      await tester.tap(
        find
            .descendant(of: find.byType(Scaffold), matching: find.text('5'))
            .first,
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('note-field')),
        'Alpha Barbershop',
      );
      await tester.pump();
      await tester.tap(find.text('Health'));
      await tester.pump();
      await tester.tap(find.text('Save expense'));
      await settle(tester);
      await settle(tester);
      final rules = await tester.runAsync(
        () => CategoryRuleRepository(db).all(),
      );
      expect(rules!['alpha barbershop'], 'default-health');
    });

    test('parse still reads statements as before (sanity)', () {
      expect(
        parseImportRows(
          parseCsv('Date,Amount\n2026-10-20,5'),
          currency: _sgd,
          today: _today,
        ).rows,
        hasLength(1),
      );
    });
  });

  group('screens', () {
    testWidgets('Back up to a file shares one JSON file with a dated name', (
      tester,
    ) async {
      final shared = <(String, String, String)>[];
      final c = await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/appearance',
        overrides: [fileSharerProvider.overrideWithValue(_Sharer(shared))],
      );
      await tester.runAsync(() => _fill(c.read(databaseProvider)));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('backup-file')));
      await tester.tap(find.byKey(const ValueKey('backup-file')));
      await settle(tester);
      await settle(tester);
      expect(shared, hasLength(1));
      expect(shared.single.$1, 'family-expenses-backup-2026-10-23.json');
      expect(shared.single.$3, 'application/json');
      expect(
        (jsonDecode(shared.single.$2) as Map)['format'],
        'family-expenses-backup',
      );
      expect(find.text('Backup file created'), findsOneWidget);
    });

    testWidgets('Restore asks first and says what is in the file', (
      tester,
    ) async {
      final src = _db();
      await _fill(src);
      final json = await BackupService(src, currencyCode: 'SGD').export();
      await src.close();
      final c = await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/appearance',
        overrides: [
          backupFilePickerProvider.overrideWithValue(() async => json),
        ],
      );
      await tester.ensureVisible(find.byKey(const ValueKey('restore-file')));
      await tester.tap(find.byKey(const ValueKey('restore-file')));
      await settle(tester);
      expect(find.text('Restore this backup?'), findsOneWidget);
      expect(find.textContaining('2 expenses'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-restore')));
      await settle(tester);
      await settle(tester);
      expect(find.text('Restored 2 expenses'), findsOneWidget);
      final db = c.read(databaseProvider);
      expect(
        (await tester.runAsync(() => db.select(db.expenses).get()))!,
        hasLength(2),
      );
    });

    testWidgets('a file that is not a backup is refused with a message', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/appearance',
        overrides: [
          backupFilePickerProvider.overrideWithValue(() async => 'hello'),
        ],
      );
      await tester.ensureVisible(find.byKey(const ValueKey('restore-file')));
      await tester.tap(find.byKey(const ValueKey('restore-file')));
      await settle(tester);
      expect(
        find.text('That file is not a Family Expenses backup.'),
        findsOneWidget,
      );
      expect(find.text('Restore this backup?'), findsNothing);
    });

    testWidgets('Privacy and data says nothing is shared with the developer', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/appearance',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('data-note')));
      expect(
        find.text(
          'Nothing is shared with the app developer. Everything stays on this device or in your own Google account.',
        ),
        findsOneWidget,
      );
    });
  });
}

class _Sharer implements FileSharer {
  _Sharer(this.shared);
  final List<(String, String, String)> shared;
  @override
  Future<void> shareText(
    String filename,
    String content,
    String mimeType,
  ) async => shared.add((filename, content, mimeType));
}
