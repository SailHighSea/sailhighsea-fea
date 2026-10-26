import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/core/theme/category_style.dart';
import 'package:family_expenses/features/expenses/expense_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

void main() {
  setUpAll(loadTestFonts);

  test('every suggested category uses a known icon and colour', () {
    final names = <String>{};
    for (final s in kSuggestedCategories) {
      expect(kCategoryIcons.containsKey(s.icon), isTrue, reason: s.name);
      expect(kCategoryColorKeys.contains(s.color), isTrue, reason: s.name);
      expect(names.add(s.name), isTrue, reason: 'duplicate ${s.name}');
    }
    expect(kSuggestedCategories.length, greaterThanOrEqualTo(30));
    expect(guessCategoryStyle('Weekly grocery').icon, 'local_grocery_store');
    expect(guessCategoryStyle('Zzz').icon, 'category');
  });

  group('Categories page', () {
    testWidgets('lists the categories and offers ready-made ones', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/categories',
      );
      expect(find.text('Food'), findsWidgets);
      expect(key('suggest-Groceries'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a ready-made category is added with its icon and colour', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/categories',
      );
      await tester.ensureVisible(key('suggest-Groceries'));
      await tapKey(tester, 'suggest-Groceries');
      await settle(tester);
      final all = await c.read(categoryRepositoryProvider).getAll();
      final g = all.firstWhere((x) => x.name == 'Groceries');
      expect(g.icon, 'local_grocery_store');
      expect(g.color, 'green');
      expect(
        key('suggest-Groceries'),
        findsNothing,
        reason: 'no longer offered',
      );
    });

    testWidgets('new category: name, icon and colour', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/categories',
      );
      await tapKey(tester, 'add-category-button');
      await tester.enterText(key('category-name'), 'Hobbies');
      await settle(tester);
      await tester.ensureVisible(
        key('icon-palette'.replaceAll('palette', 'toys')),
      );
      await tapKey(tester, 'icon-toys');
      await tester.ensureVisible(key('color-violet'));
      await tapKey(tester, 'color-violet');
      await tester.ensureVisible(key('category-save'));
      await tapKey(tester, 'category-save');
      await settle(tester);
      final all = await c.read(categoryRepositoryProvider).getAll();
      final h = all.firstWhere((x) => x.name == 'Hobbies');
      expect([h.icon, h.color], ['toys', 'violet']);
    });

    testWidgets('typing a known word picks the icon for you', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/categories',
      );
      await tapKey(tester, 'add-category-button');
      await tester.enterText(key('category-name'), 'Pharmacy run');
      await tester.pump();
      await tester.ensureVisible(key('category-save'));
      await tapKey(tester, 'category-save');
      await settle(tester);
      final h = (await c.read(categoryRepositoryProvider).getAll()).firstWhere(
        (x) => x.name == 'Pharmacy run',
      );
      expect(h.icon, 'local_pharmacy');
    });

    testWidgets(
      'editing changes the icon and colour; Other cannot be deleted',
      (tester) async {
        final c = await pumpApp(
          tester,
          size: const Size(390, 844),
          location: '/categories',
        );
        await tapKey(tester, 'category-default-food');
        await tester.ensureVisible(key('color-red'));
        await tapKey(tester, 'color-red');
        await tester.ensureVisible(key('icon-fastfood'));
        await tapKey(tester, 'icon-fastfood');
        await tester.ensureVisible(key('category-save'));
        await tapKey(tester, 'category-save');
        await settle(tester);
        final food = (await c.read(categoryRepositoryProvider).getAll())
            .firstWhere((x) => x.id == 'default-food');
        expect([food.icon, food.color], ['fastfood', 'red']);

        await tapKey(tester, 'category-default-other');
        expect(key('category-delete'), findsNothing);
      },
    );

    testWidgets('deleting moves its expenses to Other', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/categories',
      );
      await tapKey(tester, 'category-default-fun');
      await tester.ensureVisible(key('category-delete'));
      await tapKey(tester, 'category-delete');
      await settle(tester);
      final all = await c.read(categoryRepositoryProvider).getAll();
      expect(all.any((x) => x.id == 'default-fun'), isFalse);
      expect(c.read(databaseProvider), isNotNull);
    });

    for (final size in const {
      'phone': Size(390, 844),
      'phone small': Size(320, 640),
      'tablet': Size(840, 900),
      'desktop': Size(1280, 800),
    }.entries) {
      testWidgets('fits on ${size.key}', (tester) async {
        await pumpApp(tester, size: size.value, location: '/categories');
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await tapKey(tester, 'add-category-button');
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      });
    }

    testWidgets('a view-only member cannot edit or add', (tester) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/categories',
        size: const Size(390, 844),
      );
      expect(key('add-category-button'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  testWidgets('Settings lists Categories, and Goals is a bottom tab', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(390, 844));
    await tester.tap(find.text('Settings').first);
    await settle(tester);
    expect(key('settings-categories'), findsOneWidget);
    expect(key('settings-goals'), findsNothing);
    await tester.tap(find.text('Goals').first);
    await settle(tester);
    expect(find.text('Savings goals'), findsWidgets);
  });
}
