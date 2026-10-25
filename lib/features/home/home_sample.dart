import 'home_data.dart';

/// Hard-coded numbers from the Main, Tablet and Desktop mockups (Phase 1 only; Phase 2
/// replaces these with data from the local database).
HomeSummary sampleHomeSummary(DateTime month) {
  const days = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Today'];
  const weekDollars = [130, 50, 60, 85, 70, 100, 72];
  const monthDollars = [
    96, 61, 41, 122, 86, 71, 152, 56, 46, 91, 66, 111, //
    81, 35, 101, 76, 132, 51, 61, 86, 71, 101, 73,
  ];
  return HomeSummary(
    month: month,
    spentCents: 184200,
    budgetCents: 250000,
    todayCents: 7200,
    weekCents: 56700,
    safePerDayCents: 8200,
    paceCents: 8100,
    categories: const [
      CategorySpend(name: 'Food', colorKey: 'food', cents: 61200),
      CategorySpend(name: 'Bills', colorKey: 'bills', cents: 52000),
      CategorySpend(name: 'Transport', colorKey: 'transport', cents: 28400),
      CategorySpend(name: 'Other', colorKey: 'other', cents: 42600),
    ],
    last7: [
      for (var i = 0; i < 7; i++)
        DayBar(label: days[i], cents: weekDollars[i] * 100, highlight: i == 6),
    ],
    monthDaily: [
      for (var i = 0; i < monthDollars.length; i++)
        DayBar(label: '${i + 1}', cents: monthDollars[i] * 100),
    ],
    recent: [
      RecentExpense(
        id: 'sample-1',
        note: 'Groceries',
        categoryName: 'Food',
        spentOn: DateTime(2026, 10, 23),
        addedBy: 'Maya',
        cents: 4820,
      ),
      RecentExpense(
        id: 'sample-2',
        note: 'MRT top-up',
        categoryName: 'Transport',
        spentOn: DateTime(2026, 10, 22),
        addedBy: 'You',
        cents: 2000,
      ),
      RecentExpense(
        id: 'sample-3',
        note: 'Streaming plan',
        categoryName: 'Fun',
        spentOn: DateTime(2026, 10, 21),
        addedBy: 'You',
        cents: 1998,
      ),
      RecentExpense(
        id: 'sample-4',
        note: 'Hawker lunch',
        categoryName: 'Food',
        spentOn: DateTime(2026, 10, 20),
        addedBy: 'Sam',
        cents: 650,
      ),
    ],
    nextBill: const UpcomingBill(
      name: 'Electricity',
      amountCents: 9640,
      daysUntil: 5,
      billCount: 5,
      totalDueCents: 31928,
      dueByLabel: '15 Nov',
    ),
    goal: const GoalProgress(
      name: 'Holiday trip',
      savedCents: 120000,
      targetCents: 300000,
      monthlyCents: 15000,
      doneByLabel: 'Oct 2027',
    ),
  );
}
