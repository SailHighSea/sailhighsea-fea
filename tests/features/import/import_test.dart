import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/google/google_api.dart';
import 'package:family_expenses/core/money/currency.dart';
import 'package:family_expenses/core/sheets_sync/sheets_settings.dart';
import 'package:family_expenses/features/import/import_parser.dart';
import 'package:family_expenses/features/import/import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_google.dart';
import '../../helpers/pump_member.dart';
import '../../helpers/test_app.dart';

final _sgd = currencyByCode('SGD');
final _today = DateTime(2026, 10, 23);

ImportParse _parse(String csv) =>
    parseImportRows(parseCsv(csv), currency: _sgd, today: _today);

void main() {
  setUpAll(loadTestFonts);

  group('CSV reading', () {
    test(
      'commas, semicolons and tabs; quotes; line breaks inside quotes; BOM',
      () {
        expect(parseCsv('a,b,c\n1,2,3'), [
          ['a', 'b', 'c'],
          ['1', '2', '3'],
        ]);
        expect(parseCsv('a;b;c\r\n1;2;3\r\n'), [
          ['a', 'b', 'c'],
          ['1', '2', '3'],
        ]);
        expect(parseCsv('a\tb\n1\t2'), [
          ['a', 'b'],
          ['1', '2'],
        ]);
        expect(parseCsv('x,"he said ""hi"", ok",y'), [
          ['x', 'he said "hi", ok', 'y'],
        ]);
        expect(parseCsv('x,"two\nlines",y\nz'), [
          ['x', 'two\nlines', 'y'],
          ['z'],
        ]);
        expect(parseCsv('﻿Date,Amount\n1,2').first.first, 'Date');
        expect(parseCsv('a,b\n\n\n1,2'), [
          ['a', 'b'],
          ['1', '2'],
        ], reason: 'blank lines are skipped');
      },
    );
  });

  group('dates', () {
    String? d(String s) => parseImportDate(s, today: _today);
    test('the usual formats', () {
      expect(d('2026-10-05'), '2026-10-05');
      expect(d('2026/10/5'), '2026-10-05');
      expect(d('05/10/2026'), '2026-10-05', reason: 'day first');
      expect(d('5-10-26'), '2026-10-05');
      expect(d('5 Oct 2026'), '2026-10-05');
      expect(d('October 5, 2026'), '2026-10-05');
      expect(d('2026-10-05 14:30'), '2026-10-05');
    });
    test('refuses what is not a real past date', () {
      expect(d('31/02/2026'), isNull);
      expect(d('2027-01-01'), isNull);
      expect(d('yesterday'), isNull);
      expect(d(''), isNull);
    });
  });

  group('rows', () {
    test('a header in any order, with description and currency', () {
      final p = _parse(
        'Amount,Currency,Date,Description\n48.20,SGD,2026-10-20,Groceries\n12,sgd,21/10/2026,"Bus, MRT"',
      );
      expect(p.problems, isEmpty);
      expect(p.rows.map((r) => (r.date, r.description, r.cents)), [
        ('2026-10-20', 'Groceries', 4820),
        ('2026-10-21', 'Bus, MRT', 1200),
      ]);
    });

    test('no header: Date, Description, Currency, Amount in that order', () {
      final p = _parse('2026-10-20,Lunch,SGD,9.50');
      expect(p.rows.single.cents, 950);
      expect(p.rows.single.description, 'Lunch');
    });

    test('the description and currency columns are optional with a header', () {
      final p = _parse('Date,Amount\n2026-10-20,5');
      expect(p.rows.single.description, '');
      expect(p.rows.single.cents, 500);
    });

    test('money is exact whole cents, including symbols, thousands and comma decimals', () {
      int c(String a) => _parse('Date,Amount\n2026-10-20,$a').rows.single.cents;
      expect(c('0.10'), 10);
      expect(c('19.99'), 1999);
      expect(c('"1,234.56"'), 123456);
      expect(c('"S\$1,234.56"'), 123456);
      expect(
        c('"48,20"'),
        4820,
        reason: 'a comma before two digits is the decimal point',
      );
      expect(c('"1.234,56"'), 123456);
      expect(c('1000'), 100000);
    });

    test(
      'problem rows are reported with their line and skipped, never guessed',
      () {
        final p = _parse(
          'Date,Description,Currency,Amount\n'
          '2026-10-20,ok,SGD,5\n'
          'nope,bad date,SGD,5\n'
          '2026-10-20,bad amount,SGD,abc\n'
          '2026-10-20,other currency,EUR,5\n'
          '2026-10-20,refund,SGD,-5\n'
          '2026-10-20,zero,SGD,0\n'
          '2026-10-20,none,SGD,\n'
          ',,,\n'
          '2027-01-01,future,SGD,5',
        );
        expect(p.rows.map((r) => r.description), ['ok']);
        expect(p.problems.map((e) => e.line), [3, 4, 5, 6, 7, 8, 10]);
        expect(
          p.problems.firstWhere((e) => e.line == 5).message,
          contains('EUR'),
        );
      },
    );

    test('nothing in, nothing out', () {
      expect(_parse('').rows, isEmpty);
      expect(_parse('Date,Amount').rows, isEmpty);
    });
  });

  test('a sheet link or an id', () {
    expect(
      sheetIdFromInput(
        'https://docs.google.com/spreadsheets/d/1AbC_dEf-GhIjKlMnOpQrStUvWxYz/edit#gid=0',
      ),
      '1AbC_dEf-GhIjKlMnOpQrStUvWxYz',
    );
    expect(
      sheetIdFromInput('1AbC_dEf-GhIjKlMnOpQrStUvWxYz'),
      '1AbC_dEf-GhIjKlMnOpQrStUvWxYz',
    );
    expect(sheetIdFromInput('hello'), isNull);
  });

  group('service', () {
    late AppDatabase db;
    late ImportService service;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      service = ImportService(db, currency: _sgd, today: _today);
    });
    tearDown(() => db.close());

    const csv =
        'Date,Description,Currency,Amount\n2026-10-20,Groceries,SGD,48.20\n2026-10-21,Coffee,SGD,4.50\n2026-10-21,Coffee,SGD,4.50\nbad,x,SGD,1';

    test('preview then import saves everything in Other, as mine, and counts exactly', () async {
      final p = await service.previewCsv(csv);
      expect(
        (p.ready.length, p.duplicates.length, p.problems.length),
        (3, 0, 1),
      );
      expect(p.totalCents, 4820 + 450 + 450);
      expect(
        await db.select(db.expenses).get(),
        isEmpty,
        reason: 'a preview saves nothing',
      );
      expect(await service.import(p), 3);
      final rows = await db.select(db.expenses).get();
      expect(rows, hasLength(3));
      expect(
        rows.every(
          (e) =>
              e.categoryId == 'default-other' &&
              e.createdBy == 'You' &&
              e.dirty,
        ),
        isTrue,
      );
      expect(rows.map((e) => e.note).toSet(), {'Groceries', 'Coffee'});
    });

    test('importing the same file again adds nothing, but two real identical rows both count', () async {
      await service.import(await service.previewCsv(csv));
      final again = await service.previewCsv(csv);
      expect((again.ready.length, again.duplicates.length), (0, 3));
      expect(await service.import(again), 0);
      expect(await db.select(db.expenses).get(), hasLength(3));
      // A third coffee in a newer file is new.
      final p = await service.previewCsv('$csv\n2026-10-21,Coffee,SGD,4.50');
      expect((p.ready.length, p.duplicates.length), (1, 3));
    });

    test('deleted expenses do not block a re-import', () async {
      await service.import(await service.previewCsv(csv));
      await (db.update(db.expenses))
          .write(ExpensesCompanion(deletedAt: Value(DateTime(2026, 10, 22))));
      expect((await service.previewCsv(csv)).ready, hasLength(3));
    });

    test('from a Google Sheet: the first tab, whatever it is called', () async {
      final world = FakeGoogleWorld();
      final g = world.account('maya@family.test');
      final id = await g.createSpreadsheet('Bank export', ['My Bank']);
      await g.writeRanges(id, {
        'My Bank!A1:D3': [
          ['Date', 'Description', 'Currency', 'Amount'],
          ['2026-10-20', 'Groceries', 'SGD', '48.20'],
          ['2026-10-21', 'Coffee', 'SGD', '4.50'],
        ],
      });
      final p = await service.previewSheet(g, id);
      expect(p.ready.map((r) => r.cents), [4820, 450]);
    });
  });

  group('screen', () {
    Future<void> open(
      WidgetTester tester, {
      String? csv,
      Size size = const Size(390, 844),
    }) => pumpApp(
      tester,
      size: size,
      location: '/import',
      overrides: [importFilePickerProvider.overrideWithValue(() async => csv)],
    );

    testWidgets(
      'choose a file, see the preview, import, land on the expense list',
      (tester) async {
        await open(
          tester,
          csv: 'Date,Description,Currency,Amount\n2026-10-20,Groceries,SGD,48.20\n2026-10-20,Bus,SGD,2.10\nbad,x,SGD,1',
        );
        expect(find.byKey(const ValueKey('import-preview')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('import-file')));
        await settle(tester);
        expect(find.text('2 new expenses, S\$50.30 in total'), findsOneWidget);
        expect(find.textContaining('1 rows skipped'), findsOneWidget);
        expect(find.textContaining('Line 4'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('import-confirm')),
        );
        await tester.tap(find.byKey(const ValueKey('import-confirm')));
        await settle(tester);
        await settle(tester);
        expect(find.text('Groceries'), findsWidgets);
        expect(find.text('Imported 2 expenses'), findsOneWidget);
      },
    );

    testWidgets('an empty or cancelled choice shows nothing and no error', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('import-file')));
      await settle(tester);
      expect(find.byKey(const ValueKey('import-preview')), findsNothing);
      expect(find.byKey(const ValueKey('import-error')), findsNothing);
    });

    testWidgets(
      'a file with nothing usable says so and offers no Import button',
      (tester) async {
        await open(tester, csv: 'Date,Amount\nnope,abc');
        await tester.tap(find.byKey(const ValueKey('import-file')));
        await settle(tester);
        expect(find.text('Nothing new to import'), findsOneWidget);
        expect(find.byKey(const ValueKey('import-confirm')), findsNothing);
      },
    );

    testWidgets(
      'the Google Sheet box appears in Sheets mode and reads a sheet',
      (tester) async {
        final world = FakeGoogleWorld();
        final g = world.account('maya@family.test');
        final id = await tester.runAsync(() async {
          final sid = await g.createSpreadsheet('Export', ['Sheet1']);
          await g.writeRanges(sid, {
            'Sheet1!A1:D2': [
              ['Date', 'Description', 'Currency', 'Amount'],
              ['2026-10-20', 'Lunch', 'SGD', '9.50'],
            ],
          });
          return sid;
        });
        await pumpApp(
          tester,
          size: const Size(390, 844),
          location: '/import',
          overrides: [
            backendModeProvider.overrideWithValue(BackendMode.sheets),
            sheetsApiProvider.overrideWithValue(g),
          ],
        );
        await tester.enterText(
          find.byType(EditableText),
          'https://docs.google.com/spreadsheets/d/$id/edit',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('import-sheet')));
        await settle(tester);
        expect(find.text('1 new expenses, S\$9.50 in total'), findsOneWidget);
      },
    );

    testWidgets(
      'fits and meets tap targets at phone, tablet and desktop widths',
      (tester) async {
        for (final size in const [
          Size(360, 740),
          Size(840, 900),
          Size(1280, 800),
        ]) {
          await open(tester, csv: 'Date,Amount\n2026-10-20,5', size: size);
          await tester.tap(find.byKey(const ValueKey('import-file')));
          await settle(tester);
          expect(tester.takeException(), isNull, reason: '$size');
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        }
      },
    );
  });
}
