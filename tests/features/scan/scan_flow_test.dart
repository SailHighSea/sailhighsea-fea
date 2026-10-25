import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/features/expenses/expense_form_controller.dart';
import 'package:family_expenses/features/scan/receipt_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_member.dart';
import '../../helpers/test_app.dart';

class _Source implements ReceiptImageSource {
  _Source({this.camera = true, this.path = '/tmp/receipt.jpg'});
  final bool camera;
  String? path;
  @override
  bool get hasCamera => camera;
  @override
  Future<String?> takePhoto() async => path;
  @override
  Future<String?> chooseFile() async => path;
}

class _Ocr implements ReceiptOcr {
  _Ocr(this.text, {this.available = true});
  final String text;
  final bool available;
  @override
  bool get isAvailable => available;
  @override
  Future<String> recognise(String imagePath) async => text;
  @override
  Future<List<OcrLine>> recogniseLines(String imagePath) async => const [];
}

class _Storage implements ReceiptStorage {
  _Storage({this.fail = false});
  final bool fail;
  final uploads = <String>[];
  @override
  Future<String> upload({
    required String householdId,
    required String expenseId,
    required String localPath,
  }) async {
    if (fail) throw Exception('offline');
    final path = '$householdId/$expenseId.jpg';
    uploads.add(path);
    return path;
  }
}

const _receipt = '''
SUPERMARKET FRESH MART
23/10/2026
Subtotal 44.00
TOTAL 48.20
''';

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Future<List<ExpenseRow>> _expenses(
  WidgetTester tester,
  ProviderContainer c,
) async => (await tester.runAsync(
  () =>
      c.read(databaseProvider).select(c.read(databaseProvider).expenses).get(),
))!;

Future<ProviderContainer> _open(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  ReceiptImageSource? source,
  ReceiptOcr? ocr,
  ReceiptStorage? storage,
}) => pumpApp(
  tester,
  size: size,
  location: '/scan',
  overrides: [
    receiptImageSourceProvider.overrideWithValue(source ?? _Source()),
    receiptOcrProvider.overrideWithValue(ocr ?? _Ocr(_receipt)),
    receiptStorageProvider.overrideWithValue(storage),
  ],
);

void main() {
  setUpAll(loadTestFonts);

  testWidgets('reads a receipt and shows amount, shop, date and category', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Scan receipt'), findsOneWidget);
    expect(find.text('We read this from your receipt'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('take-photo')));
    await settle(tester);
    expect(find.text('We read this from your receipt'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.textContaining('48.20'), findsOneWidget);
    expect(find.text('Supermarket Fresh Mart'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Save expense'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save expense stores the expense with the shop as its note', (
    tester,
  ) async {
    final c = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('take-photo')));
    await settle(tester);
    await _tapText(tester, 'Save expense');
    await settle(tester);
    final rows = await _expenses(tester, c);
    expect(rows, hasLength(1));
    expect(rows.single.amountCents, 4820);
    expect(rows.single.note, 'Supermarket Fresh Mart');
    expect(rows.single.spentOn, '2026-10-23');
    expect(
      rows.single.receiptPath,
      isNull,
      reason: 'the photo stays on the device by default',
    );
    expect(
      find.text('Spent this month'),
      findsOneWidget,
      reason: 'back on Home',
    );
    // The draft is clean for the next expense.
    expect(c.read(expenseFormProvider(null)).receiptImagePath, isNull);
  });

  testWidgets(
    'Change details first opens the Add form with everything filled in',
    (tester) async {
      final c = await _open(tester);
      await tester.tap(find.byKey(const ValueKey('take-photo')));
      await settle(tester);
      await _tapText(tester, 'Change details first');
      await settle(tester);
      expect(find.text('Add expense'), findsWidgets);
      final form = c.read(expenseFormProvider(null));
      expect(form.amount.cents, 4820);
      expect(form.note, 'Supermarket Fresh Mart');
      expect(find.byKey(const ValueKey('receipt-attached')), findsOneWidget);
      expect(find.textContaining('kept on this device'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(find.byKey(const ValueKey('receipt-attached')), findsNothing);
      expect(await _expenses(tester, c), isEmpty, reason: 'nothing saved yet');
    },
  );

  testWidgets('sharing uploads the photo and records its path', (tester) async {
    final storage = _Storage();
    final c = await _open(tester, storage: storage);
    await tester.tap(find.byKey(const ValueKey('take-photo')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('share-receipt')));
    await tester.tap(find.byKey(const ValueKey('share-receipt')));
    await tester.pump();
    await _tapText(tester, 'Save expense');
    await settle(tester);
    final row = (await _expenses(tester, c)).single;
    expect(storage.uploads, hasLength(1));
    expect(row.receiptPath, storage.uploads.single);
    expect(row.receiptPath, endsWith('${row.id}.jpg'));
  });

  testWidgets('without the share switch nothing is uploaded', (tester) async {
    final storage = _Storage();
    await _open(tester, storage: storage);
    await tester.tap(find.byKey(const ValueKey('take-photo')));
    await settle(tester);
    await _tapText(tester, 'Save expense');
    await settle(tester);
    expect(storage.uploads, isEmpty);
  });

  testWidgets('a failed upload still saves the expense', (tester) async {
    final c = await _open(tester, storage: _Storage(fail: true));
    await tester.tap(find.byKey(const ValueKey('take-photo')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('share-receipt')));
    await tester.tap(find.byKey(const ValueKey('share-receipt')));
    await tester.pump();
    await _tapText(tester, 'Save expense');
    await settle(tester);
    final row = (await _expenses(tester, c)).single;
    expect(row.amountCents, 4820);
    expect(row.receiptPath, isNull);
  });

  testWidgets('no share switch in local-only mode', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('take-photo')));
    await settle(tester);
    expect(find.byKey(const ValueKey('share-receipt')), findsNothing);
  });

  testWidgets('nothing readable: say so and offer the Add form', (
    tester,
  ) async {
    final c = await _open(tester, ocr: _Ocr('~~ ## ..'));
    await tester.tap(find.byKey(const ValueKey('take-photo')));
    await settle(tester);
    expect(find.byKey(const ValueKey('scan-message')), findsOneWidget);
    expect(find.text('Not found'), findsWidgets);
    expect(find.text('Save expense'), findsNothing);
    await _tapText(tester, 'Fill in the details');
    await settle(tester);
    expect(find.text('Add expense'), findsWidgets);
    expect(
      c.read(expenseFormProvider(null)).receiptImagePath,
      '/tmp/receipt.jpg',
    );
  });

  testWidgets('desktop: no camera, a file chooser, and no recogniser', (
    tester,
  ) async {
    final c = await _open(
      tester,
      size: const Size(1280, 800),
      source: _Source(camera: false),
      ocr: _Ocr('', available: false),
    );
    expect(find.byKey(const ValueKey('take-photo')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('choose-photo')));
    await settle(tester);
    expect(find.textContaining('not available on this device'), findsOneWidget);
    await _tapText(tester, 'Fill in the details');
    await settle(tester);
    expect(c.read(expenseFormProvider(null)).receiptImagePath, isNotNull);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    await _open(tester, source: _Source(path: null));
    await tester.tap(find.byKey(const ValueKey('take-photo')));
    await settle(tester);
    expect(find.text('We read this from your receipt'), findsNothing);
  });

  testWidgets('the Add form has a Scan receipt button that opens the scanner', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 844), location: '/add');
    await tester.tap(find.byKey(const ValueKey('scan-receipt')));
    await settle(tester);
    expect(find.text('Scan receipt'), findsOneWidget);
  });

  testWidgets(
    'fits and meets tap targets at phone, tablet and desktop widths',
    (tester) async {
      for (final size in const [
        Size(360, 740),
        Size(840, 900),
        Size(1280, 800),
      ]) {
        await _open(tester, size: size);
        await tester.tap(find.byKey(const ValueKey('choose-photo')));
        await settle(tester);
        expect(tester.takeException(), isNull, reason: '$size');
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
    },
  );
}
