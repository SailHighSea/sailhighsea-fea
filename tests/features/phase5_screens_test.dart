import 'package:family_expenses/features/bills/bill_providers.dart';
import 'package:family_expenses/features/bills/domain/bill_calculations.dart';
import 'package:family_expenses/features/expenses/expense_providers.dart';
import 'package:family_expenses/features/bills/reminders/reminder_providers.dart';
import 'package:family_expenses/features/bills/reminders/reminder_plan.dart';
import 'package:family_expenses/features/bills/reminders/reminder_scheduler.dart';
import 'package:family_expenses/features/budgets/budget_providers.dart';
import 'package:family_expenses/features/budgets/domain/budget_calculations.dart';
import 'package:family_expenses/features/goals/goal_providers.dart';
import 'package:family_expenses/features/insights/insights_providers.dart';
import 'package:family_expenses/features/insights/domain/insights_calculations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/phase5_data.dart';
import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

const _phone = Size(390, 844);
const _tablet = Size(1024, 720);
const _desktop = Size(1280, 800);
const _sizes = {'phone': _phone, 'tablet': _tablet, 'desktop': _desktop};

class _FakeScheduler implements ReminderScheduler {
  final List<List<ReminderPlan>> applied = [];
  int permissionRequests = 0;
  int cancels = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<Set<String>> apply(List<ReminderPlan> plans) async {
    applied.add(plans);
    return {for (final p in plans) p.key};
  }

  @override
  Future<void> cancelAll() async => cancels++;

  @override
  void dispose() {}
}

Future<ProviderContainer> _local(
  WidgetTester tester,
  String route, {
  Size size = _desktop,
  bool seed = true,
  double textScale = 1,
  Map<String, Object> prefs = const {},
}) => pumpApp(
  tester,
  size: size,
  location: route,
  textScale: textScale,
  prefs: prefs,
  seedAsync: seed ? seedPhase5 : null,
);

void main() {
  setUpAll(loadTestFonts);

  group('Budgets', () {
    for (final entry in _sizes.entries) {
      testWidgets('${entry.key}: category cards with the mockup states', (
        tester,
      ) async {
        await _local(tester, '/budgets', size: entry.value);
        expect(find.text('Budgets'), findsWidgets);
        expect(key('budgets-subtitle'), findsOneWidget);
        expect(
          tester.widget<Text>(key('budgets-subtitle')).data,
          'October 2026 · S\$1,842 of S\$2,500',
        );
        expect(find.text('S\$612 / S\$800'), findsOneWidget);
        expect(find.text('S\$188 left'), findsOneWidget);
        expect(find.text('Almost at limit · S\$16 left'), findsOneWidget);
        expect(
          find.text('S\$0 / S\$200'),
          findsOneWidget,
          reason: 'Health has a budget and no spending',
        );
        expect(find.text('+ New category'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'tablet and desktop show the ring card; the phone shows the totals in the subtitle',
      (tester) async {
        await _local(tester, '/budgets', size: _desktop);
        expect(find.text('74%'), findsOneWidget);
        expect(find.text('S\$658 left'), findsOneWidget);
        expect(find.text('8 days to go · S\$82 a day'), findsOneWidget);
        await _local(tester, '/budgets', size: _phone);
        expect(find.text('74%'), findsNothing);
      },
    );

    testWidgets('over budget shows how much, and the bar is full', (
      tester,
    ) async {
      final c = await _local(tester, '/budgets', seed: false);
      // One write per runAsync, then let the streams update (Drift refreshes its streams on
      // the test zone's timers).
      final repo = c.read(budgetRepositoryProvider);
      await tester.runAsync(
        () => repo.setBudget(DateTime(2026, 10), 'default-food', 10000),
      );
      await settle(tester);
      await tester.runAsync(
        () => repo.setBudget(DateTime(2026, 10), null, 50000),
      );
      await settle(tester);
      await tester.runAsync(
        () => c
            .read(expenseRepositoryProvider)
            .add(
              amountCents: 15000,
              categoryId: 'default-food',
              spentOn: DateTime(2026, 10, 2),
            ),
      );
      await settle(tester);
      expect(find.text('Over by S\$50'), findsOneWidget);
      expect(find.text('S\$150 / S\$100'), findsOneWidget);
    });

    testWidgets('Edit budgets saves the overall and category amounts', (
      tester,
    ) async {
      final c = await _local(tester, '/budgets');
      await tapKey(tester, 'edit-budgets-button');
      expect(key('edit-budgets'), findsOneWidget);
      await enterKey(tester, 'budget-overall', '3000');
      await enterKey(tester, 'budget-default-food', '900.50');
      await enterKey(tester, 'budget-default-health', '');
      await tapKey(tester, 'budget-save');
      final rows = await tester.runAsync(
        () => c.read(budgetRepositoryProvider).watchAll().first,
      );
      final effective = effectiveBudgets(rows!, DateTime(2026, 10));
      expect(effective[null], 300000);
      expect(effective['default-food'], 90050);
      expect(
        effective.containsKey('default-health'),
        isFalse,
        reason: 'emptied',
      );
      expect(effective['default-bills'], 60000, reason: 'untouched');
      expect(find.text('October 2026 · S\$1,842 of S\$3,000'), findsOneWidget);
    });

    testWidgets('Edit budgets refuses an amount that is not a number', (
      tester,
    ) async {
      await _local(tester, '/budgets');
      await tapKey(tester, 'edit-budgets-button');
      await enterKey(tester, 'budget-overall', '1.2.3');
      await tapKey(tester, 'budget-save');
      expect(key('budget-error'), findsOneWidget);
      expect(
        key('edit-budgets'),
        findsOneWidget,
        reason: 'the sheet stays open',
      );
    });

    testWidgets('+ New category creates the category and its budget', (
      tester,
    ) async {
      await _local(tester, '/budgets');
      await tapKey(tester, 'new-category-tile');
      await enterKey(tester, 'new-category-name', 'Pets');
      await enterKey(tester, 'new-category-budget', '120');
      await tapKey(tester, 'new-category-save');
      expect(find.text('Pets'), findsOneWidget);
      expect(find.text('S\$0 / S\$120'), findsOneWidget);
    });

    testWidgets(
      'month navigation shows another month; earlier budgets carry over',
      (tester) async {
        await _local(tester, '/budgets');
        await tester.tap(find.bySemanticsLabel('Next month'));
        await settle(tester);
        expect(
          tester.widget<Text>(key('budgets-subtitle')).data,
          'November 2026 · S\$0 of S\$2,500',
        );
        expect(
          find.text('S\$0 / S\$800'),
          findsOneWidget,
          reason: "October's food budget carries over",
        );
      },
    );

    testWidgets('no budgets at all: says so', (tester) async {
      await _local(tester, '/budgets', seed: false);
      expect(key('budgets-empty'), findsOneWidget);
    });

    testWidgets('a view-only member sees budgets but cannot edit them', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/budgets',
        size: _tablet,
      );
      expect(find.text('S\$612 / S\$800'), findsOneWidget);
      expect(key('edit-budgets-button'), findsNothing);
      expect(key('new-category-tile'), findsNothing);
    });

    testWidgets('an admin can edit budgets', (tester) async {
      await pumpAsMember(
        tester,
        me: adminUser,
        location: '/budgets',
        size: _tablet,
      );
      expect(key('edit-budgets-button'), findsOneWidget);
    });
  });

  group('Goals', () {
    for (final entry in _sizes.entries) {
      testWidgets('${entry.key}: total, goals and recent contributions', (
        tester,
      ) async {
        await _local(tester, '/goals', size: entry.value);
        expect(find.text('Savings goals'), findsOneWidget);
        expect(find.text('S\$6,300'), findsOneWidget);
        expect(find.text('Saved across 3 goals'), findsOneWidget);
        expect(find.text('40%'), findsOneWidget);
        expect(find.text('75%'), findsOneWidget);
        expect(find.text('33%'), findsOneWidget);
        expect(find.text('S\$1,200 of S\$3,000'), findsOneWidget);
        expect(find.text('S\$250 a month · done by Apr 2027'), findsOneWidget);
        expect(find.text('Recent contributions'), findsOneWidget);
        expect(find.text('+S\$150'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('New goal adds a goal', (tester) async {
      await _local(tester, '/goals');
      await tapKey(tester, 'new-goal-button');
      await enterKey(tester, 'goal-name', 'Bicycle');
      await enterKey(tester, 'goal-target', '900');
      await enterKey(tester, 'goal-monthly', '100');
      await enterKey(tester, 'goal-saved', '300');
      await tapKey(tester, 'goal-save');
      expect(find.text('Bicycle'), findsOneWidget);
      expect(find.text('S\$300 of S\$900'), findsOneWidget);
      expect(find.text('Saved across 4 goals'), findsOneWidget);
      expect(find.text('S\$6,600'), findsOneWidget);
    });

    testWidgets('a goal needs a name and a target', (tester) async {
      await _local(tester, '/goals');
      await tapKey(tester, 'new-goal-button');
      await tapKey(tester, 'goal-save');
      expect(key('goal-error'), findsOneWidget);
      await enterKey(tester, 'goal-name', 'X');
      await tapKey(tester, 'goal-save');
      expect(find.text('Enter the amount you are saving for.'), findsOneWidget);
    });

    testWidgets('Add money adds a contribution and updates the totals', (
      tester,
    ) async {
      final c = await _local(tester, '/goals');
      await tapKey(tester, 'add-money-button');
      final laptop = (await tester.runAsync(
        () => c.read(goalRepositoryProvider).watchGoals().first,
      ))!.firstWhere((g) => g.name == 'New laptop');
      await tapKey(tester, 'add-money-goal-${laptop.id}');
      await enterKey(tester, 'add-money-amount', '100');
      await tapKey(tester, 'add-money-save');
      expect(find.text('S\$700 of S\$1,800'), findsOneWidget);
      expect(find.text('S\$6,400'), findsOneWidget);
      expect(find.text('+S\$100'), findsWidgets);
    });

    testWidgets('Add money needs an amount above zero', (tester) async {
      await _local(tester, '/goals');
      await tapKey(tester, 'add-money-button');
      await enterKey(tester, 'add-money-amount', '0');
      await tapKey(tester, 'add-money-save');
      expect(key('add-money-error'), findsOneWidget);
    });

    testWidgets('editing a goal changes it; deleting offers Undo', (
      tester,
    ) async {
      await _local(tester, '/goals');
      await tapText(tester, 'New laptop');
      expect(key('goal-form'), findsOneWidget);
      await enterKey(tester, 'goal-name', 'Gaming laptop');
      await tapKey(tester, 'goal-save');
      expect(
        find.text('Gaming laptop'),
        findsWidgets,
        reason: 'the card and its contribution',
      );

      await tapText(tester, 'Gaming laptop');
      await tapKey(tester, 'goal-delete');
      expect(find.text('Gaming laptop'), findsNothing);
      expect(find.text('Saved across 2 goals'), findsOneWidget);
      await tapText(tester, 'Undo');
      expect(find.text('Gaming laptop'), findsWidgets);
    });

    testWidgets('a goal that is reached says so', (tester) async {
      final c = await _local(tester, '/goals', seed: false);
      await tester.runAsync(
        () => c
            .read(goalRepositoryProvider)
            .add(name: 'Done', targetCents: 1000, savedCents: 1000),
      );
      await settle(tester);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('goal reached'), findsOneWidget);
    });

    testWidgets('no goals: invites the owner to add one', (tester) async {
      await _local(tester, '/goals', seed: false);
      expect(key('goals-empty'), findsOneWidget);
      expect(
        key('add-money-button'),
        findsNothing,
        reason: 'nothing to add money to',
      );
    });

    testWidgets('a view-only member sees goals but has no buttons', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: viewerUser,
        location: '/goals',
        size: _tablet,
      );
      expect(find.text('S\$6,300'), findsOneWidget);
      expect(key('new-goal-button'), findsNothing);
      expect(key('add-money-button'), findsNothing);
      await tester.tap(find.text('Holiday trip').first);
      await settle(tester);
      expect(key('goal-form'), findsNothing, reason: 'cannot open the editor');
    });

    testWidgets('recent contributions name who added the money', (
      tester,
    ) async {
      await pumpAsMember(
        tester,
        me: ownerUser,
        location: '/goals',
        size: _desktop,
      );
      // Seeded as plain names ("Maya"), shown as they are.
      expect(find.textContaining('Maya · Oct 15'), findsOneWidget);
    });
  });

  group('Bills', () {
    for (final entry in _sizes.entries) {
      testWidgets('${entry.key}: hero, rows and the reminder switch', (
        tester,
      ) async {
        await _local(tester, '/bills', size: entry.value);
        expect(find.text('Upcoming bills'), findsOneWidget);
        expect(find.text('Due by 15 Nov'), findsOneWidget);
        expect(find.text('S\$319.28'), findsOneWidget);
        expect(find.text('5 recurring bills'), findsOneWidget);
        expect(find.text('Electricity'), findsOneWidget);
        expect(find.text('Due in 5 days'), findsOneWidget);
        expect(find.text('S\$96.40'), findsOneWidget);
        expect(find.text('Remind everyone'), findsOneWidget);
        expect(find.text('3 days before each due date'), findsOneWidget);
        expect(find.text('Mark paid'), findsNWidgets(5));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Mark paid moves the bill on and Undo brings it back', (
      tester,
    ) async {
      final c = await _local(tester, '/bills');
      final bills = (await tester.runAsync(
        () => c.read(billRepositoryProvider).watchAll().first,
      ))!;
      final electricity = bills.firstWhere((b) => b.name == 'Electricity');
      await tapKey(tester, 'mark-paid-${electricity.id}');
      expect(
        find.textContaining('Electricity marked paid. Next due 28 Nov'),
        findsOneWidget,
      );
      expect(
        find.text('Due by 28 Nov'),
        findsOneWidget,
        reason: 'the last due date is now Electricity',
      );
      expect(
        find.text('Due in 36 days'),
        findsOneWidget,
        reason: 'Nov 28 is 36 days after Oct 23',
      );

      await tapText(tester, 'Undo');
      expect(find.text('Due in 5 days'), findsOneWidget);
      expect(find.text('Due by 15 Nov'), findsOneWidget);
    });

    testWidgets('Add bill creates a bill with its next due date', (
      tester,
    ) async {
      await _local(tester, '/bills');
      await tapKey(tester, 'add-bill-button');
      await enterKey(tester, 'bill-name', 'Water');
      await enterKey(tester, 'bill-amount', '24.50');
      await tapKey(tester, 'bill-save');
      expect(find.text('Water'), findsOneWidget);
      expect(find.text('S\$24.50'), findsOneWidget);
      expect(find.text('6 recurring bills'), findsOneWidget);
    });

    testWidgets('a bill needs a name and an amount', (tester) async {
      await _local(tester, '/bills');
      await tapKey(tester, 'add-bill-button');
      await tapKey(tester, 'bill-save');
      expect(find.text('Give the bill a name.'), findsOneWidget);
      await enterKey(tester, 'bill-name', 'Water');
      await tapKey(tester, 'bill-save');
      expect(find.text('Enter the amount of the bill.'), findsOneWidget);
    });

    testWidgets('editing a bill changes it; deleting offers Undo', (
      tester,
    ) async {
      await _local(tester, '/bills');
      await tapText(tester, 'Internet');
      expect(key('bill-form'), findsOneWidget);
      await enterKey(tester, 'bill-amount', '59.90');
      await tapKey(tester, 'bill-save');
      expect(find.text('S\$59.90'), findsOneWidget);

      await tapText(tester, 'Internet');
      await tapKey(tester, 'bill-delete');
      expect(find.text('Internet'), findsNothing);
      expect(find.text('4 recurring bills'), findsOneWidget);
      await tapText(tester, 'Undo');
      expect(find.text('Internet'), findsOneWidget);
    });

    testWidgets('overdue bills say so in amber', (tester) async {
      final c = await _local(tester, '/bills', seed: false);
      await tester.runAsync(
        () => c
            .read(billRepositoryProvider)
            .add(
              name: 'Late',
              amountCents: 1000,
              nextDueOn: DateTime(2026, 10, 20),
            ),
      );
      await settle(tester);
      expect(find.text('Overdue by 3 days'), findsOneWidget);
    });

    testWidgets('a one-off bill disappears once paid', (tester) async {
      final c = await _local(tester, '/bills', seed: false);
      final id = (await tester.runAsync(
        () => c
            .read(billRepositoryProvider)
            .add(
              name: 'Fine',
              amountCents: 1000,
              nextDueOn: DateTime(2026, 10, 25),
              repeat: BillRepeat.once,
            ),
      ))!;
      await settle(tester);
      await tapKey(tester, 'mark-paid-$id');
      expect(find.text('Fine'), findsNothing);
      expect(key('bills-empty'), findsOneWidget);
    });

    testWidgets(
      'a view-only member sees what is due but cannot mark paid or add',
      (tester) async {
        await pumpAsMember(
          tester,
          me: viewerUser,
          location: '/bills',
          size: _tablet,
        );
        expect(find.text('Electricity'), findsOneWidget);
        expect(find.text('Mark paid'), findsNothing);
        expect(key('add-bill-button'), findsNothing);
      },
    );

    testWidgets('the reminder switch is remembered and asks for permission', (
      tester,
    ) async {
      final scheduler = _FakeScheduler();
      final c = await pumpApp(
        tester,
        size: _tablet,
        location: '/bills',
        seedAsync: seedPhase5,
        overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
      );
      expect(c.read(reminderSettingsProvider).enabled, isTrue);
      await tapKey(tester, 'reminders-switch');
      expect(c.read(reminderSettingsProvider).enabled, isFalse);
      expect(
        scheduler.cancels,
        greaterThan(0),
        reason: 'switching off cancels scheduled reminders',
      );
      await tapKey(tester, 'reminders-switch');
      expect(c.read(reminderSettingsProvider).enabled, isTrue);
      expect(scheduler.permissionRequests, 1, reason: 'asked when switched on');
    });
  });

  group('Reminders follow the bills', () {
    testWidgets(
      'scheduled once the bills load, replanned on change, not repeated',
      (tester) async {
        final scheduler = _FakeScheduler();
        final c = await pumpApp(
          tester,
          size: _tablet,
          location: '/home',
          seedAsync: seedPhase5,
          overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
        );
        await settle(tester);
        expect(scheduler.applied, isNotEmpty);
        final first = scheduler.applied.last;
        // Electricity (Oct 28) is 5 days away: its reminder is on Oct 25 at 09:00.
        final electricity = first.firstWhere(
          (p) => p.body.startsWith('Electricity'),
        );
        expect(electricity.when, DateTime(2026, 10, 25, 9));
        // Internet (Oct 30): Oct 27. Phone plan (Nov 2): Oct 30. All in the future, none immediate.
        expect(first.every((p) => !p.immediate), isTrue);

        final before = scheduler.applied.length;
        await tester.runAsync(
          () => c
              .read(billRepositoryProvider)
              .add(
                name: 'Gym',
                amountCents: 3000,
                nextDueOn: DateTime(2026, 10, 24),
              ),
        );
        await settle(tester);
        expect(scheduler.applied.length, greaterThan(before));
        final gym = scheduler.applied.last.firstWhere(
          (p) => p.body.startsWith('Gym'),
        );
        expect(
          gym.immediate,
          isTrue,
          reason: 'already inside the 3 day window',
        );

        // Re-planning does not show the same reminder again.
        await tester.runAsync(
          () => c
              .read(billRepositoryProvider)
              .add(
                name: 'Other',
                amountCents: 100,
                nextDueOn: DateTime(2026, 12, 24),
              ),
        );
        await settle(tester);
        expect(
          scheduler.applied.last.where((p) => p.body.startsWith('Gym')),
          isEmpty,
        );
      },
    );
  });

  group('Insights', () {
    for (final entry in _sizes.entries) {
      testWidgets('${entry.key}: stats, charts, breakdown and notes', (
        tester,
      ) async {
        await _local(tester, '/insights', size: entry.value);
        expect(find.text('Insights'), findsWidgets);
        expect(find.text('Spent'), findsOneWidget);
        expect(find.text('S\$1,842'), findsOneWidget);
        expect(find.text('Daily average'), findsOneWidget);
        expect(find.text('S\$80'), findsOneWidget);
        expect(find.text('Projected month-end'), findsOneWidget);
        expect(find.text('S\$2,483'), findsOneWidget);
        expect(find.text('Last 6 months'), findsOneWidget);
        expect(find.text('Daily spending, 1 to 23 Oct'), findsOneWidget);
        expect(find.text('Where it went in October'), findsOneWidget);
        expect(find.text('Who spent what'), findsOneWidget);
        expect(
          find.text(
            'At this pace you finish October at about S\$2,483, under your S\$2,500 budget.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Transport is at 95% of its budget with 8 days left.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Week and Year switch the period', (tester) async {
      final c = await _local(tester, '/insights');
      await tapText(tester, 'Week');
      expect(c.read(insightsPeriodProvider), InsightsPeriod.week);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('Vs previous week'), findsOneWidget);
      await tapText(tester, 'Year');
      expect(find.text('Last 12 months'), findsOneWidget);
      expect(find.text('Highest month'), findsOneWidget);
      await tapText(tester, 'Month');
      expect(find.text('Last 6 months'), findsOneWidget);
    });

    testWidgets('no spending: a friendly empty state', (tester) async {
      await _local(tester, '/insights', seed: false);
      expect(key('insights-empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('large text does not overflow', (tester) async {
      await _local(tester, '/insights', size: _phone, textScale: 2);
      expect(tester.takeException(), isNull);
      await _local(tester, '/budgets', size: _phone, textScale: 2);
      expect(tester.takeException(), isNull);
      await _local(tester, '/goals', size: _phone, textScale: 2);
      expect(tester.takeException(), isNull);
      await _local(tester, '/bills', size: _phone, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('Home reads the real data', () {
    testWidgets('next bill, goal and budget come from what was set up', (
      tester,
    ) async {
      await _local(tester, '/home', size: _phone);
      expect(find.text('Electricity'), findsOneWidget);
      expect(find.textContaining('S\$96.40'), findsOneWidget);
      expect(
        find.text('Holiday trip goal').evaluate().length +
            find.text('Emergency fund goal').evaluate().length +
            find.text('New laptop goal').evaluate().length,
        1,
      );
      expect(find.text('Nothing due'), findsNothing);
      expect(find.text('No goal yet'), findsNothing);
    });

    testWidgets('the budget on Home is the overall budget that was set', (
      tester,
    ) async {
      final c = await _local(tester, '/home', size: _phone);
      await tester.runAsync(
        () => c
            .read(budgetRepositoryProvider)
            .setBudget(DateTime(2026, 10), null, 400000),
      );
      await settle(tester);
      expect(find.textContaining('S\$4,000'), findsWidgets);
    });

    testWidgets('without bills or goals the cards show their empty states', (
      tester,
    ) async {
      await _local(tester, '/home', size: _phone, seed: false);
      expect(find.text('Nothing due'), findsOneWidget);
      expect(find.text('No goal yet'), findsOneWidget);
    });
  });
}
