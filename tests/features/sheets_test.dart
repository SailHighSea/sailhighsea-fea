import 'dart:async';

import 'package:family_expenses/core/db/app_database.dart' show HouseholdRow;
import 'package:family_expenses/features/auth/auth_providers.dart';
import 'package:family_expenses/features/auth/auth_service.dart';
import 'package:family_expenses/features/family/data/household_repository.dart';
import 'package:family_expenses/features/family/domain/permissions.dart';
import 'package:family_expenses/features/family/domain/role.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:family_expenses/features/integrations/data/sheets_remote.dart';
import 'package:family_expenses/features/integrations/sheets_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sheets.dart';
import '../helpers/fakes.dart';
import '../helpers/test_app.dart';

const _phone = Size(390, 844);
const _tablet = Size(1024, 720);
const _desktop = Size(1280, 800);

const _owner = 'user-you';
const _admin = 'user-maya';
const _viewer = 'user-sam';

class _Env {
  _Env(this.container, this.status, this.remote, this.opened);
  final ProviderContainer container;
  final StreamController<SheetStatus> status;
  final FakeSheetsRemote remote;
  final List<Uri> opened;
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Family screen as [me], with the sheet status under test control.
Future<_Env> _pump(
  WidgetTester tester, {
  required String me,
  SheetStatus initial = const SheetStatus.none(),
  Size size = _tablet,
  double textScale = 1,
}) async {
  final remote = FakeSheetsRemote(status: initial);
  final household = FakeHouseholdRemote(
    actingUserId: me,
    household: sampleHousehold(),
  );
  final status = StreamController<SheetStatus>();
  addTearDown(status.close);
  final opened = <Uri>[];
  final container = await pumpApp(
    tester,
    size: size,
    location: '/family',
    textScale: textScale,
    gated: true,
    sampleMembers: false,
    overrides: [
      authServiceProvider.overrideWithValue(
        FakeAuthService(
          user: AuthUser(id: me, email: '$me@example.com'),
        ),
      ),
      householdRemoteProvider.overrideWithValue(household),
      sheetsRemoteProvider.overrideWithValue(remote),
      sheetStatusProvider.overrideWith((ref) => status.stream),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
    ],
    seedAsync: (db) async {
      await HouseholdRepository(db).replaceFromRemote(household.household!);
    },
  );
  status.add(initial);
  await _settle(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
  return _Env(container, status, remote, opened);
}

Future<void> _show(WidgetTester tester, SheetStatus s, _Env env) async {
  env.status.add(s);
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = _key(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _settle(tester);
}

String _headline(WidgetTester tester) =>
    tester.widget<Text>(_key('sheet-headline')).data!;

void main() {
  setUpAll(loadTestFonts);

  group('permissions', () {
    test('only the owner connects; owner and admin sync', () {
      expect(const Permissions(Role.owner).canConnectSheet, isTrue);
      expect(const Permissions(Role.admin).canConnectSheet, isFalse);
      expect(const Permissions(Role.editor).canConnectSheet, isFalse);
      expect(const Permissions(Role.viewer).canConnectSheet, isFalse);
      expect(const Permissions(Role.owner).canSyncSheet, isTrue);
      expect(const Permissions(Role.admin).canSyncSheet, isTrue);
      expect(const Permissions(Role.editor).canSyncSheet, isFalse);
      expect(const Permissions(Role.viewer).canSyncSheet, isFalse);
    });
  });

  group('status model', () {
    test('progress counts copied expenses', () {
      const s = SheetStatus(
        state: SheetState.copying,
        backfillTotal: 200,
        pending: 150,
      );
      expect(s.copied, 50);
      expect(s.progress, 0.25);
      expect(const SheetStatus(state: SheetState.active).progress, isNull);
    });

    test('polls quickly while connecting or copying, slowly otherwise', () {
      const idle = SheetStatus(state: SheetState.active);
      expect(sheetPollInterval(idle, connecting: false).inSeconds, 20);
      expect(sheetPollInterval(idle, connecting: true).inSeconds, 3);
      expect(
        sheetPollInterval(
          const SheetStatus(state: SheetState.copying),
          connecting: false,
        ).inSeconds,
        3,
      );
    });
  });

  group('status provider', () {
    test(
      'reads the status of the active household and keeps it when offline',
      () async {
        final remote = FakeSheetsRemote(
          status: const SheetStatus(state: SheetState.active),
        );
        final container = ProviderContainer(
          overrides: [
            sheetsRemoteProvider.overrideWithValue(remote),
            activeHouseholdProvider.overrideWith(
              (ref) => Stream.value(
                HouseholdRow(
                  id: 'household-1',
                  name: 'Home',
                  currency: 'SGD',
                  ownerId: _owner,
                  updatedAt: DateTime(2026),
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final seen = Completer<SheetStatus>();
        container.listen(sheetStatusProvider, (_, next) {
          final v = next.value;
          if (v != null && v.isConnected && !seen.isCompleted) {
            seen.complete(v);
          }
        }, fireImmediately: true);
        expect((await seen.future).state, SheetState.active);
        expect(remote.calls, contains('status:household-1'));
      },
    );

    test('without a remote it reports not connected', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final seen = Completer<SheetStatus>();
      container.listen(sheetStatusProvider, (_, next) {
        final v = next.value;
        if (v != null && !seen.isCompleted) seen.complete(v);
      }, fireImmediately: true);
      expect((await seen.future).state, SheetState.notConnected);
    });
  });

  testWidgets('the card is not shown when Supabase is not configured', (
    tester,
  ) async {
    await pumpApp(tester, size: _tablet, location: '/family');
    expect(_key('sheet-card'), findsNothing);
  });

  group('owner', () {
    testWidgets('connects after agreeing to what is sent to Google', (
      tester,
    ) async {
      final env = await _pump(tester, me: _owner);
      expect(_headline(tester), 'Not connected');
      await _tap(tester, 'sheet-connect');
      expect(
        _key('sheet-privacy'),
        findsOneWidget,
        reason: 'the privacy copy comes first',
      );
      expect(find.textContaining('who added it'), findsOneWidget);
      expect(env.opened, isEmpty, reason: 'nothing is opened before agreeing');

      await _tap(tester, 'sheet-privacy-agree');
      expect(env.remote.calls, contains('start:household-1'));
      expect(env.opened.single.host, 'accounts.google.com');
      expect(_headline(tester), 'Waiting for Google');
      expect(_key('sheet-cancel'), findsOneWidget);

      await _show(
        tester,
        SheetStatus(
          state: SheetState.active,
          lastSyncedAt: DateTime(2026, 10, 23, 12),
          spreadsheetUrl: 'https://docs.google.com/spreadsheets/d/x',
        ),
        env,
      );
      expect(_headline(tester), 'Connected');
      expect(find.textContaining('Last synced Oct 23'), findsOneWidget);
    });

    testWidgets('declining the privacy notice sends nothing', (tester) async {
      final env = await _pump(tester, me: _owner);
      await _tap(tester, 'sheet-connect');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(env.remote.calls.where((c) => c.startsWith('start')), isEmpty);
      expect(env.opened, isEmpty);
    });

    testWidgets('shows progress while the first copy runs', (tester) async {
      final env = await _pump(tester, me: _owner);
      await _show(
        tester,
        const SheetStatus(
          state: SheetState.copying,
          backfillTotal: 400,
          pending: 100,
        ),
        env,
      );
      expect(_headline(tester), 'Copying your expenses');
      expect(find.text('300 of 400 done'), findsOneWidget);
      expect(
        tester.widget<LinearProgressIndicator>(_key('sheet-progress')).value,
        0.75,
      );
    });

    testWidgets('connected: open, sync now and disconnect', (tester) async {
      final env = await _pump(
        tester,
        me: _owner,
        initial: SheetStatus(
          state: SheetState.active,
          spreadsheetUrl: 'https://docs.google.com/spreadsheets/d/x',
          lastSyncedAt: DateTime(2026, 10, 23, 12),
        ),
      );
      await _tap(tester, 'sheet-sync-now');
      expect(env.remote.calls, contains('sync:household-1'));
      await _tap(tester, 'sheet-open');
      expect(env.opened.last.toString(), contains('docs.google.com'));

      await _tap(tester, 'sheet-disconnect');
      await _tap(tester, 'sheet-disconnect-confirm');
      expect(env.remote.calls, contains('disconnect:household-1'));
    });

    testWidgets('a revoked connection shows a Reconnect banner', (
      tester,
    ) async {
      final env = await _pump(
        tester,
        me: _owner,
        initial: const SheetStatus(state: SheetState.revoked),
      );
      expect(_headline(tester), 'Google access was removed');
      expect(find.textContaining('Reconnect to keep'), findsOneWidget);
      await _tap(tester, 'sheet-reconnect');
      await _tap(tester, 'sheet-privacy-agree');
      expect(env.remote.calls, contains('start:household-1'));
    });

    testWidgets('server errors are explained, not hidden', (tester) async {
      final env = await _pump(tester, me: _owner);
      env.remote.failNextWith = SheetsError.rateLimited;
      await _tap(tester, 'sheet-connect');
      await _tap(tester, 'sheet-privacy-agree');
      expect(find.text('Too many tries. Wait a few minutes.'), findsOneWidget);
    });
  });

  group('admin', () {
    testWidgets('can sync and open but not connect or disconnect', (
      tester,
    ) async {
      await _pump(
        tester,
        me: _admin,
        initial: SheetStatus(
          state: SheetState.active,
          spreadsheetUrl: 'https://docs.google.com/spreadsheets/d/x',
          lastSyncedAt: DateTime(2026, 10, 23, 12),
        ),
      );
      expect(_key('sheet-sync-now'), findsOneWidget);
      expect(_key('sheet-open'), findsOneWidget);
      expect(_key('sheet-disconnect'), findsNothing);
      expect(_key('sheet-connect'), findsNothing);
    });

    testWidgets('not connected: only the owner can connect', (tester) async {
      await _pump(tester, me: _admin);
      expect(find.text('Only the owner can connect a Google Sheet.'), findsOne);
      expect(_key('sheet-connect'), findsNothing);
    });

    testWidgets('revoked: told to ask the owner, no Reconnect button', (
      tester,
    ) async {
      await _pump(
        tester,
        me: _admin,
        initial: const SheetStatus(state: SheetState.revoked),
      );
      expect(find.text('Ask the owner to reconnect Google.'), findsOneWidget);
      expect(_key('sheet-reconnect'), findsNothing);
    });

    testWidgets('error text is shown to admins', (tester) async {
      await _pump(
        tester,
        me: _admin,
        initial: const SheetStatus(
          state: SheetState.error,
          lastError: 'Sheets API 503',
        ),
      );
      expect(_headline(tester), 'Sync problem');
      expect(find.textContaining('Sheets API 503'), findsOneWidget);
      expect(_key('sheet-sync-now'), findsOneWidget);
    });
  });

  group('view only member', () {
    testWidgets('sees the state read-only, with no buttons at all', (
      tester,
    ) async {
      await _pump(
        tester,
        me: _viewer,
        initial: SheetStatus(
          state: SheetState.active,
          lastSyncedAt: DateTime(2026, 10, 23, 12),
        ),
      );
      expect(_headline(tester), 'Connected');
      for (final k in [
        'sheet-sync-now',
        'sheet-open',
        'sheet-disconnect',
        'sheet-connect',
        'sheet-reconnect',
      ]) {
        expect(_key(k), findsNothing, reason: k);
      }
    });

    testWidgets('error details are not shown', (tester) async {
      await _pump(
        tester,
        me: _viewer,
        initial: const SheetStatus(state: SheetState.error),
      );
      expect(find.text('We will try again. New expenses are kept.'), findsOne);
    });
  });

  group('same on every size', () {
    for (final (name, size) in [
      ('phone', _phone),
      ('tablet', _tablet),
      ('desktop', _desktop),
    ]) {
      testWidgets('$name: the card shows and buttons are tall enough', (
        tester,
      ) async {
        await _pump(tester, me: _owner, size: size);
        expect(_headline(tester), 'Not connected');
        final button = _key('sheet-connect');
        await tester.ensureVisible(button);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      });
    }

    testWidgets('large text does not overflow', (tester) async {
      await _pump(
        tester,
        me: _owner,
        size: _phone,
        textScale: 2,
        initial: SheetStatus(
          state: SheetState.active,
          spreadsheetUrl: 'https://docs.google.com/spreadsheets/d/x',
          lastSyncedAt: DateTime(2026, 10, 23, 12),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
