import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/features/expenses/data/day_format.dart';
import 'package:family_expenses/features/expenses/expense_providers.dart';
import 'package:family_expenses/features/expenses/widgets/amount_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

const _phone = Size(390, 844);
const _tablet = Size(1024, 720);
const _desktop = Size(1280, 800);

Finder _key(String label) => find.descendant(of: find.byType(AmountKeypad), matching: find.text(label));

Future<void> _typeAmount(WidgetTester tester, String amount) async {
  for (final ch in amount.split('')) {
    await tester.tap(_key(ch));
    await tester.pump();
  }
}

String _amountShown(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('amount-text'))).data!;

Future<List<ExpenseRow>> _expenses(WidgetTester tester, ProviderContainer c) async {
  final rows = await tester.runAsync(() => c.read(databaseProvider).select(c.read(databaseProvider).expenses).get());
  return rows!;
}

Future<String> _seed(
  WidgetTester tester,
  ProviderContainer c, {
  required int cents,
  required String day,
  String category = 'default-food',
  String note = '',
  String? by,
}) async {
  final id = await tester.runAsync(
    () => c
        .read(expenseRepositoryProvider)
        .add(amountCents: cents, categoryId: category, spentOn: parseDay(day), note: note, createdBy: by),
  );
  await tester.pumpAndSettle();
  return id!;
}

Future<void> _pressCtrlN(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestFonts);

  group('add an expense (same flow on every size)', () {
    for (final entry in {'phone': _phone, 'tablet': _tablet, 'desktop': _desktop}.entries) {
      testWidgets('${entry.key}: keypad, category, note, save', (tester) async {
        final c = await pumpApp(tester, size: entry.value);
        await tester.tap(find.text(entry.key == 'phone' ? '+ Add' : '+ Add expense'));
        await tester.pumpAndSettle();

        expect(find.text('Add expense'), findsOneWidget, reason: 'form title');
        expect(_amountShown(tester), '0');

        await _typeAmount(tester, '48.20');
        expect(_amountShown(tester), '48.20');

        await tester.tap(find.text('Transport'));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('note-field')), 'Groceries');
        await tester.pump();
        await tester.tap(find.text('Save expense'));
        await tester.pumpAndSettle();

        final rows = await _expenses(tester, c);
        expect(rows, hasLength(1));
        expect(rows.single.amountCents, 4820);
        expect(rows.single.categoryId, 'default-transport');
        expect(rows.single.note, 'Groceries');
        expect(rows.single.spentOn, formatDay(kTestNow));
        expect(rows.single.createdBy, 'You');
        expect(rows.single.dirty, isTrue);

        // Back on Home, and Home already shows the new expense from the database.
        expect(find.text('Add expense'), findsNothing);
        expect(find.text('S\$48'), findsWidgets);
        expect(find.text('Groceries'), findsWidgets);
      });
    }
  });

  testWidgets('saving without an amount shows an error and saves nothing', (tester) async {
    final c = await pumpApp(tester, size: _phone, location: '/add');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(await _expenses(tester, c), isEmpty);
    expect(find.text('Add expense'), findsWidgets, reason: 'still on the form');

    await _typeAmount(tester, '5');
    expect(find.text('Enter an amount'), findsNothing, reason: 'typing clears the error');
  });

  testWidgets('the first category is used when none is picked', (tester) async {
    final c = await pumpApp(tester, size: _tablet, location: '/add');
    await _typeAmount(tester, '12');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect((await _expenses(tester, c)).single.categoryId, 'default-food');
  });

  testWidgets('a hardware keyboard types the amount', (tester) async {
    await pumpApp(tester, size: _desktop, location: '/add');
    Future<void> press(LogicalKeyboardKey key, String ch) async {
      await tester.sendKeyDownEvent(key, character: ch);
      await tester.sendKeyUpEvent(key);
      await tester.pump();
    }

    await press(LogicalKeyboardKey.digit1, '1');
    await press(LogicalKeyboardKey.digit2, '2');
    await press(LogicalKeyboardKey.period, '.');
    await press(LogicalKeyboardKey.digit5, '5');
    expect(_amountShown(tester), '12.5');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(_amountShown(tester), '12.');
  });

  testWidgets('Ctrl+Enter saves from the keyboard', (tester) async {
    final c = await pumpApp(tester, size: _desktop, location: '/add');
    await _typeAmount(tester, '9');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect((await _expenses(tester, c)).single.amountCents, 900);
  });

  testWidgets('Ctrl+N opens Add from anywhere', (tester) async {
    await pumpApp(tester, size: _desktop);
    expect(find.text('Add expense'), findsNothing);
    await _pressCtrlN(tester);
    expect(find.text('Add expense'), findsOneWidget);
    expect(find.textContaining('Ctrl or Cmd + N'), findsOneWidget, reason: 'desktop shows the shortcut tip');

    // Esc closes it again.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsNothing);
  });

  testWidgets('Ctrl+N works from the Appearance page too', (tester) async {
    await pumpApp(tester, size: _tablet, location: '/appearance');
    await _pressCtrlN(tester);
    expect(find.text('Add expense'), findsOneWidget);
  });

  testWidgets('a new category can be added and used', (tester) async {
    final c = await pumpApp(tester, size: _phone, location: '/add');
    await tester.tap(find.text('+ New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-category-field')), 'Pets');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Pets'), findsOneWidget);

    await _typeAmount(tester, '30');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    final db = c.read(databaseProvider);
    final pets = await tester.runAsync(() => (db.select(db.categories)..where((x) => x.name.equals('Pets'))).getSingle());
    expect((await _expenses(tester, c)).single.categoryId, pets!.id);
  });

  testWidgets('the date can be changed', (tester) async {
    final c = await pumpApp(tester, size: _phone, location: '/add');
    expect(find.text('Today, 23 Oct'), findsOneWidget);
    await tester.tap(find.byKey(const Key('date-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('20 Oct'), findsOneWidget);

    await _typeAmount(tester, '7');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect((await _expenses(tester, c)).single.spentOn, '2026-10-20');
  });

  group('edit', () {
    testWidgets('opens with the saved values and saves changes', (tester) async {
      final c = await pumpApp(tester, size: _tablet, location: '/expenses');
      final id = await _seed(tester, c, cents: 4820, day: '2026-10-22', category: 'default-bills', note: 'Phone bill');

      await tester.tap(find.text('Phone bill').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit expense'), findsOneWidget);
      expect(_amountShown(tester), '48.20');
      expect(tester.widget<TextField>(find.byKey(const Key('note-field'))).controller!.text, 'Phone bill');
      expect(find.text('Yesterday, 22 Oct'), findsOneWidget);

      // Replace the amount: backspace everything, then type 60.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.descendant(of: find.byType(AmountKeypad), matching: find.byIcon(Icons.backspace_outlined)));
        await tester.pump();
      }
      await _typeAmount(tester, '60');
      await tester.tap(find.text('Fun'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final row = (await _expenses(tester, c)).single;
      expect(row.id, id);
      expect(row.amountCents, 6000);
      expect(row.categoryId, 'default-fun');
      expect(row.note, 'Phone bill');
      expect(row.updatedAt, kTestNow);
      expect(find.text('Edit expense'), findsNothing, reason: 'closed after saving');
      expect(find.text('Expenses'), findsWidgets, reason: 'back on the list');
    });

    testWidgets('close without saving changes nothing', (tester) async {
      final c = await pumpApp(tester, size: _phone, location: '/expenses');
      await _seed(tester, c, cents: 500, day: '2026-10-22', note: 'Lunch');
      await tester.tap(find.text('Lunch').first);
      await tester.pumpAndSettle();
      await _typeAmount(tester, '9');
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect((await _expenses(tester, c)).single.amountCents, 500);
    });
  });

  group('expense list', () {
    testWidgets('shows the month, total and who added each', (tester) async {
      final c = await pumpApp(tester, size: _tablet, location: '/expenses');
      expect(find.text('No expenses this month'), findsOneWidget);
      await _seed(tester, c, cents: 4820, day: '2026-10-23', note: 'Groceries', by: 'Maya');
      await _seed(tester, c, cents: 2000, day: '2026-10-22', category: 'default-transport', note: 'MRT top-up');
      await _seed(tester, c, cents: 999, day: '2026-09-15', note: 'September lunch');

      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('September lunch'), findsNothing, reason: 'other month');
      expect(find.text('S\$68.20 · 2 expenses'), findsOneWidget);
      expect(find.text('Food · Today · Maya'), findsOneWidget);
      expect(find.text('Transport · Yesterday · You'), findsOneWidget);
      expect(find.text('-S\$48.20'), findsOneWidget);
    });

    testWidgets('search and category filter', (tester) async {
      final c = await pumpApp(tester, size: _phone, location: '/expenses');
      await _seed(tester, c, cents: 4820, day: '2026-10-23', note: 'Groceries');
      await _seed(tester, c, cents: 2000, day: '2026-10-22', category: 'default-transport', note: 'MRT top-up');
      await _seed(tester, c, cents: 1998, day: '2026-10-21', category: 'default-fun', note: 'Streaming plan');

      await tester.enterText(find.byKey(const Key('expense-search')), 'groc');
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('MRT top-up'), findsNothing);

      // Search also matches the category name.
      await tester.enterText(find.byKey(const Key('expense-search')), 'transport');
      await tester.pumpAndSettle();
      expect(find.text('MRT top-up'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);

      await tester.enterText(find.byKey(const Key('expense-search')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No expenses match your search'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Category Fun'));
      await tester.pumpAndSettle();
      expect(find.text('Streaming plan'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);

      await tester.tap(find.bySemanticsLabel('All categories'));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('MRT top-up'), findsOneWidget);
    });

    testWidgets('month navigation changes what is listed', (tester) async {
      final c = await pumpApp(tester, size: _tablet, location: '/expenses');
      await _seed(tester, c, cents: 999, day: '2026-09-15', note: 'September lunch');
      await _seed(tester, c, cents: 500, day: '2026-10-01', note: 'October lunch');
      expect(find.text('October lunch'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('September lunch'), findsOneWidget);
      expect(find.text('October lunch'), findsNothing);
    });

    testWidgets('delete from the menu is soft and can be undone', (tester) async {
      final c = await pumpApp(tester, size: _desktop, location: '/expenses');
      final id = await _seed(tester, c, cents: 4820, day: '2026-10-23', note: 'Groceries');

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Expense deleted'), findsOneWidget);
      var rows = await _expenses(tester, c);
      expect(rows.single.id, id, reason: 'the row is kept (soft delete)');
      expect(rows.single.deletedAt, isNotNull);
      expect(rows.single.dirty, isTrue);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      rows = await _expenses(tester, c);
      expect(rows.single.deletedAt, isNull);
    });

    testWidgets('swipe to delete, then undo', (tester) async {
      final c = await pumpApp(tester, size: _phone, location: '/expenses');
      await _seed(tester, c, cents: 1000, day: '2026-10-23', note: 'Swipe me');
      await tester.drag(find.text('Swipe me'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Swipe me'), findsNothing);
      expect((await _expenses(tester, c)).single.deletedAt, isNotNull);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Swipe me'), findsOneWidget);
    });
  });

  group('Home with real data', () {
    testWidgets('shows totals from the database and updates live', (tester) async {
      final c = await pumpApp(tester, size: _tablet);
      expect(find.text('No spending yet this month'), findsOneWidget);

      await _seed(tester, c, cents: 61200, day: '2026-10-05', note: 'Big shop');
      await _seed(tester, c, cents: 7200, day: '2026-10-23', category: 'default-bills', note: 'Phone');

      // Spent 684, today 72, budget 2,500.
      expect(find.text('S\$684'), findsOneWidget);
      expect(find.text('of S\$2,500 · S\$1,816 left'), findsOneWidget);
      expect(find.text('27%'), findsOneWidget);
      expect(find.text('S\$72'), findsOneWidget, reason: 'today');
      expect(find.text('Food'), findsWidgets);
      expect(find.text('Big shop'), findsOneWidget);
      expect(find.text('Nothing due'), findsOneWidget, reason: 'bills arrive in Phase 5');
    });

    testWidgets('month navigation moves between months and back', (tester) async {
      final c = await pumpApp(tester, size: _phone);
      await _seed(tester, c, cents: 12300, day: '2026-09-10', note: 'September shop');
      await _seed(tester, c, cents: 4500, day: '2026-10-10', note: 'October shop');
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('S\$45'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('S\$123'), findsWidgets);
      expect(find.text('September shop'), findsOneWidget);
      expect(find.text('October shop'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('No spending yet this month'), findsOneWidget);
    });
  });

  group('foldable half-open', () {
    const hinge = DisplayFeature(
      bounds: Rect.fromLTWH(0, 440, 840, 20),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureHalfOpened,
    );

    testWidgets('dashboard above the hinge, add form below, and it saves', (tester) async {
      final c = await pumpApp(tester, size: const Size(840, 900), displayFeatures: const [hinge]);

      expect(tester.getBottomLeft(find.text('Spent this month')).dy, lessThan(440));
      final form = find.text('Save expense');
      expect(form, findsOneWidget);
      expect(tester.getTopLeft(form).dy, greaterThan(460));

      await _typeAmount(tester, '15.5');
      await tester.tap(find.text('Save expense'));
      await tester.pumpAndSettle();
      expect((await _expenses(tester, c)).single.amountCents, 1550);
      // The panel is ready for the next one.
      expect(_amountShown(tester), '0');
    });

    testWidgets('no hinge, no panel', (tester) async {
      await pumpApp(tester, size: const Size(840, 900));
      expect(find.text('Save expense'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('keypad keys, category tiles and month arrows are at least 44px', (tester) async {
      await pumpApp(tester, size: _phone, location: '/add');
      final keys = find.descendant(of: find.byType(AmountKeypad), matching: find.byType(InkWell));
      expect(keys, findsNWidgets(12));
      for (final k in keys.evaluate()) {
        final size = tester.getSize(find.byWidget(k.widget));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      for (final name in ['Food', 'Bills', '+ New']) {
        final size = tester.getSize(find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first);
        expect(size.height, greaterThanOrEqualTo(44), reason: name);
      }
    });

    testWidgets('large text does not overflow the add form or the list', (tester) async {
      await pumpApp(tester, size: const Size(360, 800), location: '/add', textScale: 2);
      expect(tester.takeException(), isNull);
      await pumpApp(tester, size: const Size(360, 800), location: '/expenses', textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
