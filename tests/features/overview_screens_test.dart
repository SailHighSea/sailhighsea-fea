import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:family_expenses/features/overview/overview_providers.dart';
import 'package:family_expenses/core/widgets/segmented_pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

const _phone = Size(390, 844);
const _tablet = Size(1024, 720);
const _desktop = Size(1280, 900);
const _sizes = {'phone': _phone, 'tablet': _tablet, 'desktop': _desktop};

Future<void> _openEveryone(WidgetTester tester) async {
  await tapKey(tester, 'see-everyone');
}

void main() {
  setUpAll(loadTestFonts);

  group('Family: what a member can see', () {
    testWidgets(
      'the owner chooses "Only their own" for an editor and a Private tag appears',
      (tester) async {
        final c = await pumpAsMember(
          tester,
          me: ownerUser,
          location: '/family',
          size: _tablet,
          seed: false,
        );
        expect(key('private-user-ed'), findsNothing);
        await tapKey(tester, 'role-button-user-ed');
        expect(find.text('Can see'), findsOneWidget);
        expect(key('visibility-option-household'), findsOneWidget);
        await tapKey(tester, 'visibility-option-own');
        expect(
          find.textContaining('Ed now sees only their own spending'),
          findsOneWidget,
        );
        expect(key('private-user-ed'), findsOneWidget);
        final remote = c.read(householdRemoteProvider)! as FakeHouseholdRemote;
        expect(remote.calls, contains('set-visibility:user-ed:own'));
      },
    );

    testWidgets('and back to everyone\'s spending', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/family',
        size: _tablet,
        seed: false,
        ownOnly: {'user-sam'},
      );
      expect(key('private-user-sam'), findsOneWidget);
      await tapKey(tester, 'role-button-user-sam');
      await tapKey(tester, 'visibility-option-household');
      expect(
        find.textContaining("Sam now sees everyone's spending"),
        findsOneWidget,
      );
      expect(key('private-user-sam'), findsNothing);
    });

    testWidgets('an admin can do it too', (tester) async {
      await pumpAsMember(
        tester,
        me: adminUser,
        location: '/family',
        size: _tablet,
        seed: false,
      );
      await tapKey(tester, 'role-button-user-sam');
      expect(find.text('Can see'), findsOneWidget);
    });

    testWidgets(
      'there is nothing to choose for an admin: they always see everything',
      (tester) async {
        await pumpAsMember(
          tester,
          me: ownerUser,
          location: '/family',
          size: _tablet,
          seed: false,
        );
        await tapKey(tester, 'role-button-user-maya');
        expect(find.text('Can see'), findsNothing);
        expect(key('visibility-option-own'), findsNothing);
      },
    );

    testWidgets('a view-only member has no way to open the sheet', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/family',
        size: _tablet,
        seed: false,
      );
      expect(key('role-button-user-ed'), findsNothing);
      expect(find.text('Can see'), findsNothing);
    });

    testWidgets('the server says no: the person is told', (tester) async {
      final c = await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/family',
        size: _tablet,
        seed: false,
      );
      (c.read(householdRemoteProvider)! as FakeHouseholdRemote).actingUserId =
          viewerUser;
      await tapKey(tester, 'role-button-user-ed');
      await tapKey(tester, 'visibility-option-own');
      expect(find.text('Your role does not allow that.'), findsOneWidget);
      expect(key('private-user-ed'), findsNothing);
    });

    testWidgets(
      'the Private tag is visible to everyone and does not break the row',
      (tester) async {
        await pumpAsMember(
          tester,
          me: viewerUser,
          location: '/family',
          size: _phone,
          seed: false,
          ownOnly: {'user-ed'},
          textScale: 2,
        );
        expect(key('private-user-ed'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('the owner\'s overview', () {
    for (final entry in _sizes.entries) {
      testWidgets('${entry.key}: every member with their month', (
        tester,
      ) async {
        await pumpAsMember(
          tester,
          me: ownerUser,
          location: '/home',
          size: entry.value,
        );
        expect(key('see-everyone'), findsOneWidget);
        expect(
          find.textContaining('4 members · S\$1,842 this month'),
          findsOneWidget,
        );
        await _openEveryone(tester);
        expect(find.text('Everyone spent'), findsOneWidget);
        expect(find.text('S\$1,842'), findsWidgets);
        expect(find.text('of S\$2,500 · S\$658 left'), findsOneWidget);
        expect(find.text('Who spent what'), findsOneWidget);
        for (final name in ['You', 'Maya', 'Sam', 'Ed']) {
          expect(find.text(name), findsWidgets, reason: name);
        }
        expect(find.text('S\$1,132'), findsWidgets);
        expect(find.text('61%'), findsOneWidget);
        expect(find.text('27%'), findsOneWidget);
        expect(find.text('12%'), findsOneWidget);
        expect(
          find.text('Most on Food'),
          findsOneWidget,
          reason: 'You: Food 612',
        );
        expect(find.text('No spending yet'), findsOneWidget, reason: 'Ed');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('it is also a tab on the Insights page', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/insights',
        size: _tablet,
      );
      expect(find.text('Everyone'), findsOneWidget);
      expect(
        find.text('Last 6 months'),
        findsOneWidget,
        reason: 'charts first',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedPills),
          matching: find.text('Everyone'),
        ),
      );
      await settle(tester);
      expect(find.text('Everyone spent'), findsOneWidget);
      expect(find.text('Last 6 months'), findsNothing);
      final tabs = find.byType(SegmentedPills);
      await tester.tap(
        find.descendant(of: tabs, matching: find.text('Insights')),
      );
      await settle(tester);
      expect(find.text('Last 6 months'), findsOneWidget);
    });

    testWidgets('the month arrows change the month', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _tablet,
      );
      await _openEveryone(tester);
      await tester.tap(find.bySemanticsLabel('Previous month'));
      await settle(tester);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('Everyone spent'), findsOneWidget);
    });

    testWidgets('tapping a person shows Home for just them', (tester) async {
      final c = await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _tablet,
      );
      await _openEveryone(tester);
      await tapKey(tester, 'person-user-sam');
      expect(c.read(memberFilterProvider), 'user-sam');
      expect(find.text('Spent this month'), findsOneWidget, reason: 'on Home');
      expect(find.text('S\$216'), findsWidgets);
      expect(
        find.text('S\$1,842'),
        findsNothing,
        reason: 'the family total is no longer shown',
      );
      expect(find.text('Gift'), findsOneWidget, reason: "Sam's own entry");
      expect(find.text('Groceries'), findsNothing, reason: "You's entry");
    });

    testWidgets('large text does not overflow on the phone', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _phone,
        textScale: 2,
      );
      await _openEveryone(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('member filter', () {
    testWidgets('chips change every number on Home, and back', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _tablet,
      );
      expect(find.text('S\$1,842'), findsWidgets);
      await tapKey(tester, 'member-chip-user-maya');
      expect(find.text('S\$494'), findsWidgets);
      expect(find.text('S\$1,842'), findsNothing);
      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      await tapKey(tester, 'member-chip-user-you');
      expect(find.text('S\$1,132'), findsWidgets);
      await tapKey(tester, 'member-chip-all');
      expect(find.text('S\$1,842'), findsWidgets);
    });

    testWidgets('the same filter applies to the expense list', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/expenses',
        size: _tablet,
      );
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Fuel'), findsOneWidget);
      await tapKey(tester, 'member-chip-user-maya');
      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('Cinema'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.text('Gift'), findsNothing);
    });

    testWidgets(
      'Home keeps the same layout with a filter on (only data changes)',
      (tester) async {
        await pumpAsMember(
          tester,
          me: ownerUser,
          location: '/home',
          size: _tablet,
        );
        List<String> sections() => [
          for (final t in [
            'Spent this month',
            'Top categories',
            'Next bill',
            'Recent',
          ])
            if (find.textContaining(t).evaluate().isNotEmpty) t,
        ];
        final before = sections();
        await tapKey(tester, 'member-chip-user-sam');
        expect(sections(), before);
      },
    );

    testWidgets('chips are big enough to tap', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _phone,
      );
      for (final k in [
        'member-chip-all',
        'member-chip-user-you',
        'member-chip-user-maya',
      ]) {
        expect(
          tester.getSize(key(k)).height,
          greaterThanOrEqualTo(44),
          reason: k,
        );
      }
    });

    testWidgets('a view-only member with household visibility can use it', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/home',
        size: _tablet,
      );
      expect(key('member-filter'), findsOneWidget);
      expect(key('see-everyone'), findsOneWidget);
    });
  });

  group('a member who only sees their own spending', () {
    testWidgets('has no overview, no filter and no Everyone tab', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: 'user-ed',
        location: '/home',
        size: _tablet,
        ownOnly: {'user-ed'},
      );
      expect(key('see-everyone'), findsNothing);
      expect(key('member-filter'), findsNothing);
      await tester.tap(find.text('Insights').first);
      await settle(tester);
      expect(find.text('Everyone'), findsNothing);
    });

    testWidgets(
      'sees only their own on every screen, even if others were cached before',
      (tester) async {
        // The seeded device holds everyone's rows (as if pulled before the setting changed).
        final c = await pumpAsMember(
          tester,
          me: 'user-ed',
          location: '/home',
          size: _tablet,
          ownOnly: {'user-ed'},
        );
        final db = c.read(databaseProvider);
        final left = await tester.runAsync(() => db.select(db.expenses).get());
        expect(
          left,
          isEmpty,
          reason: 'the others\' rows were removed when the app saw the setting',
        );
        expect(find.text('S\$1,842'), findsNothing);
        expect(find.text('Groceries'), findsNothing);
        await tester.tap(find.text('Insights').first);
        await settle(tester);
        expect(find.text('S\$1,842'), findsNothing);
        expect(find.text('Maya'), findsNothing);
      },
    );

    testWidgets('household visibility: the editor still sees everyone', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: 'user-ed',
        location: '/home',
        size: _tablet,
      );
      expect(find.text('S\$1,842'), findsWidgets);
      expect(key('see-everyone'), findsOneWidget);
    });
  });

  group('allowances', () {
    testWidgets('the owner sets one and sees what is left', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _tablet,
      );
      await _openEveryone(tester);
      expect(find.text('Set allowance'), findsNWidgets(4));
      await tapKey(tester, 'allowance-button-user-sam');
      expect(key('allowance-sheet'), findsOneWidget);
      await enterKey(tester, 'allowance-amount', '300');
      await tapKey(tester, 'allowance-save');
      expect(
        find.text('S\$216 of S\$300 allowance · S\$84 left'),
        findsOneWidget,
      );
      expect(find.text('Change allowance'), findsOneWidget);
    });

    testWidgets('over the allowance is said plainly', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _tablet,
      );
      await _openEveryone(tester);
      await tapKey(tester, 'allowance-button-user-sam');
      await enterKey(tester, 'allowance-amount', '100');
      await tapKey(tester, 'allowance-save');
      expect(find.text('Over the S\$100 allowance by S\$116'), findsOneWidget);
    });

    testWidgets('an empty amount removes it', (tester) async {
      final c = await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _tablet,
      );
      await _openEveryone(tester);
      await tapKey(tester, 'allowance-button-user-sam');
      await enterKey(tester, 'allowance-amount', '300');
      await tapKey(tester, 'allowance-save');
      await tapKey(tester, 'allowance-button-user-sam');
      await enterKey(tester, 'allowance-amount', '');
      await tapKey(tester, 'allowance-save');
      expect(find.textContaining('allowance ·'), findsNothing);
      expect(
        c
            .read(overviewProvider)
            .value!
            .people
            .firstWhere((p) => p.name == 'Sam')
            .allowanceCents,
        isNull,
      );
    });

    testWidgets('a number that is not a number is refused', (tester) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/home',
        size: _tablet,
      );
      await _openEveryone(tester);
      await tapKey(tester, 'allowance-button-user-sam');
      await enterKey(tester, 'allowance-amount', '1.2.3');
      await tapKey(tester, 'allowance-save');
      expect(key('allowance-error'), findsOneWidget);
    });

    testWidgets(
      'a member with household visibility sees the overview but cannot set allowances',
      (tester) async {
        await pumpAsMember(
          tester,
          me: viewerUser,
          location: '/home',
          size: _tablet,
        );
        await _openEveryone(tester);
        expect(find.text('Everyone spent'), findsOneWidget);
        expect(find.text('Set allowance'), findsNothing);
      },
    );
  });

  group('Home is the same in every theme with the filter and the card', () {
    testWidgets('same text, sizes and positions in Light, Dark and Pure black', (
      tester,
    ) async {
      String signature() {
        final out = StringBuffer();
        for (final element in find.byType(Text).evaluate()) {
          final text = (element.widget as Text).data ?? '';
          final box = element.renderObject as RenderBox;
          final pos = box.localToGlobal(Offset.zero);
          out.writeln(
            '$text @${pos.dx.round()},${pos.dy.round()} ${box.size.width.round()}x${box.size.height.round()}',
          );
        }
        return out.toString();
      }

      final seen = <String, String>{};
      for (final mode in ['light', 'dark', 'pureBlack']) {
        await pumpAsMember(
          tester,
          me: ownerUser,
          location: '/home',
          size: _tablet,
          mode: mode,
        );
        seen[mode] = signature();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
      expect(seen['dark'], seen['light']);
      expect(seen['pureBlack'], seen['light']);
      expect(seen['light'], contains('See everyone'));
    });
  });
}
