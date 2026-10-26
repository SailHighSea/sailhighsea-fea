import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/expenses/expense_providers.dart';
import 'package:family_expenses/core/sheets_sync/sheets_settings.dart';
import 'package:family_expenses/core/theme/appearance_provider.dart';
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
    testWidgets('two cards, then the choice of where data lives; shown once', (
      tester,
    ) async {
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
      expect(find.text('Where should your data live?'), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-skip')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('start-local')));
      await settle(tester);
      expect(find.text('Spent this month'), findsOneWidget);
    });

    testWidgets('the last page says nothing is shared with the developer', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'onboarding.done': false},
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pump();
      expect(
        find.text(
          'Nothing is shared with the app developer. Everything stays on this device or in your own Google account.',
        ),
        findsOneWidget,
      );
      expect(find.text('Sync locally, on this device'), findsOneWidget);
      expect(find.text('Import expenses from a file first'), findsOneWidget);
    });

    testWidgets(
      'Sheets mode offers Google Drive; the button opens the Family page',
      (tester) async {
        await pumpApp(
          tester,
          size: const Size(390, 844),
          prefs: {'onboarding.done': false},
          overrides: [
            backendModeProvider.overrideWithValue(BackendMode.sheets),
          ],
        );
        await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
        await tester.pump();
        expect(find.text('Sign in to Google Drive'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('start-google')));
        await settle(tester);
        expect(find.text('Family'), findsWidgets);
        expect(find.byKey(const ValueKey('google-sign-in')), findsWidgets);
      },
    );

    testWidgets('local-only builds do not offer a sign-in', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'onboarding.done': false},
        overrides: [backendModeProvider.overrideWithValue(BackendMode.local)],
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pump();
      expect(find.byKey(const ValueKey('start-google')), findsNothing);
    });

    testWidgets('Import from the start page opens the import screen', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'onboarding.done': false},
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('start-import')));
      await settle(tester);
      expect(find.text('Import expenses'), findsOneWidget);
    });

    testWidgets('the start page lets you pick a theme, applied at once', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'onboarding.done': false},
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pump();
      for (final m in ['dark', 'pureBlack', 'light']) {
        await tester.ensureVisible(find.byKey(ValueKey('start-theme-$m')));
        await tester.tap(find.byKey(ValueKey('start-theme-$m')));
        await tester.pump();
        expect(c.read(appearanceProvider).mode.name, m);
      }
    });

    testWidgets(
      'the start page lets you pick any currency, with search, and keeps it',
      (tester) async {
        final c = await pumpApp(
          tester,
          size: const Size(390, 844),
          prefs: {'onboarding.done': false},
        );
        await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
        await tester.pump();
        expect(c.read(appearanceProvider).currencyCode, 'SGD');
        await tester.ensureVisible(
          find.byKey(const ValueKey('start-currency')),
        );
        await tester.tap(find.byKey(const ValueKey('start-currency')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('currency-list')), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('currency-search')),
          'qatar',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('currency-QAR')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('currency-list')),
          findsNothing,
          reason: 'closes after choosing',
        );
        expect(c.read(appearanceProvider).currencyCode, 'QAR');
        expect(find.textContaining('QAR  Qatari riyal'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const ValueKey('start-local')));
        await tester.tap(find.byKey(const ValueKey('start-local')));
        await settle(tester);
        expect(
          find.textContaining('QR'),
          findsWidgets,
          reason: 'Home now shows the chosen currency',
        );
      },
    );

    for (final size in const {
      'phone': Size(360, 640),
      'desktop': Size(1280, 800),
    }.entries) {
      testWidgets(
        'the start page fits with the currency list open on ${size.key}, large text',
        (tester) async {
          await pumpApp(
            tester,
            size: size.value,
            prefs: {'onboarding.done': false},
            textScale: 2,
          );
          await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
          await tester.pump();
          await tester.ensureVisible(
            find.byKey(const ValueKey('start-currency')),
          );
          await tester.tap(find.byKey(const ValueKey('start-currency')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        },
      );
    }

    testWidgets('Skip goes to the choice, not past it', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'onboarding.done': false},
      );
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pump();
      expect(find.text('Where should your data live?'), findsOneWidget);
      expect(find.text('Spent this month'), findsNothing);
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
