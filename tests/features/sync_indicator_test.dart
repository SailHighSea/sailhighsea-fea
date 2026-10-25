import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/features/auth/auth_providers.dart';
import 'package:family_expenses/features/auth/auth_service.dart';
import 'package:family_expenses/features/family/data/household_repository.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/core/sync/sync_engine.dart';
import 'package:family_expenses/core/sync/sync_status.dart';
import 'package:family_expenses/core/theme/app_theme.dart';
import 'package:family_expenses/features/sync/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync.dart';
import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

const _phone = Size(390, 844);
const _tablet = Size(1024, 720);
const _desktop = Size(1280, 800);

void main() {
  setUpAll(loadTestFonts);
  _wiring();

  testWidgets('local-only: no indicator is shown', (tester) async {
    await pumpApp(tester, size: _phone);
    expect(find.byKey(const ValueKey('sync-indicator')), findsNothing);
  });

  for (final (name, size, label) in [
    ('phone', _phone, 'Offline, 2 waiting'),
    ('tablet rail', _tablet, 'Offline'),
    ('desktop sidebar', _desktop, 'Offline, 2 waiting'),
  ]) {
    testWidgets('$name: indicator shows the state and is easy to tap', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: size,
        overrides: [
          syncStatusProvider.overrideWith(
            (ref) => Stream.value(
              const SyncStatus(phase: SyncPhase.offline, pending: 2),
            ),
          ),
        ],
      );
      await tester.pump();
      final indicator = find.byKey(const ValueKey('sync-indicator'));
      expect(indicator, findsOneWidget);
      expect(
        find.descendant(of: indicator, matching: find.text(label)),
        findsOneWidget,
      );
      expect(
        tester.getSize(indicator).height,
        greaterThanOrEqualTo(kMinTapTarget),
      );
    });
  }

  testWidgets('first-time download shows progress', (tester) async {
    // The spinner never settles, so the state arrives after the app has settled.
    final states = StreamController<SyncStatus>();
    addTearDown(states.close);
    await pumpApp(
      tester,
      size: _phone,
      overrides: [syncStatusProvider.overrideWith((ref) => states.stream)],
    );
    states.add(
      const SyncStatus(phase: SyncPhase.syncing, initial: true, pulled: 120),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Getting 120 items'), findsOneWidget);
  });

  testWidgets('tapping opens details with refused changes and Dismiss', (
    tester,
  ) async {
    final server = FakeSyncServer()..seedDefaultCategories();
    late SyncEngine engine;
    final container = await pumpApp(
      tester,
      size: _tablet,
      overrides: [
        syncEngineProvider.overrideWith((ref) {
          engine = SyncEngine(
            db: ref.read(databaseProvider),
            backend: server.backendFor('vik'),
            householdId: 'h1',
            userId: 'vik',
          );
          ref.onDispose(engine.dispose);
          return engine;
        }),
      ],
    );
    final db = container.read(databaseProvider);
    await tester.runAsync(() async {
      await db
          .into(db.syncIssues)
          .insert(
            SyncIssuesCompanion.insert(
              householdId: 'h1',
              syncTable: 'expenses',
              rowId: 'e1',
              summary: 'Lunch, 12.50',
              createdAt: kTestNow,
            ),
          );
      await engine
          .dismissIssues(); // also proves the call works with an empty queue
      await db
          .into(db.syncIssues)
          .insert(
            SyncIssuesCompanion.insert(
              householdId: 'h1',
              syncTable: 'expenses',
              rowId: 'e2',
              summary: 'Lunch, 12.50',
              createdAt: kTestNow,
            ),
          );
    });
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sync-indicator')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-sheet')), findsOneWidget);
    expect(find.text('Not saved'), findsOneWidget);
    expect(find.text('Lunch, 12.50'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Not saved'), findsNothing);
  });
}

/// The whole chain with the real providers: a signed-in view-only member whose queued
/// expense is refused by the server.
void _wiring() {
  testWidgets('signed in: the engine runs, the server refuses a viewer', (
    tester,
  ) async {
    final server = FakeSyncServer(householdId: 'household-1')
      ..seedDefaultCategories()
      ..roles['user-sam'] = 'viewer';
    final remote = FakeHouseholdRemote(
      actingUserId: 'user-sam',
      household: sampleHousehold(),
    );
    final container = await pumpApp(
      tester,
      size: _tablet,
      gated: true,
      sampleMembers: false,
      overrides: [
        authServiceProvider.overrideWithValue(
          FakeAuthService(
            user: const AuthUser(id: 'user-sam', email: 'sam@example.com'),
          ),
        ),
        householdRemoteProvider.overrideWithValue(remote),
        syncBackendProvider.overrideWithValue(server.backendFor('user-sam')),
      ],
      seedAsync: (db) async {
        await HouseholdRepository(db).replaceFromRemote(remote.household!);
        await db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: 'queued-1',
                householdId: const Value('household-1'),
                amountCents: 1250,
                categoryId: 'default-food',
                note: const Value('Lunch'),
                spentOn: '2026-10-20',
                createdBy: const Value('user-sam'),
                updatedAt: kTestNow,
              ),
            );
      },
    );
    final db = container.read(databaseProvider);
    // The engine works on the real event loop; wait (up to ~10 s) until it has answered.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final found = await tester.runAsync(() => db.select(db.syncIssues).get());
      if (found!.isNotEmpty) break;
    }
    expect(server.row('expenses', 'queued-1'), isNull);
    final issues = await tester.runAsync(() => db.select(db.syncIssues).get());
    expect(issues!.single.summary, 'Lunch, 12.50');
    expect(find.text('Check'), findsOneWidget);

    // Stop the engine's timers before the test ends.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
