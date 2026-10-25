import 'dart:async';

import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/core/google/google_api.dart';
import 'package:family_expenses/core/google/google_auth.dart';
import 'package:family_expenses/core/sheets_sync/sheets_settings.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:family_expenses/features/pairing/qr_scanner.dart';
import 'package:family_expenses/features/pairing/sheets_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_google.dart';
import '../../helpers/pump_member.dart';
import '../../helpers/sheets_device.dart';
import '../../helpers/test_app.dart';

const _phone = Size(390, 844);

FakeGoogle? _lastGoogle;

Future<ProviderContainer> _open(
  WidgetTester tester,
  FakeGoogleWorld world, {
  String email = 'dad@family.test',
  String name = 'Dad',
  bool signedIn = true,
  Map<String, Object> prefs = const {},
  Size size = _phone,
  String location = '/family',
}) {
  final google = world.account(email, name: name, signedIn: signedIn);
  _lastGoogle = google;
  return pumpApp(
    tester,
    size: size,
    location: location,
    prefs: prefs,
    overrides: [
      backendModeProvider.overrideWithValue(BackendMode.sheets),
      googleAuthProvider.overrideWithValue(google),
      sheetsApiProvider.overrideWithValue(google),
      driveApiProvider.overrideWithValue(google),
      sheetsSyncIntervalProvider.overrideWithValue(null),
      qrScanProvider.overrideWithValue(null),
    ],
  );
}

/// Runs something that uses the app's own database while its screens watch it. Started in the test
/// zone and given real time to finish (awaiting it inside `runAsync` can stall Drift's streams).
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

Map<String, Object> _role(String role) => {
  'sheets.settings': '{"role":"$role","name":""}',
};

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(EditableText),
  );
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

String _codeShown(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey('code-text')))
    .data!;

void main() {
  setUpAll(loadTestFonts);

  testWidgets(
    'signed out: Sign in with Google, then choose how to use the app',
    (tester) async {
      final world = FakeGoogleWorld();
      await _open(tester, world, signedIn: false);
      expect(find.text('Sign in with Google'), findsWidgets);
      expect(find.byKey(const ValueKey('role-organiser')), findsNothing);
      await _tapKey(tester, 'google-sign-in');
      expect(find.text('How will you use the app?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('role-member')));
      await settle(tester);
      expect(find.text('Join with a code'), findsOneWidget);
    },
  );

  testWidgets('a revoked Google grant shows Reconnect and nothing is lost', (
    tester,
  ) async {
    final world = FakeGoogleWorld();
    final c = await _open(tester, world, prefs: _role('member'));
    await settle(tester);
    expect(find.text('Reconnect to Google'), findsNothing);
    _lastGoogle!.revoked = true;
    await _appRun(tester, () => c.read(sheetsSyncProvider.notifier).syncNow());
    await settle(tester);
    expect(c.read(sheetsSyncProvider).needsReconnect, isTrue);
    expect(find.text('Reconnect to Google'), findsWidgets);
    expect(find.byKey(const ValueKey('google-sign-in')), findsWidgets);
  });

  testWidgets(
    'organiser: create an invite, show the code, add the member\'s code',
    (tester) async {
      final world = FakeGoogleWorld();
      await _open(tester, world, prefs: _role('organiser'));
      expect(
        find.text(
          'Nobody is paired yet. Create an invite and send the code to a family member.',
        ),
        findsOneWidget,
      );
      await tester.runAsync(() async {});
      await _tapKey(tester, 'create-invite');
      await settle(tester);
      expect(find.byKey(const ValueKey('invite-card')), findsOneWidget);
      final invite = _codeShown(tester);
      expect(invite, startsWith('FEH1.'));

      final maya = Device(world, 'maya@family.test', 'Maya', SheetsRole.member);
      late String code;
      await tester.runAsync(
        () async => code = await maya.pairing.joinWithInvite(invite),
      );
      await _enter(tester, 'member-code-input', code);
      await _tapKey(tester, 'code-submit');
      await settle(tester);
      expect(find.textContaining('maya@family.test'), findsWidgets);
      expect(find.text('Maya'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('invite-card')),
        findsNothing,
        reason: 'the invite was used',
      );
    },
  );

  testWidgets('organiser: a wrong code says what is wrong', (tester) async {
    final world = FakeGoogleWorld();
    await _open(tester, world, prefs: _role('organiser'));
    await _enter(tester, 'member-code-input', 'not a code');
    await _tapKey(tester, 'code-submit');
    expect(find.byKey(const ValueKey('code-error')), findsOneWidget);
    expect(
      find.text('That is not a code from a family member.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'organiser: Unpair asks first, then the member shows "No longer shared"',
    (tester) async {
      final world = FakeGoogleWorld();
      final dad = world.account('dad@family.test', name: 'Dad');
      final c = await _open(tester, world, prefs: _role('organiser'));
      final maya = Device(world, 'maya@family.test', 'Maya', SheetsRole.member);
      // Pair through the app's own service so its database and settings are used.
      final svc = c.read(pairingServiceProvider)!;
      final invite = await _appRun(tester, svc.createInvite);
      late String code;
      await tester.runAsync(
        () async => code = await maya.pairing.joinWithInvite(invite),
      );
      await _appRun(tester, () => svc.addMember(code));
      expect(dad.email, isNotEmpty);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('pair-status-maya@family.test')),
        findsOneWidget,
      );
      await tester.tap(find.text('Unpair'));
      await settle(tester);
      expect(find.text('Unpair Maya?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-unpair')));
      await settle(tester);
      expect(find.textContaining('No longer shared'), findsOneWidget);
    },
  );

  testWidgets(
    'member: paste the invite, confirm what is shared, then see your own code',
    (tester) async {
      final world = FakeGoogleWorld();
      final dad = Device(world, 'dad@family.test', 'Dad', SheetsRole.organiser);
      late String invite;
      await tester.runAsync(
        () async => invite = await dad.pairing.createInvite(),
      );
      await _open(
        tester,
        world,
        email: 'maya@family.test',
        name: 'Maya',
        prefs: _role('member'),
      );
      await _enter(tester, 'invite-code-input', invite);
      await _tapKey(tester, 'code-submit');
      expect(find.text('Share your expenses?'), findsOneWidget);
      expect(find.textContaining('dad@family.test'), findsOneWidget);
      expect(find.textContaining('(read only)'), findsOneWidget);
      expect(
        world.sheets.values.where((s) => s.owner == 'maya@family.test'),
        isEmpty,
        reason: 'not shared before they say yes',
      );
      await tester.tap(find.byKey(const ValueKey('confirm-share')));
      await settle(tester);
      await settle(tester);
      expect(find.byKey(const ValueKey('sharing-with')), findsOneWidget);
      expect(find.byKey(const ValueKey('member-code-card')), findsOneWidget);
      expect(_codeShown(tester), startsWith('FEM1.'));
      final mayaSheet = world.sheets.values.singleWhere(
        (s) => s.owner == 'maya@family.test',
      );
      expect(mayaSheet.readers, {'dad@family.test'});
    },
  );

  testWidgets(
    'member: saying no shares nothing; an expired or wrong code is explained',
    (tester) async {
      final world = FakeGoogleWorld();
      final dad = Device(world, 'dad@family.test', 'Dad', SheetsRole.organiser);
      late String invite;
      await tester.runAsync(
        () async => invite = await dad.pairing.createInvite(),
      );
      await _open(
        tester,
        world,
        email: 'maya@family.test',
        name: 'Maya',
        prefs: _role('member'),
      );
      await _enter(tester, 'invite-code-input', invite);
      await _tapKey(tester, 'code-submit');
      await tester.tap(find.text('Not now'));
      await settle(tester);
      expect(
        world.sheets.values.where((s) => s.owner == 'maya@family.test'),
        isEmpty,
      );
      await _enter(tester, 'invite-code-input', 'hello');
      await _tapKey(tester, 'code-submit');
      expect(
        find.text('That is not an invite code from the organiser.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('member can leave; the organiser stops seeing the sheet', (
    tester,
  ) async {
    final world = FakeGoogleWorld();
    final dad = Device(world, 'dad@family.test', 'Dad', SheetsRole.organiser);
    late String invite;
    await tester.runAsync(
      () async => invite = await dad.pairing.createInvite(),
    );
    await _open(
      tester,
      world,
      email: 'maya@family.test',
      name: 'Maya',
      prefs: _role('member'),
    );
    await _enter(tester, 'invite-code-input', invite);
    await _tapKey(tester, 'code-submit');
    await tester.tap(find.byKey(const ValueKey('confirm-share')));
    await settle(tester);
    await settle(tester);
    await _tapKey(tester, 'stop-sharing');
    await tester.tap(find.byKey(const ValueKey('confirm-leave')));
    await settle(tester);
    await settle(tester);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(
      world.sheets.values
          .singleWhere((s) => s.owner == 'maya@family.test')
          .readers,
      isEmpty,
    );
  });

  group('suggestions', () {
    testWidgets(
      'a member sends one; the organiser approves and the budget appears',
      (tester) async {
        final world = FakeGoogleWorld();
        // Organiser phone (headless) and the member app under test.
        final dad = Device(
          world,
          'dad@family.test',
          'Dad',
          SheetsRole.organiser,
        );
        final c = await _open(
          tester,
          world,
          email: 'maya@family.test',
          name: 'Maya',
          prefs: _role('member'),
          location: '/suggestions',
        );
        late String invite;
        await tester.runAsync(
          () async => invite = await dad.pairing.createInvite(),
        );
        final code = await _appRun(
          tester,
          () => c.read(pairingServiceProvider)!.joinWithInvite(invite),
        );
        await tester.runAsync(() => dad.pairing.addMember(code));
        await settle(tester);
        await _tapKey(tester, 'new-suggestion');
        // The first AmountField in the sheet is the budget amount.
        final amount = find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(EditableText),
            )
            .first;
        await tester.enterText(amount, '1800');
        await _tapKey(tester, 'send-suggestion');
        await settle(tester);
        expect(
          find.textContaining('Waiting for the organiser'),
          findsOneWidget,
        );
        expect(find.textContaining('1,800.00'), findsOneWidget);

        await _appRun(
          tester,
          () => c.read(sheetsSyncProvider.notifier).syncNow(),
        );
        await tester.runAsync(() async {
          await dad.sync.syncOnce();
          final pending = await dad.db.select(dad.db.suggestions).get();
          expect(pending, hasLength(1));
          await dad.suggestions.approve(pending.single.id);
          await dad.sync.syncOnce();
        });
        await _appRun(
          tester,
          () => c.read(sheetsSyncProvider.notifier).syncNow(force: true),
        );
        await settle(tester);
        expect(find.textContaining('Approved'), findsOneWidget);
        final db = c.read(databaseProvider);
        expect(
          (await _appRun(
            tester,
            () => db.select(db.budgets).get(),
          )).single.amountCents,
          180000,
        );
      },
    );

    testWidgets('the organiser sees the inbox with Approve and Decline', (
      tester,
    ) async {
      final world = FakeGoogleWorld();
      final maya = Device(world, 'maya@family.test', 'Maya', SheetsRole.member);
      final c = await _open(
        tester,
        world,
        prefs: _role('organiser'),
        location: '/suggestions',
      );
      late String id;
      final svc = c.read(pairingServiceProvider)!;
      final invite = await _appRun(tester, svc.createInvite);
      late String code;
      await tester.runAsync(
        () async => code = await maya.pairing.joinWithInvite(invite),
      );
      await _appRun(tester, () => svc.addMember(code));
      await tester.runAsync(() async {
        id = await maya.suggestions.create(
          memberEmail: 'maya@family.test',
          kind: 'goal',
          action: 'add',
          payload: {'name': 'Bike', 'targetCents': 90000},
          note: 'For school',
        );
        await maya.sync.syncOnce();
      });
      await _appRun(
        tester,
        () => c.read(sheetsSyncProvider.notifier).syncNow(),
      );
      await settle(tester);
      expect(find.textContaining('New goal: Bike'), findsOneWidget);
      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('For school'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('decline-$id')));
      await settle(tester);
      expect(find.byKey(ValueKey('status-$id')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(ValueKey('status-$id'))).data,
        'Declined',
      );
      expect(find.byKey(ValueKey('approve-$id')), findsNothing);
    });

    testWidgets('a bad suggestion shows the reason and is not saved', (
      tester,
    ) async {
      final world = FakeGoogleWorld();
      await _open(
        tester,
        world,
        email: 'maya@family.test',
        name: 'Maya',
        prefs: _role('member'),
        location: '/suggestions',
      );
      await _tapKey(tester, 'new-suggestion');
      await _tapKey(tester, 'send-suggestion');
      expect(find.byKey(const ValueKey('suggestion-error')), findsOneWidget);
    });
  });

  group('rules in this mode', () {
    testWidgets(
      'a member can add expenses but not manage budgets, goals or bills',
      (tester) async {
        final c = await _open(
          tester,
          FakeGoogleWorld(),
          prefs: _role('member'),
          location: '/home',
        );
        final p = c.read(permissionsProvider);
        expect(p.canWriteExpenses, isTrue);
        expect(p.canManageBudgets, isFalse);
        expect(p.canManageGoals, isFalse);
        expect(p.canManageBills, isFalse);
        expect(
          c.read(canSeeEveryoneProvider),
          isFalse,
          reason: 'members never see other members',
        );
      },
    );

    testWidgets(
      'the organiser owns everything and sees everyone once someone is paired',
      (tester) async {
        final world = FakeGoogleWorld();
        final c = await _open(
          tester,
          world,
          prefs: _role('organiser'),
          location: '/home',
        );
        expect(c.read(permissionsProvider).canManageBudgets, isTrue);
        expect(
          c.read(canSeeEveryoneProvider),
          isFalse,
          reason: 'nobody paired yet',
        );
        final maya = Device(
          world,
          'maya@family.test',
          'Maya',
          SheetsRole.member,
        );
        final svc = c.read(pairingServiceProvider)!;
        final invite = await _appRun(tester, svc.createInvite);
        late String code;
        await tester.runAsync(
          () async => code = await maya.pairing.joinWithInvite(invite),
        );
        await _appRun(tester, () => svc.addMember(code));
        await settle(tester);
        expect(c.read(canSeeEveryoneProvider), isTrue);
      },
    );

    testWidgets(
      'the organiser cannot edit a member\'s expense, but can edit his own',
      (tester) async {
        final c = await _open(
          tester,
          FakeGoogleWorld(),
          prefs: _role('organiser'),
          location: '/home',
        );
        final canEdit = c.read(canEditExpenseProvider);
        expect(canEdit('g:maya@family.test'), isFalse);
        expect(canEdit('You'), isTrue);
        expect(canEdit(null), isTrue);
      },
    );

    testWidgets(
      'outside Sheets mode nothing changes: the member rule does not apply',
      (tester) async {
        final c = await pumpApp(tester, size: _phone);
        expect(c.read(isSheetsModeProvider), isFalse);
        expect(c.read(canEditExpenseProvider)('g:someone'), isTrue);
      },
    );
  });

  testWidgets(
    'the Family page fits and meets tap targets at phone, tablet and desktop widths',
    (tester) async {
      for (final size in const [
        Size(360, 740),
        Size(840, 900),
        Size(1280, 800),
      ]) {
        await _open(
          tester,
          FakeGoogleWorld(),
          prefs: _role('organiser'),
          size: size,
        );
        await settle(tester);
        expect(tester.takeException(), isNull, reason: '$size');
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
    },
  );

  testWidgets(
    'the organiser\'s Everyone overview shows each member\'s imported spending',
    (tester) async {
      final world = FakeGoogleWorld();
      final maya = Device(world, 'maya@family.test', 'Maya', SheetsRole.member);
      final c = await _open(
        tester,
        world,
        prefs: _role('organiser'),
        location: '/insights',
        size: const Size(1280, 800),
      );
      final svc = c.read(pairingServiceProvider)!;
      final invite = await _appRun(tester, svc.createInvite);
      late String code;
      await tester.runAsync(() async {
        code = await maya.pairing.joinWithInvite(invite);
        await maya.addExpense(
          4820,
          note: 'Groceries',
          on: DateTime(2026, 10, 20),
        );
        await maya.sync.syncOnce();
      });
      await _appRun(tester, () => svc.addMember(code));
      await _appRun(
        tester,
        () => c.read(sheetsSyncProvider.notifier).syncNow(),
      );
      await settle(tester);
      await tester.tap(find.text('Everyone').first);
      await settle(tester);
      expect(find.text('Maya'), findsWidgets);
      expect(find.textContaining('48'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
