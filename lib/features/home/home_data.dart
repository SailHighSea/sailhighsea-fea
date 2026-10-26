import 'package:flutter/foundation.dart';

/// Everything the Home screen shows for one month. All money is integer cents.
@immutable
class HomeSummary {
  const HomeSummary({
    required this.month,
    required this.spentCents,
    required this.budgetCents,
    required this.todayCents,
    required this.weekCents,
    required this.safePerDayCents,
    required this.paceCents,
    required this.categories,
    required this.last7,
    required this.monthDaily,
    required this.recent,
    this.comparison = const [],
    this.nextBill,
    this.goal,
  });

  final DateTime month;
  final int spentCents;
  final int budgetCents;
  final int todayCents;
  final int weekCents;

  /// Remaining budget divided by days left.
  final int safePerDayCents;

  /// Budget divided by days in the month: the dashed line on the charts.
  final int paceCents;

  final List<CategorySpend> categories;
  final List<DayBar> last7;
  final List<DayBar> monthDaily;
  final List<RecentExpense> recent;

  /// Every category with spending this month or at the same point last month.
  final List<CategoryCompare> comparison;
  final UpcomingBill? nextBill;
  final GoalProgress? goal;

  int get remainingCents => budgetCents - spentCents;

  /// Whole percent of the budget used (rounded); 0 when there is no budget.
  int get usedPercent =>
      budgetCents <= 0 ? 0 : (spentCents * 100 / budgetCents).round();

  /// 0 to 1 for the ring.
  double get usedFraction =>
      budgetCents <= 0 ? 0 : (spentCents / budgetCents).clamp(0.0, 1.0);
}

@immutable
class CategorySpend {
  const CategorySpend({
    required this.name,
    required this.colorKey,
    required this.cents,
  });
  final String name;
  final String colorKey;
  final int cents;
}

/// A category's spending this month against the same days of the previous month.
@immutable
class CategoryCompare {
  const CategoryCompare({
    required this.name,
    required this.colorKey,
    required this.cents,
    required this.previousCents,
    this.icon,
  });

  final String name;
  final String colorKey;
  final String? icon;
  final int cents;

  /// Last month, up to the same day of the month.
  final int previousCents;

  /// Whole percent change (rounded, integer maths); null when there was nothing last month.
  int? get changePercent {
    if (previousCents <= 0) return null;
    final diff = (cents - previousCents) * 100;
    final half = previousCents ~/ 2;
    return diff >= 0
        ? (diff + half) ~/ previousCents
        : -((-diff + half) ~/ previousCents);
  }
}

@immutable
class DayBar {
  const DayBar({
    required this.label,
    required this.cents,
    this.highlight = false,
  });

  /// Weekday name or day of month.
  final String label;
  final int cents;

  /// The "Today" bar on the 7-day chart.
  final bool highlight;
}

@immutable
class RecentExpense {
  const RecentExpense({
    required this.id,
    required this.note,
    required this.categoryName,
    required this.spentOn,
    required this.addedBy,
    required this.cents,
    this.createdBy,
  });

  /// Who added it (`created_by`), so the screen can tell whose expense it is.
  final String? createdBy;
  final String id;
  final String note;
  final String categoryName;
  final DateTime spentOn;
  final String addedBy;
  final int cents;
}

@immutable
class UpcomingBill {
  const UpcomingBill({
    required this.name,
    required this.amountCents,
    required this.daysUntil,
    required this.billCount,
    required this.totalDueCents,
    required this.dueByLabel,
  });

  final String name;
  final int amountCents;
  final int daysUntil;
  final int billCount;
  final int totalDueCents;
  final String dueByLabel;
}

@immutable
class GoalProgress {
  const GoalProgress({
    required this.name,
    required this.savedCents,
    required this.targetCents,
    required this.monthlyCents,
    required this.doneByLabel,
  });

  final String name;
  final int savedCents;
  final int targetCents;
  final int monthlyCents;
  final String doneByLabel;

  double get fraction =>
      targetCents <= 0 ? 0 : (savedCents / targetCents).clamp(0.0, 1.0);
}
