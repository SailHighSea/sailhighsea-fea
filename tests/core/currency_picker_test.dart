import 'package:family_expenses/core/money/currency.dart';
import 'package:family_expenses/core/money/money_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  setUpAll(loadTestFonts);

  group('the list of currencies', () {
    test(
      'every ISO code once, three letters, a name, and the usual decimals',
      () {
        final codes = supportedCurrencies.map((c) => c.code).toList();
        expect(codes.toSet().length, codes.length, reason: 'no duplicates');
        expect(codes.length, greaterThan(140));
        for (final c in supportedCurrencies) {
          expect(
            RegExp(r'^[A-Z]{3}$').hasMatch(c.code),
            isTrue,
            reason: c.code,
          );
          expect(c.name, isNotEmpty);
          expect(c.symbol, isNotEmpty);
          expect(c.minorDigits, inInclusiveRange(0, 3));
        }
        expect(currencyByCode('JPY').minorDigits, 0);
        expect(currencyByCode('KRW').minorDigits, 0);
        expect(currencyByCode('KWD').minorDigits, 3);
        expect(currencyByCode('USD').minorDigits, 2);
        expect(
          currencyByCode('SGD'),
          supportedCurrencies.first,
          reason: 'the default stays first',
        );
      },
    );

    test('money is exact in every currency, with integer maths', () {
      for (final c in supportedCurrencies) {
        final f = MoneyFormatter(c, locale: 'en_US');
        final cents = c.minorFactor * 1234 + (c.minorFactor > 1 ? 5 : 0);
        final text = f.format(cents);
        expect(text, contains('1,234'), reason: c.code);
        if (c.minorDigits > 0) {
          expect(
            text,
            endsWith('.${'5'.padLeft(c.minorDigits, '0')}'),
            reason: c.code,
          );
        }
        expect(f.format(-cents), startsWith('-'), reason: c.code);
      }
    });

    test('letter-only symbols get a space, short ones stay tight', () {
      MoneyFormatter f(String code) =>
          MoneyFormatter(currencyByCode(code), locale: 'en_US');
      expect(f('CHF').format(1250), 'CHF 12.50');
      expect(f('AED').format(1250), 'AED 12.50');
      expect(f('MYR').format(1250), 'RM12.50');
      expect(f('SGD').format(1250), r'S$12.50');
      expect(f('EUR').format(1250), '€12.50');
      expect(f('JPY').format(1250), '¥1,250');
    });
  });

  group('the picker', () {
    Future<String?> open(
      WidgetTester tester, {
      Size size = const Size(390, 844),
    }) async {
      String? picked = 'unset';
      await pumpApp(tester, size: size, location: '/appearance');
      await tester.tap(find.byKey(const ValueKey('currency-row')));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets(
      'scrolls all the way down on a phone and picks the last currency',
      (tester) async {
        await open(tester);
        expect(find.byKey(const ValueKey('currency-sheet')), findsOneWidget);
        expect(find.byKey(const ValueKey('currency-SGD')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('currency-ZWL')),
          findsNothing,
          reason: 'off screen until scrolled',
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('currency-ZWL')),
          300,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('currency-list')),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('currency-ZWL')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('currency-sheet')), findsNothing);
        expect(find.textContaining('Zimbabwean dollar'), findsOneWidget);
      },
    );

    testWidgets(
      'search by name, code or symbol, and a message when nothing matches',
      (tester) async {
        await open(tester);
        await tester.enterText(
          find.byKey(const ValueKey('currency-search')),
          'yen',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('currency-JPY')), findsOneWidget);
        expect(find.byKey(const ValueKey('currency-EUR')), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('currency-search')),
          'chf',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('currency-CHF')), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('currency-search')),
          '€',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('currency-EUR')), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('currency-search')),
          'zzzz',
        );
        await tester.pump();
        expect(find.text('No currency matches'), findsOneWidget);
      },
    );

    testWidgets('picking changes the app currency and every amount', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/appearance',
      );
      await tester.tap(find.byKey(const ValueKey('currency-row')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('currency-search')),
        'qatar',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('currency-QAR')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Qatari riyal'), findsWidgets);
      expect(c, isNotNull);
    });

    testWidgets(
      'fits, scrolls and meets tap targets on phone, tablet and desktop',
      (tester) async {
        for (final size in const [
          Size(360, 640),
          Size(840, 900),
          Size(1280, 800),
        ]) {
          await open(tester, size: size);
          expect(tester.takeException(), isNull, reason: '$size');
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await tester.tapAt(const Offset(2, 2));
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets('with large text the list still scrolls', (tester) async {
      await pumpApp(
        tester,
        size: const Size(360, 740),
        location: '/appearance',
        textScale: 2,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('currency-row')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('currency-row')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('currency-list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
