import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/money/currency.dart';
import 'package:family_expenses/core/money/money_format.dart';
import 'package:family_expenses/core/money/money_input.dart';
import 'package:family_expenses/features/bills/domain/bill_calculations.dart';
import 'package:family_expenses/features/bills/reminders/reminder_plan.dart';
import 'package:family_expenses/features/budgets/domain/budget_calculations.dart';
import 'package:family_expenses/features/goals/domain/goal_calculations.dart';
import 'package:family_expenses/features/insights/domain/insights_calculations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/phase5_data.dart';

final _now = DateTime(2026, 10, 23, 12);
final _money = MoneyFormatter(currencyByCode('SGD'), locale: 'en_US');

BudgetRow _budget(
  String id,
  String month,
  String? category,
  int cents, {
  DateTime? deleted,
  DateTime? updated,
}) => BudgetRow(
  id: id,
  householdId: 'h',
  month: month,
  categoryId: category,
  amountCents: cents,
  updatedAt: updated ?? DateTime(2026, 1, 1),
  deletedAt: deleted,
  dirty: false,
);

ExpenseRow _expense(
  String day,
  int cents,
  String category, {
  String? by,
  DateTime? deleted,
}) => ExpenseRow(
  id: '$day-$cents-$category',
  householdId: 'h',
  amountCents: cents,
  categoryId: category,
  note: '',
  spentOn: day,
  createdBy: by,
  receiptPath: null,
  updatedAt: DateTime(2026, 10, 1),
  deletedAt: deleted,
  dirty: false,
);

CategoryRow _cat(String id, String name, String color) => CategoryRow(
  id: id,
  householdId: 'h',
  name: name,
  color: color,
  icon: null,
  sort: 0,
  updatedAt: DateTime(2026),
  deletedAt: null,
  dirty: false,
);

final _categories = [
  _cat('default-food', 'Food', 'food'),
  _cat('default-bills', 'Bills', 'bills'),
  _cat('default-transport', 'Transport', 'transport'),
  _cat('default-fun', 'Fun', 'fun'),
  _cat('default-other', 'Other', 'other'),
];

BillRow _bill(
  String id,
  int cents,
  String due, {
  String repeat = 'monthly',
  int? day,
  String? paid,
  DateTime? deleted,
}) => BillRow(
  id: id,
  householdId: 'h',
  name: id,
  amountCents: cents,
  dueDay: day ?? int.parse(due.substring(8)),
  repeat: repeat,
  nextDueOn: due,
  lastPaidOn: paid,
  updatedAt: DateTime(2026),
  deletedAt: deleted,
  dirty: false,
);

void main() {
  group('money input', () {
    final sgd = currencyByCode('SGD');
    test('reads plain amounts without float maths', () {
      expect(parseMoneyInput('12', sgd), 1200);
      expect(parseMoneyInput('12.5', sgd), 1250);
      expect(parseMoneyInput('12.05', sgd), 1205);
      expect(parseMoneyInput('0.07', sgd), 7);
      expect(parseMoneyInput('1,250.00', sgd), 125000);
      expect(parseMoneyInput('.5', sgd), 50);
      expect(parseMoneyInput(' 3 ', sgd), 300);
      expect(parseMoneyInput('19.99', sgd), 1999);
    });
    test('refuses what is not an amount', () {
      expect(parseMoneyInput('', sgd), isNull);
      expect(parseMoneyInput('abc', sgd), isNull);
      expect(parseMoneyInput('1.2.3', sgd), isNull);
      expect(
        parseMoneyInput('1.234', sgd),
        isNull,
        reason: 'too many decimals',
      );
      expect(parseMoneyInput('-5', sgd), isNull);
      expect(parseMoneyInput('1234567890', sgd), isNull);
    });
    test('currencies without decimals', () {
      final jpy = currencyByCode('JPY');
      expect(
        parseMoneyInput('500', jpy),
        500 * jpy.minorFactor ~/ jpy.minorFactor,
      );
    });
  });

  group('budgets', () {
    test('ids are fixed per month and category', () {
      expect(budgetId(DateTime(2026, 10, 17), null), 'b:2026-10:overall');
      expect(
        budgetId(DateTime(2026, 10), 'default-food'),
        'b:2026-10:default-food',
      );
    });

    test(
      'a month uses the latest earlier budget; a deleted row means none',
      () {
        final rows = [
          _budget('a', '2026-08-01', 'f', 100),
          _budget('b', '2026-09-01', 'f', 200),
          _budget('c', '2026-11-01', 'f', 999),
          _budget('d', '2026-08-01', 't', 50),
          _budget('e', '2026-10-01', 't', 50, deleted: DateTime(2026, 10, 2)),
        ];
        final oct = effectiveBudgets(rows, DateTime(2026, 10));
        expect(oct['f'], 200, reason: 'latest not after October');
        expect(
          oct.containsKey('t'),
          isFalse,
          reason: 'deleted from October on',
        );
        expect(effectiveBudgets(rows, DateTime(2026, 9))['t'], 50);
        expect(effectiveBudgets(rows, DateTime(2026, 7)), isEmpty);
        expect(effectiveBudgets(rows, DateTime(2026, 12))['f'], 999);
      },
    );

    test('state turns amber at 90% and rose over 100%', () {
      BudgetLine line(int spent) => BudgetLine(
        categoryId: 'c',
        name: 'C',
        colorKey: 'c',
        budgetCents: 10000,
        spentCents: spent,
      );
      expect(line(8999).state, BudgetState.ok);
      expect(line(9000).state, BudgetState.nearLimit);
      expect(line(10000).state, BudgetState.nearLimit);
      expect(line(10001).state, BudgetState.over);
      expect(line(10001).overCents, 1);
      expect(line(5000).percent, 50);
      expect(line(20000).fraction, 1.0);
    });

    test('summary matches the mockup numbers', () {
      final rows = [
        _budget('o', '2026-10-01', null, 250000),
        _budget('f', '2026-10-01', 'default-food', 80000),
        _budget('t', '2026-10-01', 'default-transport', 30000),
      ];
      final expenses = [
        _expense('2026-10-03', 61200, 'default-food'),
        _expense('2026-10-05', 52000, 'default-bills'),
        _expense('2026-10-08', 28400, 'default-transport'),
        _expense('2026-10-12', 21000, 'default-fun'),
        _expense('2026-10-20', 21600, 'default-other'),
        _expense('2026-09-30', 99999, 'default-food'),
        _expense(
          '2026-10-21',
          5000,
          'default-food',
          deleted: DateTime(2026, 10, 22),
        ),
      ];
      final s = buildBudgetsSummary(
        month: DateTime(2026, 10),
        now: _now,
        budgetRows: rows,
        expenses: expenses,
        categories: _categories,
      );
      expect(s.spentCents, 184200);
      expect(s.overallCents, 250000);
      expect(s.leftCents, 65800);
      expect(s.percent, 74);
      expect(s.daysLeft, 8);
      expect(s.perDayCents, 8225, reason: '658 / 8 days, rounded');
      expect(s.lines.map((l) => l.name), ['Food', 'Transport']);
      expect(s.lines.last.state, BudgetState.nearLimit);
      expect(s.lines.last.leftCents, 1600);
      expect(s.hasOverallBudget, isTrue);
    });

    test(
      'without an overall budget the default is used; past and future months',
      () {
        final s = buildBudgetsSummary(
          month: DateTime(2026, 10),
          now: _now,
          budgetRows: const [],
          expenses: const [],
          categories: _categories,
        );
        expect(s.overallCents, defaultMonthlyBudgetCents);
        expect(s.hasOverallBudget, isFalse);
        final past = buildBudgetsSummary(
          month: DateTime(2026, 8),
          now: _now,
          budgetRows: const [],
          expenses: const [],
          categories: _categories,
        );
        expect(past.daysLeft, 0);
        expect(past.perDayCents, 0);
        final future = buildBudgetsSummary(
          month: DateTime(2026, 12),
          now: _now,
          budgetRows: const [],
          expenses: const [],
          categories: _categories,
        );
        expect(future.daysLeft, 31);
      },
    );

    test('over the overall budget', () {
      final s = buildBudgetsSummary(
        month: DateTime(2026, 10),
        now: _now,
        budgetRows: [_budget('o', '2026-10-01', null, 10000)],
        expenses: [_expense('2026-10-02', 15000, 'default-food')],
        categories: _categories,
      );
      expect(s.isOver, isTrue);
      expect(s.leftCents, -5000);
      expect(s.perDayCents, 0);
      expect(s.fraction, 1.0);
    });
  });

  group('goals', () {
    GoalRow goal(
      String id,
      String name,
      int target,
      int saved,
      int monthly, {
      String? due,
      DateTime? deleted,
    }) => GoalRow(
      id: id,
      householdId: 'h',
      name: name,
      targetCents: target,
      savedCents: saved,
      monthlyCents: monthly,
      dueOn: due,
      updatedAt: DateTime(2026),
      deletedAt: deleted,
      dirty: false,
    );
    GoalContributionRow add(
      String goal,
      int cents, {
      DateTime? deleted,
      String day = '2026-10-15',
      String? by,
    }) => GoalContributionRow(
      id: '$goal-$cents-$day',
      householdId: 'h',
      goalId: goal,
      amountCents: cents,
      contributedOn: day,
      addedBy: by,
      updatedAt: DateTime(2026, 10, 15),
      deletedAt: deleted,
      dirty: false,
    );

    test('saved is the opening balance plus live contributions', () {
      final views = buildGoalViews(
        goals: [
          goal('g', 'Trip', 300000, 100000, 15000),
          goal('x', 'Gone', 100, 0, 0, deleted: DateTime(2026)),
        ],
        contributions: [
          add('g', 15000),
          add('g', 5000),
          add('g', 99999, deleted: DateTime(2026, 10, 16)),
        ],
        now: _now,
      );
      expect(views, hasLength(1));
      expect(views.single.savedCents, 120000);
      expect(views.single.percent, 40);
      expect(views.single.remainingCents, 180000);
    });

    test('projected finish is whole months at the monthly amount', () {
      expect(
        projectFinish(remainingCents: 180000, monthlyCents: 15000, now: _now),
        DateTime(2027, 10),
      );
      expect(
        projectFinish(remainingCents: 150001, monthlyCents: 15000, now: _now),
        DateTime(2027, 9),
        reason: 'rounds up',
      );
      expect(
        projectFinish(remainingCents: 0, monthlyCents: 0, now: _now),
        DateTime(2026, 10),
      );
      expect(
        projectFinish(remainingCents: 100, monthlyCents: 0, now: _now),
        isNull,
      );
    });

    test('labels', () {
      GoalView view(GoalRow g, int saved, DateTime? finish) =>
          GoalView(goal: g, savedCents: saved, projectedFinish: finish);
      expect(
        doneByLabel(view(goal('g', 'T', 100, 0, 10), 40, DateTime(2027, 10))),
        'done by Oct 2027',
      );
      expect(
        doneByLabel(
          view(goal('g', 'T', 100, 100, 10), 100, DateTime(2026, 10)),
        ),
        'goal reached',
      );
      expect(
        doneByLabel(
          view(goal('g', 'T', 100, 0, 0, due: '2028-03-01'), 0, null),
        ),
        'aim for Mar 2028',
      );
      expect(
        doneByLabel(view(goal('g', 'T', 100, 0, 0), 0, null)),
        'no monthly amount yet',
      );
    });

    test('percent never rounds up to 100 early', () {
      final v = GoalView(
        goal: goal('g', 'T', 1000, 996, 0),
        savedCents: 996,
        projectedFinish: null,
      );
      expect(v.percent, 99);
      expect(v.reached, isFalse);
    });

    test('featured goal is the unfinished one that finishes first', () {
      final a = GoalView(
        goal: goal('a', 'A', 100, 0, 10),
        savedCents: 0,
        projectedFinish: DateTime(2028),
      );
      final b = GoalView(
        goal: goal('b', 'B', 100, 0, 10),
        savedCents: 0,
        projectedFinish: DateTime(2027),
      );
      final c = GoalView(
        goal: goal('c', 'C', 100, 100, 10),
        savedCents: 100,
        projectedFinish: DateTime(2026, 10),
      );
      expect(featuredGoal([a, b, c])!.goal.id, 'b');
      expect(featuredGoal([c])!.goal.id, 'c');
      expect(featuredGoal(const []), isNull);
      expect(totalSaved([a, b, c]), 100);
    });

    test(
      'recent contributions: newest first, deleted and orphaned ones left out',
      () {
        final r = recentContributions(
          goals: [goal('g', 'Trip', 1, 0, 0)],
          contributions: [
            add('g', 1, day: '2026-10-01'),
            add('g', 2, day: '2026-10-20', by: 'maya'),
            add('g', 3, day: '2026-10-25', deleted: DateTime(2026)),
            add('zzz', 4, day: '2026-10-26'),
          ],
        );
        expect(r.map((e) => e.cents), [2, 1]);
        expect(r.first.addedByUserId, 'maya');
      },
    );
  });

  group('bills', () {
    test('monthly bills keep their day and snap back after short months', () {
      expect(
        addPeriod(DateTime(2026, 1, 31), BillRepeat.monthly, 31),
        DateTime(2026, 2, 28),
      );
      expect(
        addPeriod(DateTime(2026, 2, 28), BillRepeat.monthly, 31),
        DateTime(2026, 3, 31),
      );
      expect(
        addPeriod(DateTime(2028, 1, 31), BillRepeat.monthly, 31),
        DateTime(2028, 2, 29),
      );
      expect(
        addPeriod(DateTime(2026, 12, 15), BillRepeat.monthly, 15),
        DateTime(2027, 1, 15),
      );
    });
    test('yearly, weekly and once', () {
      expect(
        addPeriod(DateTime(2028, 2, 29), BillRepeat.yearly, 29),
        DateTime(2029, 2, 28),
      );
      expect(
        addPeriod(DateTime(2026, 10, 28), BillRepeat.weekly, 28),
        DateTime(2026, 11, 4),
      );
      expect(addPeriod(DateTime(2026, 10, 28), BillRepeat.once, 28), isNull);
    });

    test('days until, labels and overdue', () {
      BillView v(String due) => BillView(
        bill: _bill('b', 100, due),
        dueOn: DateTime.parse(due),
        today: DateTime(2026, 10, 23),
      );
      expect(v('2026-10-28').daysUntil, 5);
      expect(v('2026-10-28').dueLabel, 'Due in 5 days');
      expect(v('2026-10-24').dueLabel, 'Due tomorrow');
      expect(v('2026-10-23').dueLabel, 'Due today');
      expect(v('2026-10-22').dueLabel, 'Overdue by 1 day');
      expect(v('2026-10-20').dueLabel, 'Overdue by 3 days');
      expect(v('2026-10-20').overdue, isTrue);
      expect(v('2026-10-28').isSoon(), isTrue);
      expect(v('2026-10-30').isSoon(), isFalse);
      expect(
        v('2026-10-20').isSoon(),
        isTrue,
        reason: 'overdue counts as soon',
      );
    });

    test('upcoming: sorted, deleted and settled one-off bills left out, totals add up', () {
      final bills = [
        _bill('Insurance', 11800, '2026-11-15'),
        _bill('Electricity', 9640, '2026-10-28'),
        _bill('Internet', 4990, '2026-10-30'),
        _bill('Old', 500, '2026-10-25', deleted: DateTime(2026)),
        _bill('OneOff', 700, '2026-10-26', repeat: 'once', paid: '2026-10-22'),
        _bill('Phone plan', 3500, '2026-11-02'),
        _bill('Streaming plan', 1998, '2026-11-05'),
      ];
      final up = upcomingBills(bills, _now);
      expect(up.map((b) => b.bill.id), [
        'Electricity',
        'Internet',
        'Phone plan',
        'Streaming plan',
        'Insurance',
      ]);
      expect(totalDue(up), 31928, reason: 'S\$319.28');
      expect(dueBy(up), DateTime(2026, 11, 15));
      expect(dayMonthLabel(dueBy(up)!), '15 Nov');
      expect(dueBy(const []), isNull);
    });

    test('mark paid moves the due date one period and records the day', () {
      final paid = markPaidResult(_bill('b', 100, '2026-10-28'), _now);
      expect(paid.lastPaidOn, DateTime(2026, 10, 23));
      expect(paid.nextDueOn, DateTime(2026, 11, 28));
      final once = markPaidResult(
        _bill('b', 100, '2026-10-28', repeat: 'once'),
        _now,
      );
      expect(
        once.nextDueOn,
        DateTime(2026, 10, 28),
        reason: 'stays; the bill is settled',
      );
      final jan = markPaidResult(
        _bill('b', 100, '2026-01-31', day: 31),
        DateTime(2026, 1, 30),
      );
      expect(jan.nextDueOn, DateTime(2026, 2, 28));
    });
  });

  group('reminders', () {
    BillView view(
      String id,
      String due, {
      String repeat = 'monthly',
      String? paid,
    }) => BillView(
      bill: _bill(id, 9640, due, repeat: repeat, paid: paid),
      dueOn: DateTime.parse(due),
      today: _now.dateOnlyForTest,
    );

    test('a future reminder is scheduled 3 days before at 09:00', () {
      final plans = planReminders(
        bills: [view('Electricity', '2026-10-28')],
        now: _now,
        leadDays: 3,
        handled: {},
        money: _money.format,
      );
      expect(plans, hasLength(1));
      expect(plans.single.when, DateTime(2026, 10, 25, 9));
      expect(plans.single.immediate, isFalse);
      expect(plans.single.body, 'Electricity (S\$96.40) is due in 3 days.');
    });

    test('inside the window it shows now, once', () {
      final bill = view('Electricity', '2026-10-24');
      final first = planReminders(
        bills: [bill],
        now: _now,
        leadDays: 3,
        handled: {},
        money: _money.format,
      );
      expect(first.single.immediate, isTrue);
      expect(first.single.body, 'Electricity (S\$96.40) is due tomorrow.');
      final again = planReminders(
        bills: [bill],
        now: _now,
        leadDays: 3,
        handled: {first.single.key},
        money: _money.format,
      );
      expect(again, isEmpty, reason: 'not repeated every time the app opens');
    });

    test('overdue bills are reminded once; settled ones never', () {
      final over = planReminders(
        bills: [view('Late', '2026-10-20')],
        now: _now,
        leadDays: 3,
        handled: {},
        money: _money.format,
      );
      expect(over.single.body, contains('3 days overdue'));
      expect(
        planReminders(
          bills: [
            view('Done', '2026-10-24', repeat: 'once', paid: '2026-10-22'),
          ],
          now: _now,
          leadDays: 3,
          handled: {},
          money: _money.format,
        ),
        isEmpty,
      );
    });

    test('a new due date or lead time is a new reminder; ids are stable', () {
      final a = view('Electricity', '2026-10-24');
      final b = view('Electricity', '2026-11-24');
      expect(reminderKey(a, 3), isNot(reminderKey(b, 3)));
      expect(reminderKey(a, 3), isNot(reminderKey(a, 5)));
      expect(stableId(reminderKey(a, 3)), stableId(reminderKey(a, 3)));
      expect(stableId('x'), inInclusiveRange(0, 0x7fffffff));
    });
  });

  group('insights', () {
    late AppDatabase db;
    late List<ExpenseRow> expenses;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory(), clock: () => _now);
      await seedPhase5(db);
      expenses = await db.select(db.expenses).get();
    });
    tearDown(() => db.close());

    InsightsData build(
      InsightsPeriod period, {
      DateTime? month,
      DateTime? now,
    }) => buildInsights(
      period: period,
      month: month ?? DateTime(2026, 10),
      now: now ?? _now,
      expenses: expenses,
      categories: _categories,
      overallBudgetCents: 250000,
      budgetLines: [
        const BudgetLine(
          categoryId: 't',
          name: 'Transport',
          colorKey: 'transport',
          budgetCents: 30000,
          spentCents: 28400,
        ),
      ],
      memberName: (by) => by ?? 'You',
      money: _money.formatWhole,
    );

    test('month: the mockup numbers', () {
      final d = build(InsightsPeriod.month);
      expect(d.totalCents, 184200);
      expect(d.stats.map((s) => s.label), [
        'Spent',
        'Daily average',
        'Highest day',
        'Projected month-end',
      ]);
      expect(d.stats[1].cents, 8009, reason: '1,842 / 23 days = S\$80');
      expect(d.stats[2].cents, 61200);
      expect(d.stats[3].cents, 248279, reason: 'S\$2,483');
      expect(d.paceCents, 8065, reason: '2,500 / 31 = S\$81');
      expect(d.trend.map((b) => b.label), [
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
      ]);
      expect(d.trend.map((b) => b.cents ~/ 100), [
        2210,
        1980,
        2340,
        2050,
        2190,
        1842,
      ]);
      expect(d.trend.last.highlight, isTrue);
      expect(d.daily.length, 23);
      expect(d.dailyTitle, 'Daily spending, 1 to 23 Oct');
      expect(d.categories.map((c) => c.name), [
        'Food',
        'Bills',
        'Transport',
        'Other',
        'Fun',
      ]);
      expect(d.members.map((m) => m.name), ['You', 'Maya', 'Sam']);
      expect(d.members.map((m) => m.cents), [113200, 49400, 21600]);
    });

    test(
      'month: notes say where the month is heading and which budgets are close',
      () {
        final d = build(InsightsPeriod.month);
        expect(d.notes.first.kind, NoteKind.good);
        expect(
          d.notes.first.text,
          'At this pace you finish October at about S\$2,483, under your S\$2,500 budget.',
        );
        expect(d.notes.last.kind, NoteKind.warning);
        expect(
          d.notes.last.text,
          'Transport is at 95% of its budget with 8 days left.',
        );
      },
    );

    test('month: over budget at this pace is a warning', () {
      final d = buildInsights(
        period: InsightsPeriod.month,
        month: DateTime(2026, 10),
        now: _now,
        expenses: expenses,
        categories: _categories,
        overallBudgetCents: 100000,
        budgetLines: const [],
        memberName: (b) => b ?? 'You',
        money: _money.formatWhole,
      );
      expect(d.notes.first.kind, NoteKind.warning);
      expect(d.notes.first.text, contains('over your S\$1,000 budget'));
    });

    test('month: an over-budget category and a past month', () {
      final over = buildInsights(
        period: InsightsPeriod.month,
        month: DateTime(2026, 10),
        now: _now,
        expenses: expenses,
        categories: _categories,
        overallBudgetCents: 250000,
        budgetLines: const [
          BudgetLine(
            categoryId: 'f',
            name: 'Food',
            colorKey: 'food',
            budgetCents: 50000,
            spentCents: 61200,
          ),
        ],
        memberName: (b) => b ?? 'You',
        money: _money.formatWhole,
      );
      expect(
        over.notes.any((n) => n.text == 'Food is over its budget by S\$112.'),
        isTrue,
      );
      final past = build(InsightsPeriod.month, month: DateTime(2026, 9));
      expect(
        past.stats[3].cents,
        past.totalCents,
        reason: 'a finished month is not projected',
      );
      expect(past.notes, isEmpty);
    });

    test('week: last 7 days with a comparison to the week before', () {
      final d = build(InsightsPeriod.week);
      expect(d.trendTitle, 'Last 7 days');
      expect(d.trend, hasLength(7));
      expect(d.trend.last.label, 'Today');
      expect(d.totalCents, 21600, reason: 'only Oct 20 falls in Oct 17 to 23');
      expect(d.stats[3].label, 'Vs previous week');
      expect(d.daily, isEmpty);
    });

    test('year: twelve months, monthly average and projection', () {
      final d = build(InsightsPeriod.year);
      expect(d.trend, hasLength(12));
      expect(d.totalCents, 221000 + 198000 + 234000 + 205000 + 219000 + 184200);
      expect(d.stats[2].cents, 234000, reason: 'highest month');
      expect(
        d.stats[1].cents,
        d.totalCents ~/ 10,
        reason: 'average over the 10 months so far',
      );
    });

    test('range covers what each period draws', () {
      final month = insightsRange(
        InsightsPeriod.month,
        DateTime(2026, 10),
        _now,
      );
      expect(month.from, DateTime(2026, 5));
      expect(month.to, DateTime(2026, 10, 31));
      final week = insightsRange(InsightsPeriod.week, DateTime(2026, 10), _now);
      expect(week.from, DateTime(2026, 10, 10));
      expect(week.to, DateTime(2026, 10, 23));
      final year = insightsRange(InsightsPeriod.year, DateTime(2026, 10), _now);
      expect(year.from, DateTime(2026));
      expect(year.to, DateTime(2026, 12, 31));
    });

    test('no spending: zeros, no division by zero', () {
      final d = buildInsights(
        period: InsightsPeriod.month,
        month: DateTime(2026, 11),
        now: _now,
        expenses: const [],
        categories: _categories,
        overallBudgetCents: 0,
        budgetLines: const [],
        memberName: (b) => b ?? 'You',
        money: _money.formatWhole,
      );
      expect(d.totalCents, 0);
      expect(d.paceCents, 0);
      expect(d.categories, isEmpty);
      expect(d.notes, isEmpty);
    });
  });
}

extension on DateTime {
  DateTime get dateOnlyForTest => DateTime(year, month, day);
}
