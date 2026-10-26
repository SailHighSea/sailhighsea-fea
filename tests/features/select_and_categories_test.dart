import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/core/money/currency.dart';
import 'package:family_expenses/core/sheets_sync/sheets_settings.dart';
import 'package:family_expenses/features/expenses/data/category_rule_repository.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:family_expenses/features/import/import_service.dart';
import 'package:family_expenses/features/import/statement_readers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

Future<void> _seed(AppDatabase db) async {
  final repo = ExpenseRepository(db, clock: () => DateTime.utc(2026, 10, 20));
  await repo.add(
    amountCents: 4820,
    categoryId: 'default-food',
    spentOn: DateTime(2026, 10, 20),
    note: 'Groceries',
    createdBy: 'You',
  );
  await repo.add(
    amountCents: 1200,
    categoryId: 'default-food',
    spentOn: DateTime(2026, 10, 19),
    note: 'Lunch',
    createdBy: 'You',
  );
  await repo.add(
    amountCents: 900,
    categoryId: 'default-transport',
    spentOn: DateTime(2026, 10, 18),
    note: 'Bus',
    createdBy: 'You',
  );
  await repo.add(
    amountCents: 7700,
    categoryId: 'default-fun',
    spentOn: DateTime(2026, 10, 17),
    note: 'Game',
    createdBy: 'You',
  );
}

Future<List<ExpenseRow>> _rows(WidgetTester tester, ProviderContainer c) async {
  final db = c.read(databaseProvider);
  return (await tester.runAsync(() => db.select(db.expenses).get()))!;
}

void main() {
  setUpAll(loadTestFonts);

  Future<ProviderContainer> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    List<Override>? overrides,
  }) => pumpApp(
    tester,
    size: size,
    location: '/expenses',
    seedAsync: _seed,
    overrides: overrides ?? const [],
  );

  Future<void> tap(WidgetTester tester, String k) async {
    final f = find.byKey(ValueKey(k));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  Future<String> id(
    WidgetTester tester,
    ProviderContainer c,
    String note,
  ) async => (await _rows(tester, c)).firstWhere((e) => e.note == note).id;

  group('select several expenses', () {
    testWidgets(
      'Select shows checkboxes; tapping rows selects them; Cancel leaves it',
      (tester) async {
        final c = await open(tester);
        expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
        await tap(tester, 'select-start');
        expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
        expect(find.text('Tap expenses to select them'), findsOneWidget);
        final groceries = await id(tester, c, 'Groceries');
        await tap(tester, 'select-$groceries');
        expect(find.text('1 selected'), findsOneWidget);
        await tester.tap(find.text('Lunch'));
        await tester.pump();
        expect(find.text('2 selected'), findsOneWidget);
        await tester.tap(find.text('Lunch'));
        await tester.pump();
        expect(find.text('1 selected'), findsOneWidget);
        await tap(tester, 'select-cancel');
        expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
        expect(await _rows(tester, c), hasLength(4), reason: 'nothing changed');
      },
    );

    testWidgets('a long press starts selecting with that row ticked', (
      tester,
    ) async {
      await open(tester);
      await tester.longPress(find.text('Bus'));
      await settle(tester);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('Select all, then Clear', (tester) async {
      await open(tester);
      await tap(tester, 'select-start');
      await tap(tester, 'select-all');
      expect(find.text('4 selected'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      await tap(tester, 'select-all');
      expect(find.text('Tap expenses to select them'), findsOneWidget);
    });

    testWidgets('the action buttons wait until something is selected', (
      tester,
    ) async {
      await open(tester);
      await tap(tester, 'select-start');
      final del = tester.widget<InkWell>(
        find
            .descendant(
              of: find.byKey(const ValueKey('bulk-delete')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(del.onTap, isNull);
    });

    testWidgets('Delete removes them all, and Undo brings them back', (
      tester,
    ) async {
      final c = await open(tester);
      await tap(tester, 'select-start');
      await tester.tap(find.text('Groceries'));
      await tester.pump();
      await tester.tap(find.text('Lunch'));
      await tester.pump();
      await tap(tester, 'bulk-delete');
      expect(find.text('2 expenses deleted'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Bus'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('selection-bar')),
        findsNothing,
        reason: 'back to the normal list',
      );
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.text('Groceries'), findsOneWidget);
      expect(
        (await _rows(tester, c)).where((e) => e.deletedAt != null),
        isEmpty,
      );
    });

    testWidgets('Change category moves them all and remembers the shops', (
      tester,
    ) async {
      final c = await open(tester);
      await tap(tester, 'select-start');
      await tester.tap(find.text('Groceries'));
      await tester.pump();
      await tester.tap(find.text('Game'));
      await tester.pump();
      await tap(tester, 'bulk-category');
      expect(find.text('Move 2 expenses'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('bulk-category-apply')),
            )
            .onPressed,
        isNull,
        reason: 'choose first',
      );
      await tester.tap(find.byKey(const ValueKey('bulk-category-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Health').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bulk-category-apply')));
      await settle(tester);
      expect(find.text('2 expenses moved'), findsOneWidget);
      final rows = await _rows(tester, c);
      expect(
        rows
            .where((e) => e.categoryId == 'default-health')
            .map((e) => e.note)
            .toSet(),
        {'Groceries', 'Game'},
      );
      expect(
        rows.firstWhere((e) => e.note == 'Lunch').categoryId,
        'default-food',
        reason: 'the others are untouched',
      );
      final rules = await tester.runAsync(
        () => CategoryRuleRepository(c.read(databaseProvider)).all(),
      );
      expect(rules!['groceries'], 'default-health');
    });

    testWidgets(
      'a new category can be made right there and the expenses move into it',
      (tester) async {
        final c = await open(tester);
        await tap(tester, 'select-start');
        await tester.tap(find.text('Bus'));
        await tester.pump();
        await tap(tester, 'bulk-category');
        await tester.tap(find.byKey(const ValueKey('bulk-category-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('New category').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('new-category-field')),
          'Commute',
        );
        await tester.tap(find.byKey(const Key('new-category-add')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('bulk-category-apply')));
        await settle(tester);
        final db = c.read(databaseProvider);
        final cats = (await tester.runAsync(
          () => db.select(db.categories).get(),
        ))!;
        final commute = cats.singleWhere((x) => x.name == 'Commute');
        expect(
          (await _rows(
            tester,
            c,
          )).firstWhere((e) => e.note == 'Bus').categoryId,
          commute.id,
        );
      },
    );

    for (final size in const {
      'tablet': Size(840, 900),
      'desktop': Size(1280, 800),
    }.entries) {
      testWidgets('works on ${size.key} too, and fits', (tester) async {
        await open(tester, size: size.value);
        await tap(tester, 'select-start');
        await tap(tester, 'select-all');
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }

    testWidgets('a view-only member has no Select button', (tester) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/expenses',
        size: const Size(390, 844),
      );
      expect(find.byKey(const ValueKey('select-start')), findsNothing);
    });

    testWidgets(
      'in Sheets mode the organiser cannot select a member\'s expenses',
      (tester) async {
        final c = await pumpApp(
          tester,
          size: const Size(390, 844),
          location: '/expenses',
          prefs: {'sheets.settings': '{"role":"organiser","name":""}'},
          overrides: [
            backendModeProvider.overrideWithValue(BackendMode.sheets),
          ],
          seedAsync: (db) async {
            await _seed(db);
            await ExpenseRepository(db).add(
              amountCents: 500,
              categoryId: 'default-food',
              spentOn: DateTime(2026, 10, 20),
              note: 'Maya lunch',
              createdBy: 'g:maya@family.test',
            );
          },
        );
        await tap(tester, 'select-start');
        await tap(tester, 'select-all');
        expect(
          find.text('4 selected'),
          findsOneWidget,
          reason: 'only his own four, not the member\'s',
        );
        final mayaId = await id(tester, c, 'Maya lunch');
        expect(find.byKey(ValueKey('select-$mayaId')), findsNothing);
      },
    );
  });

  group('new categories while choosing', () {
    testWidgets(
      'a member in Sheets mode may add one (the data is on their own device)',
      (tester) async {
        final c = await pumpApp(
          tester,
          size: const Size(390, 844),
          prefs: {'sheets.settings': '{"role":"member","name":""}'},
          overrides: [
            backendModeProvider.overrideWithValue(BackendMode.sheets),
          ],
        );
        expect(c.read(permissionsProvider).canManageCategories, isTrue);
      },
    );
  });

  group('shops in an imported statement, once each', () {
    const csv =
        'Date,Description,Currency,Amount\n'
        '2026-10-20,ALPHA BARBERSHOP 111,SGD,15\n'
        '2026-10-21,NTUC FAIRPRICE,SGD,20\n'
        '2026-10-22,ALPHA BARBERSHOP 222,SGD,16\n'
        '2026-10-22,AL ANEES ELECTRONICS,SGD,79\n'
        '2026-10-23,ALPHA BARBERSHOP 333,SGD,14';

    Future<ProviderContainer> start(
      WidgetTester tester, {
      Size size = const Size(390, 844),
    }) async {
      final c = await pumpApp(
        tester,
        size: size,
        location: '/import',
        overrides: [
          importFilePickerProvider.overrideWithValue(
            () async => PickedImport.text('s.csv', csv),
          ),
        ],
      );
      await tap(tester, 'import-file');
      return c;
    }

    testWidgets('each shop is listed once, with how many rows and the total', (
      tester,
    ) async {
      await start(tester);
      expect(find.byKey(const ValueKey('import-shops')), findsOneWidget);
      expect(find.text('3 different shops'), findsOneWidget);
      expect(
        find.text('3 rows · S\$45.00'),
        findsOneWidget,
        reason: 'the barber appears three times',
      );
      expect(find.text('2 shops need one.'), findsNothing);
      expect(
        find.textContaining('2 shops need one'),
        findsOneWidget,
        reason: 'barber and electronics are unknown',
      );
    });

    testWidgets('choosing once for a shop fills all its rows', (tester) async {
      await start(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('shop-category-ALPHA BARBERSHOP 111')),
      );
      await tester.tap(
        find.byKey(const ValueKey('shop-category-ALPHA BARBERSHOP 111')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Health').last);
      await settle(tester);
      expect(find.textContaining('1 shop needs one'), findsOneWidget);
      // The three barber rows in the table all say Health now.
      for (final line in [2, 4, 6]) {
        final dd = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: find.byKey(ValueKey('category-$line')),
            matching: find.byType(DropdownButton<String>),
          ),
        );
        expect(dd.value, 'default-health', reason: 'row $line');
      }
    });

    testWidgets('a new category can be made from the shop list', (
      tester,
    ) async {
      final c = await start(tester);
      final key = find.byKey(
        const ValueKey('shop-category-ALPHA BARBERSHOP 111'),
      );
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New category').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-category-field')),
        'Grooming',
      );
      await tester.tap(find.byKey(const Key('new-category-add')));
      await settle(tester);
      await settle(tester);
      final db = c.read(databaseProvider);
      final cats = (await tester.runAsync(
        () => db.select(db.categories).get(),
      ))!;
      final grooming = cats.singleWhere((x) => x.name == 'Grooming');
      final dd = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const ValueKey('category-2')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dd.value, grooming.id);
      // Import everything and check the shops are remembered for the next statement.
      await tap(tester, 'import-other');
      await tap(tester, 'import-confirm');
      await settle(tester);
      final rules = await tester.runAsync(
        () => CategoryRuleRepository(db).all(),
      );
      expect(rules!['alpha barbershop'], grooming.id);
      expect(
        rules.containsKey('al anees electronics'),
        isFalse,
        reason: 'Other is not remembered',
      );
    });

    for (final size in const {
      'phone': Size(360, 740),
      'tablet': Size(840, 900),
      'desktop': Size(1280, 800),
    }.entries) {
      testWidgets('fits on ${size.key}', (tester) async {
        await start(tester, size: size.value);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });

  test('statement text feeds the shop list too (sanity)', () {
    final s = rowsFromStatementText(
      '25/09/26  22/09/26  AZZCO HYPERMARKET, DOHA, 068276  58.39\n',
      defaultYear: 2026,
    );
    expect(s.rows, hasLength(2));
    expect(currencyByCode('QAR').code, 'QAR');
  });
}
