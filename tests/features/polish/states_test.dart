import 'package:family_expenses/core/theme/app_theme.dart';
import 'package:family_expenses/core/theme/appearance_settings.dart';
import 'package:family_expenses/core/theme/color_themes.dart';
import 'package:family_expenses/core/widgets/async_placeholder.dart';
import 'package:family_expenses/features/bills/bill_providers.dart';
import 'package:family_expenses/features/budgets/budget_providers.dart';
import 'package:family_expenses/features/goals/goal_providers.dart';
import 'package:family_expenses/features/home/home_providers.dart';
import 'package:family_expenses/features/insights/insights_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(loadTestFonts);

  Object boom() => StateError('boom');
  final cases = <String, (String, Override Function(bool failed))>{
    '/home': (
      'expenses',
      (f) => homeSummaryProvider.overrideWithValue(
        f ? AsyncError(boom(), StackTrace.empty) : const AsyncLoading(),
      ),
    ),
    '/budgets': (
      'budgets',
      (f) => budgetsSummaryProvider.overrideWithValue(
        f ? AsyncError(boom(), StackTrace.empty) : const AsyncLoading(),
      ),
    ),
    '/insights': (
      'insights',
      (f) => insightsProvider.overrideWithValue(
        f ? AsyncError(boom(), StackTrace.empty) : const AsyncLoading(),
      ),
    ),
    '/goals': (
      'goals',
      (f) => goalViewsProvider.overrideWithValue(
        f ? AsyncError(boom(), StackTrace.empty) : const AsyncLoading(),
      ),
    ),
    '/bills': (
      'bills',
      (f) => upcomingBillsProvider.overrideWithValue(
        f ? AsyncError(boom(), StackTrace.empty) : const AsyncLoading(),
      ),
    ),
  };

  for (final e in cases.entries) {
    final (what, override) = e.value;
    testWidgets(
      '${e.key}: a failure is a sentence and Try again, not an exception text',
      (tester) async {
        await pumpApp(
          tester,
          size: const Size(390, 844),
          location: e.key,
          overrides: [override(true)],
        );
        await tester.pump();
        expect(
          find.text('Could not load $what. Your data on this device is safe.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('boom'),
          findsNothing,
          reason: 'no raw exception text',
        );
        expect(find.byKey(const ValueKey('retry')), findsOneWidget);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      },
    );
  }

  testWidgets('the loading spinner is announced and Try again calls back', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(const AppearanceSettings(), ThemeVariant.light),
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(
                height: 120,
                child: AsyncPlaceholder(what: 'bills'),
              ),
              SizedBox(
                height: 240,
                child: AsyncPlaceholder(
                  what: 'goals',
                  error: 'x',
                  onRetry: () => retried++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Loading bills'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry')));
    expect(retried, 1);
    handle.dispose();
  });
}
