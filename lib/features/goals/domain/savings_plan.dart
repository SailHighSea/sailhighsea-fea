import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../bills/domain/bill_calculations.dart';
import '../../expenses/data/day_format.dart';
import '../data/savings_repository.dart' show monthKey;
import 'goal_calculations.dart';

/// Whether the monthly goal amounts fit in what is left of the income.
enum PlanStatus { noIncome, fits, short }

/// One past month's savings rate: whole percent of income kept, `null` without an income.
class MonthRate {
  const MonthRate(this.month, this.percent);
  final DateTime month;
  final int? percent;
}

/// The money picture of one month: what comes in, what has gone out, what is promised to goals
/// and what is left. All integer cents.
class SavingsPlan {
  const SavingsPlan({
    required this.month,
    required this.incomeCents,
    required this.spentCents,
    required this.billsDueCents,
    required this.goalsMonthlyCents,
    required this.totalSavingsCents,
    required this.totalAsOn,
    required this.inGoalsCents,
    required this.history,
  });

  final DateTime month;

  /// `null` until an income is set for this month or an earlier one.
  final int? incomeCents;
  final int spentCents;

  /// Unpaid bills still to come this month.
  final int billsDueCents;

  /// What the unfinished goals ask to be set aside each month.
  final int goalsMonthlyCents;

  /// `null` until the person enters what they hold.
  final int? totalSavingsCents;
  final DateTime? totalAsOn;
  final int inGoalsCents;
  final List<MonthRate> history;

  bool get hasIncome => incomeCents != null && incomeCents! > 0;

  /// Income minus what has been spent so far.
  int get keptCents => (incomeCents ?? 0) - spentCents;

  /// Income minus spending, bills still due and the goal amounts. Negative when over.
  int get leftCents => keptCents - billsDueCents - goalsMonthlyCents;

  /// What is left once spending and bills are covered, before goals.
  int get availableForGoalsCents => keptCents - billsDueCents;

  PlanStatus get status => !hasIncome
      ? PlanStatus.noIncome
      : goalsMonthlyCents <= availableForGoalsCents
      ? PlanStatus.fits
      : PlanStatus.short;

  /// Whole percent of income kept so far; `null` without an income.
  int? get ratePercent => hasIncome ? _rate(keptCents, incomeCents!) : null;

  /// Percent of income the goals ask for; `null` without an income.
  int? get goalsPercent =>
      hasIncome ? _rate(goalsMonthlyCents, incomeCents!) : null;

  /// Savings that are not assigned to any goal.
  int get notInGoalsCents {
    final total = totalSavingsCents ?? 0;
    return total > inGoalsCents ? total - inGoalsCents : 0;
  }
}

/// Rounded percent, half away from zero, using integers only.
int _rate(int part, int whole) {
  final n = part * 100;
  return part >= 0 ? (n + whole ~/ 2) ~/ whole : -((-n + whole ~/ 2) ~/ whole);
}

/// The income in force for [month]: the latest entry that starts at or before it.
int? incomeFor(DateTime month, List<IncomeRow> income) {
  final key = monthKey(month);
  IncomeRow? best;
  for (final i in income) {
    if (i.month.compareTo(key) <= 0 &&
        (best == null || i.month.compareTo(best.month) > 0)) {
      best = i;
    }
  }
  return best?.amountCents;
}

int _spentIn(DateTime month, List<ExpenseRow> expenses) {
  final prefix = monthKey(month);
  var sum = 0;
  for (final e in expenses) {
    if (e.deletedAt == null && e.spentOn.startsWith(prefix)) {
      sum += e.amountCents;
    }
  }
  return sum;
}

/// First day of the earliest month [buildSavingsPlan] wants expenses from (five months back).
DateTime savingsRangeStart(DateTime month) =>
    DateTime(month.year, month.month - 5);

SavingsPlan buildSavingsPlan({
  required DateTime month,
  required DateTime now,
  required List<IncomeRow> income,
  required List<SavingsBalanceRow> balances,
  required List<GoalView> goals,
  required List<BillRow> bills,

  /// Expenses from [savingsRangeStart] to the end of [month].
  required List<ExpenseRow> expenses,
}) {
  final first = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  final today = now.dateOnly;

  // Unpaid bills due inside the month (overdue ones included). A finished month has none.
  var billsDue = 0;
  final monthIsOver = !end.isAfter(DateTime(today.year, today.month));
  if (!monthIsOver) {
    for (final v in upcomingBills(bills, now)) {
      if (!v.dueOn.isBefore(first) && v.dueOn.isBefore(end)) {
        billsDue += v.amountCents;
      }
    }
  }

  var goalsMonthly = 0;
  var inGoals = 0;
  for (final g in goals) {
    inGoals += g.savedCents;
    if (!g.reached) goalsMonthly += g.goal.monthlyCents;
  }

  SavingsBalanceRow? latest;
  for (final b in balances) {
    if (latest == null || b.asOn.compareTo(latest.asOn) > 0) latest = b;
  }

  final history = <MonthRate>[
    for (var i = 5; i >= 0; i--)
      () {
        final m = DateTime(month.year, month.month - i);
        final inc = incomeFor(m, income);
        if (inc == null || inc <= 0) return MonthRate(m, null);
        return MonthRate(m, _rate(inc - _spentIn(m, expenses), inc));
      }(),
  ];

  return SavingsPlan(
    month: first,
    incomeCents: incomeFor(first, income),
    spentCents: _spentIn(first, expenses),
    billsDueCents: billsDue,
    goalsMonthlyCents: goalsMonthly,
    totalSavingsCents: latest?.amountCents,
    totalAsOn: latest == null ? null : parseDay(latest.asOn),
    inGoalsCents: inGoals,
    history: history,
  );
}
