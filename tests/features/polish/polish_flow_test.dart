import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/expenses/expense_providers.dart';
import 'package:family_expenses/features/privacy/app_lock.dart';
import 'package:family_expenses/features/privacy/csv_share.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_member.dart';
import '../../helpers/test_app.dart';

class _Lock implements AppLockService {
  _Lock({this.supported = true, this.result = true});
  bool supported;
  bool result;
  int asked = 0;
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return result;
  }
}

class _Sharer implements FileSharer {
  final shared = <(String, String, String)>[];
  @override
  Future<void> shareText(
    String filename,
    String content,
    String mimeType,
  ) async => shared.add((filename, content, mimeType));
}

void main() {
  setUpAll(loadTestFonts);

  group('first run', () {
    testWidgets('three cards, then the app; shown once', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'onboarding.done': false},
      );
      expect(find.text('Add an expense in seconds'), findsOneWidget);
      expect(find.text('Spent this month'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pump();
      expect(find.text('See where the money goes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pump();
      expect(find.text('Yours, on your device'), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-skip')), findsNothing);
      await tester.tap(find.text('Get started'));
      await settle(tester);
      expect(find.text('Spent this month'), findsOneWidget);
    });

    testWidgets('Skip goes straight to the app', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'onboarding.done': false},
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await settle(tester);
      expect(find.text('Spent this month'), findsOneWidget);
    });

    testWidgets(
      'fits and meets tap targets at phone and desktop widths, large text',
      (tester) async {
        for (final size in const [Size(360, 640), Size(1280, 800)]) {
          await pumpApp(
            tester,
            size: size,
            prefs: {'onboarding.done': false},
            textScale: 2,
          );
          expect(tester.takeException(), isNull, reason: '$size');
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        }
      },
    );
  });

  group('app lock', () {
    testWidgets('off by default: nothing asked', (tester) async {
      final lock = _Lock();
      await pumpApp(
        tester,
        size: const Size(390, 844),
        overrides: [appLockServiceProvider.overrideWithValue(lock)],
      );
      expect(lock.asked, 0);
      expect(find.text('Spent this month'), findsOneWidget);
    });

    testWidgets(
      'turning it on needs the device to confirm; then a restart is locked',
      (tester) async {
        final lock = _Lock();
        await pumpApp(
          tester,
          size: const Size(1280, 800),
          location: '/appearance',
          overrides: [appLockServiceProvider.overrideWithValue(lock)],
        );
        await settle(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('app-lock')));
        await tester.tap(find.byKey(const ValueKey('app-lock')));
        await settle(tester);
        expect(lock.asked, 1);
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(const ValueKey('app-lock')))
              .value,
          isTrue,
        );
      },
    );

    testWidgets('a restart with the lock on starts locked until unlocked', (
      tester,
    ) async {
      final lock = _Lock(result: false);
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'privacy.appLock': true},
        overrides: [appLockServiceProvider.overrideWithValue(lock)],
      );
      await settle(tester);
      expect(find.text('Family Expenses is locked'), findsOneWidget);
      expect(
        find.text('Spent this month'),
        findsNothing,
        reason: 'content hidden while locked',
      );
      lock.result = true;
      await tester.tap(find.byKey(const ValueKey('unlock')));
      await settle(tester);
      expect(find.text('Spent this month'), findsOneWidget);
    });

    testWidgets('a failed confirmation does not turn it on', (tester) async {
      final lock = _Lock(result: false);
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/appearance',
        overrides: [appLockServiceProvider.overrideWithValue(lock)],
      );
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('app-lock')));
      await tester.tap(find.byKey(const ValueKey('app-lock')));
      await settle(tester);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('app-lock')))
            .value,
        isFalse,
      );
    });

    testWidgets('no switch where the device cannot lock (Linux)', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/appearance',
        overrides: [
          appLockServiceProvider.overrideWithValue(_Lock(supported: false)),
        ],
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('app-lock')), findsNothing);
    });

    testWidgets('re-locks after 30 seconds in the background, not after 5', (
      tester,
    ) async {
      final lock = _Lock();
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'privacy.appLock': true},
        overrides: [appLockServiceProvider.overrideWithValue(lock)],
      );
      await settle(tester);
      expect(
        c.read(appLockProvider).locked,
        isFalse,
        reason: 'unlocked at start by the fake',
      );
      final n = c.read(appLockProvider.notifier);
      final t0 = DateTime(2026, 10, 25, 9);
      n.onLifecycle(AppLifecycleState.paused, t0);
      n.onLifecycle(
        AppLifecycleState.resumed,
        t0.add(const Duration(seconds: 5)),
      );
      expect(c.read(appLockProvider).locked, isFalse);
      n.onLifecycle(AppLifecycleState.paused, t0);
      n.onLifecycle(
        AppLifecycleState.resumed,
        t0.add(const Duration(seconds: 31)),
      );
      expect(c.read(appLockProvider).locked, isTrue);
    });
  });

  group('privacy and data', () {
    testWidgets('exports the expenses as CSV through the share sheet', (
      tester,
    ) async {
      final sharer = _Sharer();
      final c = await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/appearance',
        overrides: [fileSharerProvider.overrideWithValue(sharer)],
      );
      await tester.runAsync(() async {
        await ExpenseRepository(c.read(databaseProvider)).add(
          amountCents: 1250,
          categoryId:
              (await c.read(categoryRepositoryProvider).getAll()).first.id,
          spentOn: DateTime(2026, 10, 2),
          note: '=1+1',
          createdBy: 'You',
        );
      });
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('export-csv')));
      await tester.tap(find.byKey(const ValueKey('export-csv')));
      await settle(tester);
      expect(sharer.shared, hasLength(1));
      final (name, content, mime) = sharer.shared.single;
      expect(name, 'family-expenses.csv');
      expect(mime, 'text/csv');
      expect(content, contains('2026-10-02,12.50,SGD,'));
      expect(content, contains("'=1+1"));
      expect(find.text('Exported 1 expenses'), findsOneWidget);
    });

    testWidgets('the privacy policy page opens and reads', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/appearance',
      );
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('privacy-policy')));
      await tester.tap(find.byKey(const ValueKey('privacy-policy')));
      await settle(tester);
      expect(find.text('What this app is'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Show the introduction again" brings the intro back', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/appearance',
      );
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('show-intro')));
      await tester.tap(find.byKey(const ValueKey('show-intro')));
      await settle(tester);
      expect(find.text('Add an expense in seconds'), findsOneWidget);
    });
  });
}
