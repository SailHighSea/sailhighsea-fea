import 'dart:async';

import 'package:drift/native.dart';
import 'package:family_expenses/core/money/currency.dart';

import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/features/duplicates/duplicate_finder.dart';
import 'package:family_expenses/features/duplicates/duplicate_providers.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/import/import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:family_expenses/features/expenses/expense_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

ExpenseRow _e(
  String id,
  String by,
  String note, {
  int cents = 4820,
  String day = '2026-10-20',
  DateTime? at,
  DateTime? deleted,
}) => expenseRow(
  id: id,
  spentOn: day,
  cents: cents,
  note: note,
  createdBy: by,
  updatedAt: at ?? DateTime(2026, 10, 20, 9),
  deletedAt: deleted,
);

Future<T> _appRun<T>(WidgetTester tester, Future<T> Function() f) async {
  T? result;
  Object? error;
  var done = false;
  unawaited(
    f().then(
      (v) {
        result = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 100 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  if (error != null) throw error!;
  return result as T;
}

final _sgd = currencyByCode('SGD');

void main() {
  setUpAll(loadTestFonts);

  group('which descriptions could be the same purchase', () {
    test('digits, case and punctuation do not matter; one containing the other counts', () {
      expect(
        similarDescriptions('LULU HYPERMARKET 12', 'lulu hypermarket 99'),
        isTrue,
      );
      expect(similarDescriptions('Lulu', 'LULU HYPERMARKET, DOHA'), isTrue);
      expect(similarDescriptions('', 'Groceries'), isTrue);
      expect(similarDescriptions('Groceries', 'Bus fare'), isFalse);
      expect(
        similarDescriptions('ab', 'abcdef'),
        isFalse,
        reason: 'too short to say',
      );
    });
  });

  group('finding duplicates added by two people', () {
    test('same day, amount and description by different people is a pair', () {
      final pairs = findSharedDuplicates([
        _e('a', 'me', 'Groceries'),
        _e('b', 'maya', 'groceries'),
      ], me: 'me');
      expect(pairs, hasLength(1));
      expect({pairs.single.first.id, pairs.single.second.id}, {'a', 'b'});
    });

    test('the same person buying twice is not a duplicate', () {
      expect(
        findSharedDuplicates([
          _e('a', 'me', 'Coffee'),
          _e('b', 'me', 'Coffee'),
        ], me: 'me'),
        isEmpty,
      );
      expect(
        findSharedDuplicates([
          _e('a', 'You', 'Coffee'),
          _e('b', 'me', 'Coffee'),
        ], me: 'me'),
        isEmpty,
        reason: '"You" is me',
      );
    });

    test(
      'another day, another amount, another thing or a deleted entry is not',
      () {
        expect(
          findSharedDuplicates([
            _e('a', 'me', 'x1'),
            _e('b', 'maya', 'x1', day: '2026-10-21'),
          ], me: 'me'),
          isEmpty,
        );
        expect(
          findSharedDuplicates([
            _e('a', 'me', 'Food'),
            _e('b', 'maya', 'Food', cents: 4821),
          ], me: 'me'),
          isEmpty,
        );
        expect(
          findSharedDuplicates([
            _e('a', 'me', 'Groceries'),
            _e('b', 'maya', 'Bus fare'),
          ], me: 'me'),
          isEmpty,
        );
        expect(
          findSharedDuplicates([
            _e('a', 'me', 'Food'),
            _e('b', 'maya', 'Food', deleted: DateTime(2026, 10, 21)),
          ], me: 'me'),
          isEmpty,
        );
      },
    );

    test('answered pairs are left out, in either order', () {
      final rows = [_e('a', 'me', 'Food'), _e('b', 'maya', 'Food')];
      final key = findSharedDuplicates(rows, me: 'me').single.key;
      expect(findSharedDuplicates(rows, me: 'me', resolved: {key}), isEmpty);
      expect(
        findSharedDuplicates(rows.reversed.toList(), me: 'me', resolved: {key}),
        isEmpty,
      );
    });

    test('three people with the same entry give every pair', () {
      final rows = [
        _e('a', 'me', 'F'),
        _e('b', 'maya', 'F'),
        _e('c', 'sam', 'F'),
      ];
      expect(findSharedDuplicates(rows, me: 'me'), hasLength(3));
    });
  });

  group('importing', () {
    late AppDatabase db;
    late ImportService service;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      service = ImportService(
        db,
        currency: _sgd,
        today: DateTime(2026, 10, 23),
      );
    });
    tearDown(() => db.close());
    test('a row that matches an existing one loosely is a possible duplicate, once each', () async {
      final repo = ExpenseRepository(db, clock: () => DateTime(2026, 10, 20));
      await repo.add(
        amountCents: 4820,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 20),
        note: 'LULU HYPERMARKET, DOHA 0123',
        createdBy: 'Maya',
      );
      final p = await service.previewCsv(
        'Date,Description,Currency,Amount\n'
        '2026-10-20,Lulu Hypermarket Doha,SGD,48.20\n'
        '2026-10-20,Lulu Hypermarket Doha,SGD,48.20\n'
        '2026-10-20,Bus,SGD,2.10',
      );
      expect(p.duplicates, hasLength(1));
      expect(
        p.ready,
        hasLength(2),
        reason: 'the second identical row is a real second purchase',
      );
    });
  });

  group('the import screen asks', () {
    Future<ProviderContainer> open(WidgetTester tester) => pumpApp(
      tester,
      size: const Size(390, 844),
      location: '/import',
      seedAsync: (db) async {
        final repo = ExpenseRepository(db, clock: () => DateTime(2026, 10, 20));
        await repo.add(
          amountCents: 4820,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 20),
          note: 'Groceries',
          createdBy: 'You',
        );
      },
      overrides: [
        importFilePickerProvider.overrideWithValue(
          () async => PickedImport.text(
            'file.csv',
            'Date,Description,Currency,Amount\n2026-10-20,Groceries,SGD,48.20\n2026-10-20,Bus,SGD,2.10',
          ),
        ),
      ],
    );

    testWidgets('Skip duplicates leaves them out', (tester) async {
      await open(tester);
      await tapKey(tester, 'import-file');
      expect(key('import-duplicates-dialog'), findsOneWidget);
      expect(find.textContaining('Groceries'), findsWidgets);
      await tapKey(tester, 'dup-skip');
      expect(find.text('1 new expenses, S\$2.10 in total'), findsOneWidget);
      expect(
        find.textContaining('looked like duplicates (skipped)'),
        findsOneWidget,
      );
      expect(find.textContaining('Possible duplicate'), findsNothing);
    });

    testWidgets('Import them anyway adds them to the table, marked', (
      tester,
    ) async {
      await open(tester);
      await tapKey(tester, 'import-file');
      await tapKey(tester, 'dup-keep');
      expect(
        find.textContaining('Possible duplicate · Groceries'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'look like duplicates (added to the table, marked)',
        ),
        findsOneWidget,
      );
    });
  });

  group('entries two people both added', () {
    Future<ProviderContainer> openAsOwner(WidgetTester tester) async {
      return pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: const Size(390, 844),
        seed: false,
      );
    }

    Future<void> addPair(
      WidgetTester tester,
      ProviderContainer c, {
      String firstBy = ownerUser,
      String secondBy = adminUser,
    }) => _appRun(tester, () async {
      final repo = c.read(expenseRepositoryProvider);
      Future<void> add(String by, DateTime at) =>
          ExpenseRepository(
            c.read(databaseProvider),
            clock: () => at,
            householdId: 'household-1',
          ).add(
            amountCents: 4820,
            categoryId: 'default-food',
            spentOn: DateTime(2026, 10, 23),
            note: 'Groceries',
            createdBy: by,
          );
      expect(repo, isNotNull);
      await add(firstBy, DateTime(2026, 10, 23, 9));
      await add(secondBy, DateTime(2026, 10, 23, 10));
    });

    testWidgets('nobody is asked when there is no pair', (tester) async {
      await openAsOwner(tester);
      expect(key('duplicate-dialog'), findsNothing);
    });

    testWidgets(
      'a pair opens the question; Different keeps both and is not asked again',
      (tester) async {
        final c = await openAsOwner(tester);
        await addPair(tester, c);
        await settle(tester);
        expect(key('duplicate-dialog'), findsOneWidget);
        expect(find.textContaining('Groceries'), findsWidgets);
        await tapKey(tester, 'duplicate-different');
        await settle(tester);
        expect(key('duplicate-dialog'), findsNothing);
        expect(c.read(duplicateDecisionsProvider), hasLength(1));
        expect(c.read(duplicatePairsProvider), isEmpty);
      },
    );

    testWidgets(
      'Same removes the newer entry the person may remove, with Undo',
      (tester) async {
        final c = await openAsOwner(tester);
        await addPair(tester, c, firstBy: adminUser, secondBy: ownerUser);
        await settle(tester);
        await tapKey(tester, 'duplicate-same');
        await settle(tester);
        final db = c.read(databaseProvider);
        final rows = await _appRun<List<ExpenseRow>>(
          tester,
          () => db.select(db.expenses).get(),
        );
        final live = rows
            .where((e) => e.deletedAt == null && e.note == 'Groceries')
            .toList();
        expect(live, hasLength(1));
        expect(find.text('Duplicate removed'), findsOneWidget);
      },
    );

    testWidgets('Ask me later closes it for now', (tester) async {
      final c = await openAsOwner(tester);
      await addPair(tester, c);
      await settle(tester);
      await tapKey(tester, 'duplicate-later');
      await settle(tester);
      expect(key('duplicate-dialog'), findsNothing);
      expect(c.read(duplicateDecisionsProvider), isEmpty);
      expect(c.read(duplicatesLaterProvider), hasLength(1));
    });

    testWidgets(
      'the dialog fits on a small phone with large text and a desktop',
      (tester) async {
        final c = await pumpAsMember(
          tester,
          me: ownerUser,
          location: '/home',
          size: const Size(320, 640),
          textScale: 1.6,
          seed: false,
        );
        await addPair(tester, c);
        await settle(tester);
        expect(key('duplicate-dialog'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
