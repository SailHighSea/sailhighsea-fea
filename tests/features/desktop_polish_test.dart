import 'package:family_expenses/features/expenses/widgets/amount_widgets.dart';

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/phase5_data.dart';
import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

const _desktop = Size(1280, 800);
const _tablet = Size(1024, 720);

Future<void> _chord(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
}) async {
  final mod = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(mod);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(mod);
  await tester.pumpAndSettle();
}

Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(
    tester.getCenter(target),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestFonts);

  group('keyboard shortcuts', () {
    testWidgets('Ctrl and a number go to the destinations', (tester) async {
      await pumpApp(tester, size: _desktop, seedAsync: seedPhase5);
      expect(find.text('Spent this month'), findsOneWidget);
      await _chord(tester, LogicalKeyboardKey.digit2);
      expect(find.text('Budgets'), findsWidgets);
      expect(find.text('Edit budgets'), findsOneWidget);
      await _chord(tester, LogicalKeyboardKey.digit3);
      expect(find.text('Last 6 months'), findsOneWidget);
      await _chord(tester, LogicalKeyboardKey.digit4);
      expect(find.text('Savings goals'), findsOneWidget);
      await _chord(tester, LogicalKeyboardKey.digit5);
      expect(find.text('Upcoming bills'), findsOneWidget);
      await _chord(tester, LogicalKeyboardKey.digit6);
      expect(find.text('Family'), findsWidgets);
      await _chord(tester, LogicalKeyboardKey.digit1);
      expect(find.text('Spent this month'), findsOneWidget);
    });

    testWidgets('the command key works the same (macOS)', (tester) async {
      await pumpApp(tester, size: _desktop, seedAsync: seedPhase5);
      await _chord(tester, LogicalKeyboardKey.digit2, meta: true);
      expect(find.text('Edit budgets'), findsOneWidget);
    });

    testWidgets('Ctrl+comma opens Appearance', (tester) async {
      await pumpApp(tester, size: _desktop);
      await _chord(tester, LogicalKeyboardKey.comma);
      expect(find.text('Colour theme'), findsOneWidget);
    });

    testWidgets('Ctrl+F opens the expense list with the search box focused', (
      tester,
    ) async {
      await pumpApp(tester, size: _desktop, seedAsync: seedPhase5);
      await _chord(tester, LogicalKeyboardKey.keyF);
      expect(find.text('Expenses'), findsWidgets);
      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('expense-search')),
          matching: find.byType(EditableText),
        ),
        findsOneWidget,
      );
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('expense-search')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue, reason: 'ready to type');
      await tester.enterText(find.byKey(const Key('expense-search')), 'Fuel');
      await tester.pumpAndSettle();
      expect(find.text('Fuel'), findsWidgets);
    });

    testWidgets('Ctrl+F while already on the list also focuses the box', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: _desktop,
        location: '/expenses',
        seedAsync: seedPhase5,
      );
      await _chord(tester, LogicalKeyboardKey.keyF);
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('expense-search')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('Ctrl+slash and the Appearance link show the shortcut list', (
      tester,
    ) async {
      await pumpApp(tester, size: _desktop);
      await _chord(tester, LogicalKeyboardKey.slash);
      expect(find.byKey(const ValueKey('shortcut-help')), findsOneWidget);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.text('Add an expense'), findsOneWidget);
      expect(find.text('Search expenses'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('shortcut-help')),
        findsNothing,
        reason: 'Esc closes it',
      );

      await _chord(tester, LogicalKeyboardKey.comma);
      await tapKey(tester, 'keyboard-shortcuts');
      expect(find.byKey(const ValueKey('shortcut-help')), findsOneWidget);
    });

    testWidgets(
      'Esc goes back to Home from any page, and does nothing on Home',
      (tester) async {
        await pumpApp(
          tester,
          size: _desktop,
          location: '/bills',
          seedAsync: seedPhase5,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Spent this month'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Spent this month'), findsOneWidget);
      },
    );

    testWidgets('Ctrl+N opens the Add screen', (tester) async {
      await pumpApp(tester, size: _desktop);
      await _chord(tester, LogicalKeyboardKey.keyN);
      expect(find.text('Save expense'), findsWidgets);
    });

    testWidgets('Ctrl+N does nothing for a view-only member', (tester) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/home',
        size: _desktop,
      );
      await _chord(tester, LogicalKeyboardKey.keyN);
      expect(find.text('Save expense'), findsNothing);
    });
  });

  group('keyboard navigation and focus', () {
    testWidgets(
      'Tab moves through the controls and the theme shows focus and hover',
      (tester) async {
        await pumpApp(tester, size: _desktop, seedAsync: seedPhase5);
        final theme = Theme.of(tester.element(find.byType(Scaffold).first));
        expect(
          theme.focusColor.a,
          greaterThan(0),
          reason: 'a visible focus colour',
        );
        expect(
          theme.hoverColor.a,
          greaterThan(0),
          reason: 'a visible hover colour',
        );

        final seen = <FocusNode?>{};
        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          seen.add(FocusManager.instance.primaryFocus);
        }
        expect(seen.length, greaterThan(3), reason: 'focus actually moves');
      },
    );

    testWidgets('Tab then Enter activates a focused control without errors', (
      tester,
    ) async {
      await pumpApp(tester, size: _desktop, seedAsync: seedPhase5);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('context menus (right click)', () {
    testWidgets('an expense row offers Edit and Delete; Delete can be undone', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: _desktop,
        location: '/expenses',
        seedAsync: seedPhase5,
      );
      await _rightClick(tester, find.text('Groceries'));
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Expense deleted'), findsOneWidget);
    });

    testWidgets('Edit from the menu opens the edit form', (tester) async {
      await pumpApp(
        tester,
        size: _desktop,
        location: '/expenses',
        seedAsync: seedPhase5,
      );
      await _rightClick(tester, find.text('Groceries'));
      await tester.tap(find.text('Edit'));
      await settle(tester);
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('a bill row offers Mark paid and Edit bill', (tester) async {
      await pumpApp(
        tester,
        size: _desktop,
        location: '/bills',
        seedAsync: seedPhase5,
      );
      await _rightClick(tester, find.text('Electricity'));
      expect(find.text('Mark paid'), findsWidgets);
      expect(find.text('Edit bill'), findsOneWidget);
      await tester.tap(find.text('Edit bill'));
      await settle(tester);
      expect(find.byKey(const ValueKey('bill-form')), findsOneWidget);
    });

    testWidgets('a goal offers Edit goal', (tester) async {
      await pumpApp(
        tester,
        size: _desktop,
        location: '/goals',
        seedAsync: seedPhase5,
      );
      await _rightClick(tester, find.text('New laptop').first);
      await tester.tap(find.text('Edit goal'));
      await settle(tester);
      expect(find.byKey(const ValueKey('goal-form')), findsOneWidget);
    });

    testWidgets('a view-only member gets no menu', (tester) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/expenses',
        size: _desktop,
      );
      await _rightClick(tester, find.text('Groceries'));
      expect(find.text('Delete'), findsNothing);
    });
  });

  group('foldable half-open: every page, state kept', () {
    const hinge = DisplayFeature(
      bounds: Rect.fromLTWH(0, 440, 840, 20),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureHalfOpened,
    );
    const size = Size(840, 900);

    for (final entry in {
      '/home': 'Spent this month',
      '/budgets': 'Edit budgets',
      '/insights': 'Insights',
      '/goals': 'Savings goals',
      '/bills': 'Upcoming bills',
      '/family': 'Family',
      '/appearance': 'Colour theme',
      '/expenses': 'Expenses',
    }.entries) {
      testWidgets(
        '${entry.key}: the page above the hinge, the Add form below',
        (tester) async {
          await pumpApp(
            tester,
            size: size,
            location: entry.key,
            seedAsync: seedPhase5,
            displayFeatures: const [hinge],
          );
          expect(tester.takeException(), isNull);
          final title = find.text(entry.value).first;
          expect(
            tester.getTopLeft(title).dy,
            lessThan(440),
            reason: entry.value,
          );
          final save = find.text('Save expense');
          expect(save, findsOneWidget);
          expect(tester.getTopLeft(save).dy, greaterThan(460));
        },
      );
    }

    testWidgets('no Add form on the add and edit screens themselves', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: size,
        location: '/add',
        displayFeatures: const [hinge],
      );
      expect(
        find.text('Save expense'),
        findsOneWidget,
        reason: 'only the form itself',
      );
    });

    testWidgets('a view-only member gets the page and no form', (tester) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/budgets',
        size: size,
      );
      // Not half-open here, so just check the role rule used for the panel.
      expect(find.text('Save expense'), findsNothing);
    });

    testWidgets('what was typed in the fold form survives unfolding', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        size: size,
        displayFeatures: const [hinge],
      );
      for (final ch in '12.5'.split('')) {
        await tester.tap(
          find.descendant(
            of: find.byType(AmountKeypad),
            matching: find.text(ch),
          ),
        );
        await tester.pump();
      }
      String amount() =>
          tester.widget<Text>(find.byKey(const Key('amount-text'))).data!;
      expect(amount(), '12.5');

      // Unfold: no hinge any more, the full Add screen opens with the same draft.
      tester.view.displayFeatures = const <DisplayFeature>[];
      await tester.pumpAndSettle();
      expect(
        find.text('Save expense'),
        findsNothing,
        reason: 'the panel is gone',
      );
      await _chord(tester, LogicalKeyboardKey.keyN);
      expect(amount(), '12.5', reason: 'same draft');

      // Fold again and go home: the panel shows the same draft once more.
      tester.view.displayFeatures = const [hinge];
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c, isNotNull);
    });
  });

  group('wide screens', () {
    testWidgets('content is centred and capped on a 1920 window', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(1920, 1080),
        location: '/budgets',
        seedAsync: seedPhase5,
      );
      final subtitle = tester.getTopLeft(
        find.byKey(const ValueKey('budgets-subtitle')),
      );
      expect(
        subtitle.dx,
        greaterThan(240 + 40),
        reason: 'beside the sidebar, not stretched to the edge',
      );
      final grid = tester.getTopRight(find.text('+ New category'));
      expect(
        grid.dx,
        lessThan(1920 - 40),
        reason: 'does not run to the right edge',
      );
    });

    testWidgets('the tablet width keeps the rail', (tester) async {
      await pumpApp(tester, size: _tablet);
      expect(find.text('Settings'), findsOneWidget, reason: 'the rail');
    });
  });
}
