import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/features/auth/auth_providers.dart';
import 'package:family_expenses/features/auth/auth_service.dart';
import 'package:family_expenses/features/auth/sign_in_screen.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/family/data/household_remote.dart';
import 'package:family_expenses/features/family/data/household_repository.dart';
import 'package:family_expenses/features/family/domain/role.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:family_expenses/core/widgets/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

const _phone = Size(390, 844);
const _tablet = Size(1024, 720);

const _owner = 'user-you';
const _admin = 'user-maya';
const _editor = 'user-ed';
const _viewer = 'user-sam';

Finder _key(String key) => find.byKey(ValueKey(key));
Finder _field(String key) =>
    find.descendant(of: _key(key), matching: find.byType(TextField));

Future<void> _settle(WidgetTester tester) async {
  // Database work needs the real event loop; the starting page's spinner never "settles",
  // so step time by hand instead of pumpAndSettle.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.enterText(_field(key), text);
  await tester.pump();
}

class _Env {
  _Env(this.container, this.remote, this.auth);
  final ProviderContainer container;
  final FakeHouseholdRemote remote;
  final FakeAuthService auth;
}

Future<_Env> _pump(
  WidgetTester tester, {
  AuthUser? user,
  RemoteHousehold? existing,
  bool cached = false,
  String location = '/home',
  Size size = _tablet,
  Future<void> Function(AppDatabase db)? seedAsync,
  List<Override> extra = const [],
}) async {
  final remote = FakeHouseholdRemote(
    actingUserId: user?.id ?? _admin,
    household: existing,
  )..clock = () => kTestNow;
  final auth = FakeAuthService(user: user);
  final container = await pumpApp(
    tester,
    size: size,
    location: location,
    gated: true,
    sampleMembers: false,
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      householdRemoteProvider.overrideWithValue(remote),
      ...extra,
    ],
    seedAsync: (db) async {
      if (cached && existing != null) {
        await HouseholdRepository(db).replaceFromRemote(existing);
      }
      await seedAsync?.call(db);
    },
  );
  await _settle(tester);
  return _Env(container, remote, auth);
}

AuthUser _user(String id) =>
    AuthUser(id: id, email: '${id.replaceFirst('user-', '')}@example.com');

void main() {
  setUpAll(loadTestFonts);

  group('sign in', () {
    testWidgets('signed-out people land on the sign-in screen, not the app', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Family Expenses'), findsOneWidget);
      expect(_key('auth-email'), findsOneWidget);
      expect(find.text('Spent this month'), findsNothing);
      // No Apple or Google buttons on a desktop-class platform.
      expect(_key('auth-apple'), findsNothing);
    });

    testWidgets('a wrong password shows an error and stays signed out', (
      tester,
    ) async {
      final env = await _pump(tester);
      await _type(tester, 'auth-email', 'maya@example.com');
      await _type(tester, 'auth-password', 'nope');
      await _tap(tester, _key('auth-submit'));
      expect(
        find.text('That email and password do not match.'),
        findsOneWidget,
      );
      expect(env.auth.currentUser, isNull);
    });

    testWidgets('empty fields are explained, not sent', (tester) async {
      final env = await _pump(tester);
      await _tap(tester, _key('auth-submit'));
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(env.auth.calls, isEmpty);
    });

    testWidgets('signing in the first time leads to creating a household', (
      tester,
    ) async {
      final env = await _pump(tester);
      await _type(tester, 'auth-email', 'maya@example.com');
      await _type(tester, 'auth-password', 'secret-pass-1');
      await _tap(tester, _key('auth-submit'));
      expect(find.text('Set up your household'), findsOneWidget);
      expect(find.text('Spent this month'), findsNothing);

      await _type(tester, 'welcome-household', 'The Tans');
      await _type(tester, 'welcome-name', 'Maya Tan');
      await _tap(tester, _key('welcome-create'));

      expect(
        env.remote.calls.any(
          (c) => c.startsWith('create:The Tans:Maya Tan:SGD'),
        ),
        isTrue,
      );
      expect(
        find.text('Spent this month'),
        findsOneWidget,
        reason: 'now in the app',
      );
      expect(env.container.read(currentRoleProvider), Role.owner);
      final household = env.container.read(activeHouseholdProvider).value;
      expect(household?.name, 'The Tans');
    });

    testWidgets('an emailed code works as an alternative to a password', (
      tester,
    ) async {
      final env = await _pump(tester);
      await _type(tester, 'auth-email', 'ed@example.com');
      await _tap(tester, _key('auth-email-code'));
      expect(env.auth.calls, contains('send-code:ed@example.com'));
      expect(
        find.textContaining('We emailed a code to ed@example.com'),
        findsOneWidget,
      );

      await _type(tester, 'auth-code', '000000');
      await _tap(tester, _key('auth-verify'));
      expect(find.text('That code is wrong or has expired.'), findsOneWidget);

      await _type(tester, 'auth-code', '123456');
      await _tap(tester, _key('auth-verify'));
      expect(env.auth.currentUser?.email, 'ed@example.com');
    });

    testWidgets('creating an account signs in', (tester) async {
      final env = await _pump(tester);
      await _tap(tester, find.text('Create account').first);
      await _type(tester, 'auth-email', 'new@example.com');
      await _type(tester, 'auth-password', 'short');
      await _tap(tester, _key('auth-submit'));
      expect(
        find.text('Use at least 8 characters for the password.'),
        findsOneWidget,
      );
      await _type(tester, 'auth-password', 'long-enough-1');
      await _tap(tester, _key('auth-submit'));
      expect(env.auth.calls, contains('signup:new@example.com'));
      expect(find.text('Set up your household'), findsOneWidget);
    });

    testWidgets(
      'Google and Apple buttons appear where the platform offers them',
      (tester) async {
        final env = await _pump(
          tester,
          extra: [
            oauthProvidersProvider.overrideWithValue(const [
              OAuthProviderKind.google,
              OAuthProviderKind.apple,
            ]),
          ],
        );
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(find.text('Continue with Apple'), findsOneWidget);
        await _tap(tester, _key('auth-google'));
        expect(env.auth.calls, contains('oauth:google'));
      },
    );

    testWidgets('the sign-in screen fits a phone with large text', (
      tester,
    ) async {
      await _pump(tester, size: const Size(360, 800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('returning members go straight in, to where they were headed', (
      tester,
    ) async {
      await _pump(
        tester,
        user: _user(_owner),
        existing: sampleHousehold(),
        cached: true,
        location: '/family',
      );
      expect(find.text('Invite someone'), findsWidgets);
    });

    testWidgets('signing out returns to sign-in', (tester) async {
      final env = await _pump(
        tester,
        user: _user(_owner),
        existing: sampleHousehold(),
        cached: true,
      );
      expect(find.text('Spent this month'), findsOneWidget);
      await env.auth.signOut();
      await _settle(tester);
      expect(_key('auth-email'), findsOneWidget);
    });
  });

  group('join with a code', () {
    Future<_Env> pumpJoiner(WidgetTester tester) async {
      // Someone else owns the household and has made a code; this person is new.
      final env = await _pump(
        tester,
        user: const AuthUser(
          id: 'user-nina',
          email: 'nina@example.com',
          displayName: 'Nina',
        ),
        existing: sampleHousehold(),
      );
      env.remote.nextCodes
        ..clear()
        ..add('K7M4QX9X');
      env.remote.actingUserId = _owner;
      await env.remote.createInvite('household-1', Role.viewer);
      env.remote.actingUserId = 'user-nina';
      return env;
    }

    testWidgets('a new member joins with the role the code carries', (
      tester,
    ) async {
      final env = await pumpJoiner(tester);
      expect(find.text('Set up your household'), findsOneWidget);
      await _tap(tester, _key('welcome-join'));
      expect(find.text('Join a household'), findsOneWidget);

      // The button waits until all eight characters are in.
      expect(tester.widget<PillButton>(_key('join-submit')).onTap, isNull);

      await _type(tester, 'join-code', 'k7m4qx9x');
      expect(
        find.text('K7M4-QX9X'),
        findsOneWidget,
        reason: 'capitals and a dash as you type',
      );
      await _tap(tester, _key('join-submit'));

      expect(env.remote.calls, contains('redeem:K7M4QX9X'));
      expect(find.text('Spent this month'), findsOneWidget);
      expect(env.container.read(currentRoleProvider), Role.viewer);
      final members = env.container.read(membersProvider).value ?? [];
      expect(members.map((m) => m.displayName), contains('Nina'));
    });

    testWidgets('a wrong code is explained and nothing changes', (
      tester,
    ) async {
      final env = await pumpJoiner(tester);
      await _tap(tester, _key('welcome-join'));
      await _type(tester, 'join-code', 'ABCDEFGH');
      await _tap(tester, _key('join-submit'));
      expect(find.textContaining('That code did not work'), findsOneWidget);
      expect(
        env.container.read(currentRoleProvider),
        Role.viewer,
        reason: 'still no household',
      );
      expect(find.text('Join a household'), findsWidgets);
    });

    testWidgets('a code works once', (tester) async {
      final env = await pumpJoiner(tester);
      await _tap(tester, _key('welcome-join'));
      await _type(tester, 'join-code', 'K7M4QX9X');
      await _tap(tester, _key('join-submit'));
      expect(find.text('Spent this month'), findsOneWidget);

      // A second person tries the same code.
      env.remote.actingUserId = 'user-zed';
      expect(
        () => env.remote.redeemInvite('K7M4QX9X'),
        throwsA(
          isA<HouseholdFailure>().having(
            (e) => e.error,
            'error',
            HouseholdError.invalidCode,
          ),
        ),
      );
    });

    testWidgets('the join screen fits a phone', (tester) async {
      await pumpJoiner(tester);
      await _tap(tester, _key('welcome-join'));
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Codes work once and expire after 24 hours'),
        findsOneWidget,
      );
    });
  });

  group('what each role can do with expenses', () {
    Future<void> seedExpense(AppDatabase db) async {
      await db.customStatement(
        "UPDATE categories SET household_id = 'household-1'",
      );
      await ExpenseRepository(
        db,
        clock: () => kTestNow,
        householdId: 'household-1',
      ).add(
        amountCents: 1850,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 22),
        note: 'Hawker dinner',
        createdBy: _owner,
      );
    }

    Future<_Env> as(
      WidgetTester tester,
      String me, {
      String location = '/home',
      Size size = _tablet,
    }) => _pump(
      tester,
      user: _user(me),
      existing: sampleHousehold(),
      cached: true,
      location: location,
      size: size,
      seedAsync: seedExpense,
    );

    for (final me in [_owner, _admin, _editor]) {
      testWidgets('$me can add expenses', (tester) async {
        await as(tester, me);
        expect(find.text('+ Add expense'), findsOneWidget);
        await _tap(tester, find.text('+ Add expense'));
        expect(find.text('Add expense'), findsWidgets);
        expect(find.text('Save expense'), findsOneWidget);
      });

      testWidgets('$me can edit and delete from the list', (tester) async {
        await as(tester, me, location: '/expenses');
        expect(
          find.byTooltip('More actions for Hawker dinner'),
          findsOneWidget,
        );
        expect(find.byType(Dismissible), findsOneWidget);
      });
    }

    testWidgets(
      'a view-only member sees expenses but no way to add, edit or delete',
      (tester) async {
        await as(tester, _viewer);
        expect(
          find.text('Hawker dinner'),
          findsWidgets,
          reason: 'can read everything',
        );
        expect(find.text('+ Add expense'), findsNothing);
        expect(find.text('+ Add'), findsNothing);

        await tester.tap(find.text('Hawker dinner').first);
        await _settle(tester);
        expect(
          find.text('Edit expense'),
          findsNothing,
          reason: 'rows do not open',
        );
      },
    );

    testWidgets('view-only: the list has no menu, swipe or add button', (
      tester,
    ) async {
      await as(tester, _viewer, location: '/expenses');
      expect(find.text('Hawker dinner'), findsOneWidget);
      expect(find.byType(Dismissible), findsNothing);
      expect(find.byType(PopupMenuButton<Object?>), findsNothing);
      expect(find.byTooltip('More actions for Hawker dinner'), findsNothing);
      expect(find.bySemanticsLabel('Add expense'), findsNothing);
    });

    testWidgets('view-only: Add and edit addresses go back to Home', (
      tester,
    ) async {
      await as(tester, _viewer, location: '/add');
      expect(find.text('Save expense'), findsNothing);
      expect(find.text('Spent this month'), findsOneWidget);
    });

    testWidgets('view-only: Ctrl+N does nothing, for an editor it opens Add', (
      tester,
    ) async {
      Future<void> ctrlN() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await _settle(tester);
      }

      await as(tester, _viewer);
      await ctrlN();
      expect(find.text('Save expense'), findsNothing);
    });

    testWidgets('editor: Ctrl+N opens Add', (tester) async {
      await as(tester, _editor);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _settle(tester);
      expect(find.text('Save expense'), findsOneWidget);
    });

    testWidgets('only owner and admin can create categories', (tester) async {
      await as(tester, _editor, location: '/add');
      expect(find.text('+ New'), findsNothing);
      expect(find.text('Food'), findsWidgets);
    });

    testWidgets('admin sees the + New category tile', (tester) async {
      await as(tester, _admin, location: '/add');
      expect(find.text('+ New'), findsOneWidget);
    });

    testWidgets('the phone hides the Add button for view only', (tester) async {
      await as(tester, _viewer, size: _phone);
      expect(find.text('+ Add'), findsNothing);
      expect(find.text('Spent this month'), findsOneWidget);
    });
  });

  test('without Supabase the app is one person who can do everything', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(authServiceProvider), isNull);
    expect(container.read(currentRoleProvider), Role.owner);
    expect(container.read(permissionsProvider).canWriteExpenses, isTrue);
    expect(container.read(addedByLabelProvider)(null), 'You');
    expect(container.read(addedByLabelProvider)('You'), 'You');
    expect(
      container.read(addedByLabelProvider)('Maya'),
      'Maya',
      reason: 'old plain names',
    );
  });
}
