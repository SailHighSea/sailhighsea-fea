import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/money/currency.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/import/category_guess.dart';
import 'package:family_expenses/features/import/import_parser.dart';
import 'package:family_expenses/features/import/import_service.dart';
import 'package:family_expenses/features/import/statement_readers.dart';
import 'package:family_expenses/features/scan/receipt_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../helpers/pump_member.dart';
import '../../helpers/test_app.dart';

final _today = DateTime(2026, 10, 23);
final _sgd = currencyByCode('SGD');
final _qar = currencyByCode('QAR');

/// The statement from the user's screenshot, as text (a PDF or a photo reads the same).
const _statement = '''
Post Date  Purchase Date  Description & Reference  Foreign Currency  Amount in QAR
25/09/26  22/09/26  AZZCO HYPERMARKET, DOHA, 068276  58.39
25/09/26  22/09/26  CARE N CURE-BIN MAHMOU, DOHA, 026120  38.00
27/09/26  25/09/26  BASKIN ROBBINS-MALL OF, DOHA, 057489  26.00
28/09/26  25/09/26  PAPA DOLA RESTAURANT, DOHA, 080722  60.00
30/09/26  27/09/26  ALPHA BARBERSHOP, DOHA, 034973  15.00
04/10/26  01/10/26  LULU HYPERMARKET, DOHA, 002313  192.78
05/10/26  05/10/26  Paid using bankDirect  051026K34702  CR  1,000.00
06/10/26  01/10/26  CENTURY RESTAURANT BIN, DOHA, 039948  26.00
Continued on next page...
''';

void main() {
  setUpAll(loadTestFonts);

  group('more kinds of spreadsheet', () {
    test('header names from banks, and Debit and Credit columns (money in is left out)', () {
      final p = parseImportRows(
        parseCsv(
          'Transaction Date,Particulars,Debit,Credit,Balance\n20/10/2026,NTUC FAIRPRICE,48.20,,900.00\n21/10/2026,SALARY,,3000.00,3900.00\n22/10/2026,GRAB RIDE,12.00,,3888.00',
        ),
        currency: _sgd,
        today: _today,
      );
      expect(p.rows.map((r) => (r.description, r.cents)), [
        ('NTUC FAIRPRICE', 4820),
        ('GRAB RIDE', 1200),
      ]);
      expect(p.incomeSkipped, 1);
    });

    test('a bank export that writes spending as negative numbers', () {
      final p = parseImportRows(
        parseCsv(
          'Date,Description,Amount\n2026-10-20,Shop,-48.20\n2026-10-21,Salary,3000.00\n2026-10-22,Bus,-2.10',
        ),
        currency: _sgd,
        today: _today,
      );
      expect(p.rows.map((r) => r.cents), [4820, 210]);
      expect(p.incomeSkipped, 1);
    });

    test(
      'mostly positive amounts: a negative is a refund and is not imported',
      () {
        final p = parseImportRows(
          parseCsv(
            'Date,Description,Amount\n2026-10-20,A,10\n2026-10-21,B,20\n2026-10-22,Refund,-5',
          ),
          currency: _sgd,
          today: _today,
        );
        expect(p.rows, hasLength(2));
        expect(p.problems.single.message, contains('Refunds'));
      },
    );
  });

  group('currency detection', () {
    CurrencyDetection d(String csv) => detectCurrencies(parseCsv(csv));
    test('from a currency column, a code in the amount, or a symbol', () {
      expect(d('Date,Currency,Amount\n2026-10-20,eur,5').codes, {'EUR'});
      expect(d('Date,Amount\n2026-10-20,SGD 5.00').codes, {'SGD'});
      expect(d('Date,Amount\n2026-10-20,€5.00').codes, {'EUR'});
      expect(d('Date,Amount\n2026-10-20,"S\$5.00"').codes, {'SGD'});
      expect(d('Date,Amount\n2026-10-20,5\n2026-10-21,"QAR 6"').codes, {'QAR'});
    });
    test('nothing found, a bare dollar sign, or several currencies', () {
      expect(d('Date,Amount\n2026-10-20,5').unknown, isTrue);
      final dollar = d('Date,Amount\n2026-10-20,\$5');
      expect(dollar.unknown, isTrue);
      expect(dollar.ambiguousDollar, isTrue);
      expect(
        d('Date,Currency,Amount\n2026-10-20,SGD,5\n2026-10-21,EUR,6').codes,
        {'SGD', 'EUR'},
      );
    });
  });

  group('categories', () {
    late List<CategoryRow> cats;
    setUp(() async {
      final db = AppDatabase(NativeDatabase.memory());
      cats = await db.select(db.categories).get();
      await db.close();
    });
    String? name(CategoryGuess g) => g.categoryId == null
        ? null
        : cats.firstWhere((c) => c.id == g.categoryId).name;

    test(
      'keywords decide the obvious ones, and unknown shops are left to ask',
      () {
        final g = CategoryGuesser(categories: cats, history: const {});
        expect(name(g.guess('AZZCO HYPERMARKET, DOHA')), 'Food');
        expect(name(g.guess('PAPA DOLA RESTAURANT')), 'Food');
        expect(name(g.guess('SHELL PETROL')), 'Transport');
        expect(name(g.guess('GRAB RIDE 123')), 'Transport');
        expect(name(g.guess('CITY PHARMACY')), 'Health');
        expect(name(g.guess('SINGTEL BILL')), 'Bills');
        expect(name(g.guess('NETFLIX')), 'Fun');
        expect(g.guess('ALPHA BARBERSHOP').categoryId, isNull);
        expect(g.guess('').categoryId, isNull);
      },
    );

    test('short words only match whole words (a "bus" is not "business")', () {
      final g = CategoryGuesser(categories: cats, history: const {});
      expect(name(g.guess('MRT TOPUP')), 'Transport');
      expect(g.guess('BUSINESS CARDS PRINTING').categoryId, isNull);
    });

    test(
      'what you did before wins: the same shop gets the same category',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final repo = ExpenseRepository(db);
        await repo.add(
          amountCents: 100,
          categoryId: 'default-bills',
          spentOn: DateTime(2026, 10, 1),
          note: 'ALPHA BARBERSHOP #12',
        );
        await repo.add(
          amountCents: 100,
          categoryId: 'default-bills',
          spentOn: DateTime(2026, 10, 2),
          note: 'alpha barbershop 99',
        );
        final guesser = await ImportService(
          db,
          currency: _sgd,
          today: _today,
        ).loadGuesser();
        final g = guesser.guess('ALPHA BARBERSHOP, DOHA');
        expect(
          g.categoryId,
          isNull,
          reason: 'a longer description is a different key',
        );
        expect(guesser.guess('Alpha Barbershop 7').categoryId, 'default-bills');
        expect(guesser.guess('Alpha Barbershop 7').reason, 'history');
        await db.close();
      },
    );

    test('a renamed category is still found by what it means', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await (db.update(db.categories)
            ..where((c) => c.id.equals('default-food')))
          .write(const CategoriesCompanion(name: Value('Groceries & dining')));
      final guesser = await ImportService(
        db,
        currency: _sgd,
        today: _today,
      ).loadGuesser();
      expect(guesser.guess('SUPERMARKET').categoryId, 'default-food');
      await db.close();
    });
  });

  group('statements', () {
    test('lines with a date and an amount become rows; CR is money in; references are dropped', () {
      final s = rowsFromStatementText(_statement, defaultYear: 2026);
      expect(s.moneyIn, 1);
      final data = s.rows.skip(1).toList();
      expect(data, hasLength(7));
      expect(data.first.take(3), [
        '25/09/26',
        'AZZCO HYPERMARKET, DOHA',
        '58.39',
      ]);
      expect(
        data.every((r) => r[4] == 'QAR'),
        isTrue,
        reason: 'the currency is in the header line',
      );
      final parsed = parseImportRows(s.rows, currency: _qar, today: _today);
      expect(parsed.problems, isEmpty);
      expect(
        parsed.rows.first.date,
        '2026-09-25',
        reason: 'day first, two-digit year',
      );
      expect(
        parsed.rows.map((r) => r.cents).reduce((a, b) => a + b),
        5839 + 3800 + 2600 + 6000 + 1500 + 19278 + 2600,
      );
    });

    test('with a running balance the amount is the one before it', () {
      final s = rowsFromStatementText(
        '20 Oct 2026  NTUC FAIRPRICE  48.20  1,951.80\n',
        defaultYear: 2026,
      );
      expect(s.rows[1][2], '48.20');
    });

    test('a date without a year takes the statement year', () {
      final s = rowsFromStatementText(
        '23 Oct  COFFEE SHOP  4.50\n',
        defaultYear: 2026,
      );
      expect(
        parseImportRows(s.rows, currency: _sgd, today: _today).rows.single.date,
        '2026-10-23',
      );
    });

    test('a photographed statement is put back together by rows', () {
      OcrLine l(String t, double x, double y) =>
          OcrLine(t, left: x, top: y, right: x + 100, bottom: y + 20);
      final lines = [
        l('Amount in QAR', 1200, 10),
        l('25/09/26', 50, 52),
        l('22/09/26', 190, 53),
        l('AZZCO HYPERMARKET, DOHA, 068276', 310, 52),
        l('58.39', 1300, 54),
        l('05/10/26', 50, 92),
        l('05/10/26', 190, 93),
        l('Paid using bankDirect 051026K34702', 310, 92),
        l('CR', 1200, 93),
        l('1,000.00', 1300, 92),
        l('28/09/26', 50, 132),
        l('28/09/26', 190, 133),
        l('PAPA DOLA RESTAURANT, DOHA, 080722', 310, 132),
        l('60.00', 1300, 131),
      ];
      final s = rowsFromOcrLines(lines, defaultYear: 2026);
      expect(s.moneyIn, 1);
      expect(s.rows.skip(1).map((r) => r[2]), ['58.39', '60.00']);
      expect(s.rows[1][1], 'AZZCO HYPERMARKET, DOHA');
      expect(s.rows[1][4], 'QAR');
    });

    test('no text, no rows', () {
      expect(rowsFromOcrLines(const []).rows, hasLength(1));
      expect(
        rowsFromStatementText('hello world\nno dates here').rows,
        hasLength(1),
      );
    });

    test('a real PDF: text is read back out of it', () {
      final doc = PdfDocument();
      final page = doc.pages.add();
      final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
      var y = 0.0;
      for (final line in _statement.trim().split('\n')) {
        page.graphics.drawString(
          line,
          font,
          bounds: Rect.fromLTWH(0, y, 500, 16),
        );
        y += 16;
      }
      final bytes = Uint8List.fromList(doc.saveSync());
      doc.dispose();
      final s = rowsFromStatementText(textFromPdf(bytes), defaultYear: 2026);
      expect(s.rows.length, greaterThan(5));
      expect(s.rows[1][1], contains('AZZCO HYPERMARKET'));
      expect(s.rows[1][2], '58.39');
    });

    test(
      'an Excel file: the first sheet, dates as real dates, exact amounts',
      () {
        final book = Excel.createExcel();
        final sheet = book[book.getDefaultSheet()!];
        sheet.appendRow([
          TextCellValue('Date'),
          TextCellValue('Description'),
          TextCellValue('Currency'),
          TextCellValue('Amount'),
        ]);
        sheet.appendRow([
          const DateCellValue(year: 2026, month: 10, day: 20),
          TextCellValue('Groceries'),
          TextCellValue('SGD'),
          const DoubleCellValue(48.2),
        ]);
        sheet.appendRow([
          const DateCellValue(year: 2026, month: 10, day: 21),
          TextCellValue('Coffee'),
          TextCellValue('SGD'),
          const IntCellValue(5),
        ]);
        final rows = rowsFromXlsx(Uint8List.fromList(book.save()!));
        expect(rows[1], ['2026-10-20', 'Groceries', 'SGD', '48.2']);
        final p = parseImportRows(rows, currency: _sgd, today: _today);
        expect(p.rows.map((r) => r.cents), [4820, 500]);
      },
    );
  });

  group('screen', () {
    Future<void> open(
      WidgetTester tester, {
      PickedImport? file,
      OcrLines? ocr,
      String? photo,
      Size size = const Size(390, 844),
      bool ocrAvailable = true,
    }) => pumpApp(
      tester,
      size: size,
      location: '/import',
      overrides: [
        importFilePickerProvider.overrideWithValue(() async => file),
        receiptOcrProvider.overrideWithValue(
          _FakeOcr(ocr ?? const [], available: ocrAvailable),
        ),
        receiptImageSourceProvider.overrideWithValue(_Source(photo)),
      ],
    );

    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await settle(tester);
    }

    testWidgets(
      'categories are filled in, unknown ones are asked, and nothing imports until they are chosen',
      (tester) async {
        await open(
          tester,
          file: PickedImport.text(
            's.csv',
            'Date,Description,Currency,Amount\n2026-10-20,NTUC FAIRPRICE,SGD,48.20\n2026-10-21,ALPHA BARBERSHOP,SGD,15\n2026-10-22,GRAB RIDE,SGD,12',
          ),
        );
        await tapKey(tester, 'import-file');
        expect(find.byKey(const ValueKey('import-table')), findsOneWidget);
        expect(find.text('Food'), findsWidgets);
        expect(find.text('Transport'), findsWidgets);
        expect(find.byKey(const ValueKey('import-missing')), findsOneWidget);
        expect(
          find.text(
            '1 expense needs a category. Choose one in the table, or put them in Other.',
          ),
          findsOneWidget,
        );
        final confirm = tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(const ValueKey('import-confirm')),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(confirm, isNotNull);
        // Choose a category for the unknown one.
        await tester.ensureVisible(find.byKey(const ValueKey('category-3')));
        await tester.tap(find.byKey(const ValueKey('category-3')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other').last);
        await settle(tester);
        expect(find.byKey(const ValueKey('import-missing')), findsNothing);
      },
    );

    testWidgets('"Put the rest in Other" answers every question at once', (
      tester,
    ) async {
      await open(
        tester,
        file: PickedImport.text(
          's.csv',
          'Date,Description,Currency,Amount\n2026-10-20,ALPHA BARBERSHOP,SGD,15\n2026-10-21,AL ANEES ELECTRONICS,SGD,79',
        ),
      );
      await tapKey(tester, 'import-file');
      expect(find.byKey(const ValueKey('import-missing')), findsOneWidget);
      await tapKey(tester, 'import-other');
      expect(find.byKey(const ValueKey('import-missing')), findsNothing);
      await tapKey(tester, 'import-confirm');
      await settle(tester);
      expect(find.text('Imported 2 expenses'), findsOneWidget);
    });

    testWidgets('a row can be left out with its checkbox', (tester) async {
      await open(
        tester,
        file: PickedImport.text(
          's.csv',
          'Date,Description,Currency,Amount\n2026-10-20,NTUC FAIRPRICE,SGD,48.20\n2026-10-21,GRAB RIDE,SGD,12',
        ),
      );
      await tapKey(tester, 'import-file');
      expect(find.text('Import 2 expenses'), findsOneWidget);
      await tapKey(tester, 'use-2');
      expect(find.text('Import 1 expenses'), findsOneWidget);
    });

    testWidgets(
      'no currency in the file: it asks, and nothing is shown until answered',
      (tester) async {
        await open(
          tester,
          file: PickedImport.text(
            's.csv',
            'Date,Description,Amount\n2026-10-20,NTUC FAIRPRICE,48.20',
          ),
        );
        await tapKey(tester, 'import-file');
        expect(
          find.text(
            'We could not tell which currency these amounts are in. Which currency are they?',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('import-table')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('currency-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('SGD  Singapore dollar').last);
        await settle(tester);
        expect(find.byKey(const ValueKey('import-table')), findsOneWidget);
      },
    );

    testWidgets(
      'a currency other than the app\'s must be confirmed as "import as they are"',
      (tester) async {
        await open(
          tester,
          file: PickedImport.text(
            's.csv',
            'Date,Description,Currency,Amount\n2026-10-20,NTUC FAIRPRICE,QAR,48.20',
          ),
        );
        await tapKey(tester, 'import-file');
        expect(find.text('Currency: QAR (found in the file)'), findsOneWidget);
        expect(find.byKey(const ValueKey('keep-as-is')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('import-table')),
          findsNothing,
          reason: 'not until the person agrees',
        );
        await tapKey(tester, 'keep-as-is');
        expect(find.byKey(const ValueKey('import-table')), findsOneWidget);
      },
    );

    testWidgets(
      'a photo of a statement is read, the credit is left out, and Qatari riyals are understood',
      (tester) async {
        OcrLine l(String t, double x, double y) =>
            OcrLine(t, left: x, top: y, right: x + 100, bottom: y + 20);
        await open(
          tester,
          photo: '/tmp/statement.png',
          ocr: [
            l('Amount in QAR', 1200, 10),
            l('25/09/26', 50, 52),
            l('22/09/26', 190, 53),
            l('AZZCO HYPERMARKET, DOHA, 068276', 310, 52),
            l('58.39', 1300, 54),
            l('28/09/26', 50, 92),
            l('25/09/26', 190, 93),
            l('ALPHA BARBERSHOP, DOHA, 034973', 310, 92),
            l('15.00', 1300, 92),
            l('05/10/26', 50, 132),
            l('CR', 1200, 133),
            l('1,000.00', 1300, 132),
          ],
        );
        await tapKey(tester, 'import-photo');
        expect(find.text('Currency: QAR (found in the file)'), findsOneWidget);
        await tapKey(tester, 'keep-as-is');
        expect(
          find.text('2 new expenses, S\$73.39 in total'),
          findsOneWidget,
          reason: 'amounts are not converted',
        );
        expect(find.textContaining('1 money-in rows left out'), findsOneWidget);
        expect(find.text('Food'), findsWidgets);
        expect(find.byKey(const ValueKey('import-missing')), findsOneWidget);
      },
    );

    testWidgets('where pictures cannot be read (desktop) it says so', (
      tester,
    ) async {
      await open(tester, ocrAvailable: false, size: const Size(1280, 800));
      await tapKey(tester, 'import-photo');
      expect(find.textContaining('works in the phone app'), findsOneWidget);
    });

    testWidgets('a picture with nothing readable explains what to do', (
      tester,
    ) async {
      await open(tester, photo: '/tmp/x.png', ocr: const []);
      await tapKey(tester, 'import-photo');
      expect(find.textContaining('No text was found'), findsOneWidget);
    });

    testWidgets('old .xls and scanned PDFs are explained', (tester) async {
      await open(tester, file: PickedImport('old.xls', Uint8List(0)));
      await tapKey(tester, 'import-file');
      expect(find.byKey(const ValueKey('import-error')), findsOneWidget);
      expect(find.textContaining('Old .xls files'), findsOneWidget);
    });

    testWidgets('the Add screen has an import button next to the scan button', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(390, 844), location: '/add');
      expect(find.byKey(const ValueKey('import-from-add')), findsOneWidget);
      expect(find.byKey(const ValueKey('scan-receipt')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('import-from-add')));
      await settle(tester);
      expect(find.text('Import expenses'), findsOneWidget);
    });

    testWidgets(
      'fits and meets tap targets with a table, at phone, tablet and desktop widths',
      (tester) async {
        for (final size in const [
          Size(360, 740),
          Size(840, 900),
          Size(1280, 800),
        ]) {
          await open(
            tester,
            file: PickedImport.text(
              's.csv',
              'Date,Description,Currency,Amount\n2026-10-20,NTUC FAIRPRICE,SGD,48.20\n2026-10-21,ALPHA BARBERSHOP,SGD,15',
            ),
            size: size,
          );
          await tapKey(tester, 'import-file');
          expect(tester.takeException(), isNull, reason: '$size');
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        }
      },
    );
  });
}

typedef OcrLines = List<OcrLine>;

class _FakeOcr implements ReceiptOcr {
  _FakeOcr(this.lines, {this.available = true});
  final List<OcrLine> lines;
  final bool available;
  @override
  bool get isAvailable => available;
  @override
  Future<String> recognise(String imagePath) async => '';
  @override
  Future<List<OcrLine>> recogniseLines(String imagePath) async => lines;
}

class _Source implements ReceiptImageSource {
  _Source(this.path);
  final String? path;
  @override
  bool get hasCamera => false;
  @override
  Future<String?> takePhoto() async => path;
  @override
  Future<String?> chooseFile() async => path;
}
