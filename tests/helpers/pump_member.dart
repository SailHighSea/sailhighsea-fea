import 'package:family_expenses/features/auth/auth_providers.dart';
import 'package:family_expenses/features/auth/auth_service.dart';
import 'package:family_expenses/features/family/data/household_repository.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'phase5_data.dart';
import 'test_app.dart';

/// The people in sampleHousehold(): owner "You", admin Maya, view-only Sam.
const ownerUser = 'user-you';
const adminUser = 'user-maya';
const viewerUser = 'user-sam';

/// Opens the app at [location] signed in as [me] in sampleHousehold (id `household-1`), with
/// the Phase 5 mockup data stored under that household.
Future<ProviderContainer> pumpAsMember(
  WidgetTester tester, {
  required String me,
  required String location,
  required Size size,
  double textScale = 1,
  bool seed = true,
  Set<String> ownOnly = const {},
  String mode = 'light',
  List<Override> overrides = const [],
}) async {
  final household = FakeHouseholdRemote(
    actingUserId: me,
    household: sampleHousehold(ownOnly: ownOnly),
  );
  final container = await pumpApp(
    tester,
    size: size,
    location: location,
    textScale: textScale,
    prefs: {'appearance.mode': mode},
    gated: true,
    sampleMembers: false,
    overrides: [
      authServiceProvider.overrideWithValue(
        FakeAuthService(
          user: AuthUser(id: me, email: '$me@example.com'),
        ),
      ),
      householdRemoteProvider.overrideWithValue(household),
      ...overrides,
    ],
    seedAsync: (db) async {
      await HouseholdRepository(db).replaceFromRemote(household.household!);
      if (seed) {
        await seedPhase5(db, household: 'household-1');
        await useMemberIds(db);
      }
    },
  );
  await settle(tester, rounds: 14);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
  return container;
}

/// Lets database work (real event loop) and animations finish.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> tapKey(WidgetTester tester, String k) async {
  final finder = key(k);
  expect(finder, findsOneWidget, reason: k);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Future<void> enterKey(WidgetTester tester, String k, String text) async {
  final field = find.descendant(of: key(k), matching: find.byType(TextField));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}
