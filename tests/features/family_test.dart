import 'dart:ui' show DisplayFeature;

import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/features/auth/auth_providers.dart';
import 'package:family_expenses/features/auth/auth_service.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/family/data/household_remote.dart';
import 'package:family_expenses/features/family/data/household_repository.dart';
import 'package:family_expenses/features/family/domain/role.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

const _phone = Size(390, 844);
const _tablet = Size(1024, 720);
const _desktop = Size(1280, 800);

// The people in sampleHousehold().
const _owner = 'user-you';
const _admin = 'user-maya';
const _editor = 'user-ed';
const _viewer = 'user-sam';

class _Env {
  _Env(this.container, this.remote, this.auth);
  final ProviderContainer container;
  final FakeHouseholdRemote remote;
  final FakeAuthService auth;
}

/// Opens the app as [me], already a member (the household is cached on the device).
Future<_Env> _pumpMember(
  WidgetTester tester, {
  required String me,
  Size size = _tablet,
  String location = '/family',
  double textScale = 1,
  void Function(AppDatabase db)? seed,
  Future<void> Function(AppDatabase db)? seedAsync,
  List<DisplayFeature> displayFeatures = const [],
}) async {
  final remote = FakeHouseholdRemote(
    actingUserId: me,
    household: sampleHousehold(),
  )..clock = () => kTestNow;
  final auth = FakeAuthService(
    user: AuthUser(
      id: me,
      email: '${me.replaceFirst('user-', '')}@example.com',
    ),
  );
  final container = await pumpApp(
    tester,
    size: size,
    location: location,
    textScale: textScale,
    gated: true,
    sampleMembers: false,
    displayFeatures: displayFeatures,
    seed: seed,
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      householdRemoteProvider.overrideWithValue(remote),
    ],
    seedAsync: (db) async {
      await HouseholdRepository(db).replaceFromRemote(remote.household!);
      await seedAsync?.call(db);
    },
  );
  await _settle(tester);
  return _Env(container, remote, auth);
}

/// Lets database work (which needs the real event loop) and animations finish.
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

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

String _memberRoleText(WidgetTester tester, String userId) {
  final tile = _key('member-$userId');
  final texts = tester
      .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
  return texts.join('|');
}

void main() {
  setUpAll(loadTestFonts);

  group('Family screen: owner', () {
    testWidgets(
      'lists members with role pills and a role button for everyone else',
      (tester) async {
        await _pumpMember(tester, me: _owner);
        expect(find.text('Family'), findsWidgets);
        expect(find.text('Household owner'), findsOneWidget);
        expect(
          _key('role-$_owner'),
          findsOneWidget,
          reason: 'owner pill, not a button',
        );
        expect(find.text('Owner'), findsOneWidget);
        expect(_key('role-button-$_owner'), findsNothing);
        for (final id in [_admin, _viewer, _editor]) {
          expect(_key('role-button-$id'), findsOneWidget, reason: id);
        }
        expect(_memberRoleText(tester, _admin), contains('Admin'));
        expect(_memberRoleText(tester, _viewer), contains('View only'));
        expect(_memberRoleText(tester, _editor), contains('Can edit'));
        expect(find.textContaining('Joined 12 Oct'), findsOneWidget);
        expect(find.text('Have a code? Join a household'), findsOneWidget);
      },
    );

    testWidgets('promotes a member to Admin from the role sheet', (
      tester,
    ) async {
      final env = await _pumpMember(tester, me: _owner);
      await _tap(tester, _key('role-button-$_viewer'));
      expect(_key('role-sheet'), findsOneWidget);
      await _tap(tester, _key('role-option-admin'));
      expect(env.remote.calls, contains('set-role:$_viewer:admin'));
      expect(_memberRoleText(tester, _viewer), contains('Admin'));
      expect(_key('role-sheet'), findsNothing);
    });

    testWidgets('changes a role down to view only', (tester) async {
      final env = await _pumpMember(tester, me: _owner);
      await _tap(tester, _key('role-button-$_editor'));
      await _tap(tester, _key('role-option-viewer'));
      expect(env.remote.calls, contains('set-role:$_editor:viewer'));
      expect(_memberRoleText(tester, _editor), contains('View only'));
    });

    testWidgets('removes a member after confirming', (tester) async {
      final env = await _pumpMember(tester, me: _owner);
      await _tap(tester, _key('role-button-$_editor'));
      await _tap(tester, _key('remove-member'));
      expect(find.text('Remove Ed?'), findsOneWidget);
      await _tap(tester, _key('confirm-action'));
      expect(env.remote.calls, contains('remove:$_editor'));
      expect(_key('member-$_editor'), findsNothing);
      expect(_key('member-$_viewer'), findsOneWidget);
    });

    testWidgets('cancelling the removal keeps the member', (tester) async {
      final env = await _pumpMember(tester, me: _owner);
      await _tap(tester, _key('role-button-$_editor'));
      await _tap(tester, _key('remove-member'));
      await _tap(tester, find.text('Cancel'));
      expect(env.remote.calls.where((c) => c.startsWith('remove')), isEmpty);
      expect(_key('member-$_editor'), findsOneWidget);
    });

    testWidgets(
      'creates a code for Can edit, then for View only, and copies it',
      (tester) async {
        final env = await _pumpMember(tester, me: _owner);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        expect(find.text('Create a code to share'), findsOneWidget);
        await _tap(tester, _key('invite-create'));
        expect(env.remote.calls, contains('create-invite:editor'));
        expect(find.text('K7M4-QX9X'), findsOneWidget);
        expect(find.text('One use · expires in 24 hours'), findsOneWidget);

        await _tap(tester, _key('invite-copy'));
        expect(copied, 'K7M4-QX9X');
        expect(find.text('Code copied'), findsOneWidget);

        // The code belongs to one role, so changing the role clears it.
        await _tap(tester, find.text('View only').last);
        expect(find.text('K7M4-QX9X'), findsNothing);
        await _tap(tester, _key('invite-create'));
        expect(env.remote.calls, contains('create-invite:viewer'));
        expect(find.text('P3R8-WZ2N'), findsOneWidget);

        await _tap(tester, _key('invite-new'));
        expect(find.text('B5D6-FH7J'), findsOneWidget);
      },
    );

    testWidgets('open codes are listed and can be revoked', (tester) async {
      final env = await _pumpMember(tester, me: _owner);
      await _tap(tester, _key('invite-create'));
      expect(find.text('Open codes'), findsOneWidget);
      expect(
        find.textContaining('Can edit · expires in 24 hours'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Revoke'));
      expect(
        env.remote.calls.where((c) => c.startsWith('revoke')),
        hasLength(1),
      );
      expect(find.text('Open codes'), findsNothing);
    });

    testWidgets('has no Leave button but can sign out', (tester) async {
      final env = await _pumpMember(tester, me: _owner);
      expect(_key('leave-household'), findsNothing);
      await _tap(tester, _key('sign-out'));
      expect(env.auth.calls, contains('sign-out'));
      expect(
        find.text('Family Expenses'),
        findsOneWidget,
        reason: 'back at sign-in',
      );
    });
  });

  group('Family screen: admin', () {
    testWidgets('manages members and invites but cannot touch the owner', (
      tester,
    ) async {
      await _pumpMember(tester, me: _admin);
      expect(
        _key('role-button-$_owner'),
        findsNothing,
        reason: 'owner row has no control',
      );
      expect(_key('role-$_owner'), findsOneWidget);
      expect(
        _key('role-button-$_admin'),
        findsNothing,
        reason: 'not your own role',
      );
      expect(_key('role-button-$_viewer'), findsOneWidget);
      expect(_key('role-button-$_editor'), findsOneWidget);
      expect(_key('invite-create'), findsOneWidget);
      expect(_key('leave-household'), findsOneWidget);
    });

    testWidgets('can change a role', (tester) async {
      final env = await _pumpMember(tester, me: _admin);
      await _tap(tester, _key('role-button-$_viewer'));
      await _tap(tester, _key('role-option-editor'));
      expect(env.remote.calls, contains('set-role:$_viewer:editor'));
    });

    testWidgets('leaving asks first, then the household is gone from the app', (
      tester,
    ) async {
      final env = await _pumpMember(tester, me: _admin);
      await _tap(tester, _key('leave-household'));
      expect(find.text('Leave this household?'), findsOneWidget);
      await _tap(tester, _key('confirm-action'));
      expect(env.remote.calls, contains('remove:$_admin'));
      expect(find.text('Set up your household'), findsOneWidget);
    });
  });

  group('Family screen: editor and view only', () {
    for (final me in [_editor, _viewer]) {
      testWidgets('$me sees the members but no role or invite controls', (
        tester,
      ) async {
        await _pumpMember(tester, me: me);
        expect(_key('member-$_owner'), findsOneWidget);
        expect(_key('member-$_admin'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w.key.toString().contains('role-button-'),
          ),
          findsNothing,
        );
        expect(_key('invite-create'), findsNothing);
        expect(_key('cannot-invite'), findsOneWidget);
        expect(find.text('Open codes'), findsNothing);
        expect(
          find.textContaining('Only the owner and admins can invite'),
          findsOneWidget,
        );
      });
    }

    testWidgets(
      'a stale screen cannot get around the server: the change is rejected',
      (tester) async {
        final env = await _pumpMember(tester, me: _admin);
        // The server now says this person is only a viewer, but the device has not heard yet.
        env.remote.offline = true;
        env.remote.household = RemoteHousehold(
          id: 'household-1',
          name: 'Our household',
          currency: 'SGD',
          ownerId: _owner,
          members: [
            for (final m in sampleHousehold().members)
              RemoteMember(
                userId: m.userId,
                role: m.userId == _admin ? Role.viewer : m.role,
                displayName: m.displayName,
                joinedAt: m.joinedAt,
              ),
          ],
        );
        await _tap(tester, _key('role-button-$_editor'));
        await _tap(tester, _key('role-option-viewer'));
        expect(find.text('Your role does not allow that.'), findsOneWidget);
        expect(
          _memberRoleText(tester, _editor),
          contains('Can edit'),
          reason: 'unchanged',
        );
      },
    );
  });

  group('Family screen layouts', () {
    for (final (name, size) in [
      ('phone', _phone),
      ('tablet', _tablet),
      ('desktop', _desktop),
    ]) {
      testWidgets('$name: members, legend and invite card all fit', (
        tester,
      ) async {
        await _pumpMember(tester, me: _owner, size: size);
        expect(tester.takeException(), isNull);
        expect(find.text('Admin:'), findsNothing); // rich text, checked below
        expect(
          find.textContaining('full access, same as the owner'),
          findsOneWidget,
        );
        expect(_key('invite-create'), findsOneWidget);
        expect(find.text('Invite someone'), findsWidgets);
        expect(
          find.text(
            size == _phone
                ? 'Have a code instead? Join a household'
                : 'Have a code? Join a household',
          ),
          findsOneWidget,
        );
      });
    }

    testWidgets('large text does not overflow on a phone', (tester) async {
      await _pumpMember(
        tester,
        me: _owner,
        size: const Size(360, 800),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('every control is at least 44 high', (tester) async {
      await _pumpMember(tester, me: _owner, size: _phone);
      for (final key in [
        'role-button-$_viewer',
        'role-button-$_admin',
        'invite-create',
      ]) {
        final finder = _key(key);
        await tester.ensureVisible(finder);
        expect(
          tester.getSize(finder).height,
          greaterThanOrEqualTo(44),
          reason: key,
        );
      }
      await _tap(tester, _key('invite-create'));
      for (final key in ['invite-copy', 'invite-share', 'invite-new']) {
        final finder = _key(key);
        await tester.ensureVisible(finder);
        expect(
          tester.getSize(finder).height,
          greaterThanOrEqualTo(44),
          reason: key,
        );
      }
    });

    testWidgets(
      'the phone reaches Family from Settings and opens Join from it',
      (tester) async {
        await _pumpMember(tester, me: _owner, size: _phone, location: '/home');
        await _tap(tester, find.text('Settings').first);
        await _tap(tester, find.byKey(const ValueKey('settings-family')));
        expect(_key('invite-create'), findsOneWidget);
        await _tap(tester, find.text('Have a code instead? Join a household'));
        expect(find.text('Join a household'), findsOneWidget);
      },
    );
  });

  group('who added', () {
    testWidgets('expenses show the member name, "You" for your own', (
      tester,
    ) async {
      Future<void> seedExpenses(AppDatabase db) async {
        final repo = ExpenseRepository(
          db,
          clock: () => kTestNow,
          householdId: 'household-1',
        );
        await repo.add(
          amountCents: 1850,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 22),
          note: 'Hawker dinner',
          createdBy: _admin,
        );
        await repo.add(
          amountCents: 900,
          categoryId: 'default-transport',
          spentOn: DateTime(2026, 10, 21),
          note: 'Bus pass',
          createdBy: _owner,
        );
      }

      await _pumpMember(
        tester,
        me: _owner,
        location: '/expenses',
        seedAsync: (db) async {
          // The default categories belong to the household once it exists.
          await db.customStatement(
            "UPDATE categories SET household_id = 'household-1'",
          );
          await seedExpenses(db);
        },
      );
      expect(find.textContaining('Maya'), findsWidgets);
      expect(find.textContaining('Food · Yesterday · Maya'), findsOneWidget);
      expect(find.textContaining('· You'), findsOneWidget);
      expect(find.textContaining('· Maya'), findsOneWidget);
    });
  });
}
