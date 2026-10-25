import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../expenses/data/day_format.dart';

/// The overall budget when no month has one yet (the mockups' S$2,500).
const defaultMonthlyBudgetCents = 250000;

/// At or above this share of a budget the card turns amber ("Almost at limit").
const nearLimitPercent = 90;

/// Fixed id for the budget of [month] and [categoryId] (null = overall), so two devices that
/// set the same budget offline end up with one row.
String budgetId(DateTime month, String? categoryId) =>
    'b:${formatDay(monthStart(month)).substring(0, 7)}:${categoryId ?? 'overall'}';

String budgetMonthText(DateTime month) => formatDay(monthStart(month));

/// The budget amounts in force for [month], by category id (`null` = overall). A month
/// without its own row uses the latest earlier month's row; a deleted row means "no budget".
Map<String?, int> effectiveBudgets(List<BudgetRow> rows, DateTime month) {
  final limit = budgetMonthText(month);
  final latest = <String?, BudgetRow>{};
  for (final r in rows) {
    if (r.month.compareTo(limit) > 0) continue;
    final current = latest[r.categoryId];
    if (current == null ||
        r.month.compareTo(current.month) > 0 ||
        (r.month == current.month && r.updatedAt.isAfter(current.updatedAt))) {
      latest[r.categoryId] = r;
    }
  }
  return {
    for (final e in latest.entries)
      if (e.value.deletedAt == null) e.key: e.value.amountCents,
  };
}

enum BudgetState {
  ok,

  /// 90% or more used.
  nearLimit,

  /// Spent more than the budget.
  over,
}

class BudgetLine {
  const BudgetLine({
    required this.categoryId,
    required this.name,
    required this.colorKey,
    required this.budgetCents,
    required this.spentCents,
  });

  final String categoryId;
  final String name;
  final String colorKey;
  final int budgetCents;
  final int spentCents;

  int get leftCents => budgetCents - spentCents;
  int get overCents => spentCents > budgetCents ? spentCents - budgetCents : 0;

  /// Whole percent used (rounded); 0 when the budget is 0.
  int get percent => budgetCents <= 0
      ? 0
      : (spentCents * 100 + budgetCents ~/ 2) ~/ budgetCents;

  /// 0 to 1 for the bar.
  double get fraction =>
      budgetCents <= 0 ? 0 : (spentCents / budgetCents).clamp(0.0, 1.0);

  BudgetState get state {
    if (spentCents > budgetCents) return BudgetState.over;
    if (budgetCents > 0 && spentCents * 100 >= budgetCents * nearLimitPercent) {
      return BudgetState.nearLimit;
    }
    return BudgetState.ok;
  }
}

class BudgetsSummary {
  const BudgetsSummary({
    required this.month,
    required this.overallCents,
    required this.hasOverallBudget,
    required this.spentCents,
    required this.lines,
    required this.daysLeft,
    required this.perDayCents,
  });

  final DateTime month;

  /// The overall monthly budget; [defaultMonthlyBudgetCents] until one is set.
  final int overallCents;
  final bool hasOverallBudget;

  /// Everything spent in the month, with or without a category budget.
  final int spentCents;

  /// Categories that have a budget, largest budget first.
  final List<BudgetLine> lines;
  final int daysLeft;

  /// What is left spread over the days left.
  final int perDayCents;

  int get leftCents => overallCents - spentCents;
  int get percent => overallCents <= 0
      ? 0
      : (spentCents * 100 + overallCents ~/ 2) ~/ overallCents;
  double get fraction =>
      overallCents <= 0 ? 0 : (spentCents / overallCents).clamp(0.0, 1.0);
  bool get isOver => spentCents > overallCents;
}

/// Budgets for [month] from the stored rows and the month's [expenses] (live ones only).
BudgetsSummary buildBudgetsSummary({
  required DateTime month,
  required DateTime now,
  required List<BudgetRow> budgetRows,
  required List<ExpenseRow> expenses,
  required List<CategoryRow> categories,
}) {
  final budgets = effectiveBudgets(budgetRows, month);
  final prefix = formatDay(monthStart(month)).substring(0, 7);
  final spentBy = <String, int>{};
  var spent = 0;
  for (final e in expenses) {
    if (e.deletedAt != null || !e.spentOn.startsWith(prefix)) continue;
    spent += e.amountCents;
    spentBy[e.categoryId] = (spentBy[e.categoryId] ?? 0) + e.amountCents;
  }
  final byId = {for (final c in categories) c.id: c};
  final lines =
      <BudgetLine>[
        for (final e in budgets.entries)
          if (e.key != null && byId[e.key] != null)
            BudgetLine(
              categoryId: e.key!,
              name: byId[e.key]!.name,
              colorKey: byId[e.key]!.color,
              budgetCents: e.value,
              spentCents: spentBy[e.key] ?? 0,
            ),
      ]..sort((a, b) {
        final byBudget = b.budgetCents.compareTo(a.budgetCents);
        return byBudget != 0 ? byBudget : a.name.compareTo(b.name);
      });

  final overall = budgets[null];
  final overallCents = overall ?? defaultMonthlyBudgetCents;
  final today = now.dateOnly;
  final days = daysInMonth(month);
  final isCurrent = today.year == month.year && today.month == month.month;
  final isPast = DateTime(
    month.year,
    month.month,
  ).isBefore(DateTime(today.year, today.month));
  final daysLeft = isCurrent ? days - today.day : (isPast ? 0 : days);
  final left = overallCents - spent;
  final perDay = (left <= 0 || isPast)
      ? 0
      : (left + (daysLeft < 1 ? 1 : daysLeft) ~/ 2) ~/
            (daysLeft < 1 ? 1 : daysLeft);
  return BudgetsSummary(
    month: monthStart(month),
    overallCents: overallCents,
    hasOverallBudget: overall != null,
    spentCents: spent,
    lines: lines,
    daysLeft: daysLeft,
    perDayCents: perDay,
  );
}
