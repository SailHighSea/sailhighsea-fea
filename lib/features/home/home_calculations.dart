import 'package:intl/intl.dart';

import '../../core/db/app_database.dart';
import '../../core/time.dart';
import '../expenses/data/day_format.dart';
import 'home_data.dart';

/// First day the Home query must cover for [month]: the 7-day chart can reach back into
/// the previous month.
DateTime homeRangeStart(DateTime month, DateTime now) =>
    _referenceDay(month, now).subtract(const Duration(days: 6));

/// Last day the Home query must cover.
DateTime homeRangeEnd(DateTime month) =>
    DateTime(month.year, month.month, daysInMonth(month));

/// The day "Today", "This week" and the 7-day chart are measured to: today for the
/// current month, the last day of a past month, the first day of a future month.
DateTime _referenceDay(DateTime month, DateTime now) {
  final today = now.dateOnly;
  final monthIndex = month.year * 12 + month.month;
  final todayIndex = today.year * 12 + today.month;
  if (monthIndex == todayIndex) return today;
  if (monthIndex < todayIndex) {
    return DateTime(month.year, month.month, daysInMonth(month));
  }
  return DateTime(month.year, month.month);
}

/// Builds everything Home shows from the expenses in [expenses] (which must cover
/// [homeRangeStart] to [homeRangeEnd]). All amounts are integer cents.
HomeSummary buildHomeSummary({
  required DateTime month,
  required DateTime now,
  required int budgetCents,
  required List<ExpenseRow> expenses,
  required List<CategoryRow> categories,
  String currentUser = 'You',
  int topCategoryCount = 4,
  int recentCount = 4,
}) {
  final today = now.dateOnly;
  final monthIndex = month.year * 12 + month.month;
  final todayIndex = today.year * 12 + today.month;
  final isCurrent = monthIndex == todayIndex;
  final isPast = monthIndex < todayIndex;
  final days = daysInMonth(month);
  final ref = _referenceDay(month, now);
  final monthPrefix = formatDay(DateTime(month.year, month.month))
      .substring(0, 7);

  final categoryById = {for (final c in categories) c.id: c};
  final byDay = <String, int>{};
  final monthExpenses = <ExpenseRow>[];
  for (final e in expenses) {
    if (e.deletedAt != null) continue;
    byDay[e.spentOn] = (byDay[e.spentOn] ?? 0) + e.amountCents;
    if (e.spentOn.startsWith(monthPrefix)) monthExpenses.add(e);
  }

  final spent = monthExpenses.fold<int>(0, (sum, e) => sum + e.amountCents);

  // Last 7 days ending on the reference day.
  final weekdayFormat = DateFormat('EEE', 'en_US');
  final last7 = <DayBar>[];
  for (var i = 6; i >= 0; i--) {
    final day = ref.subtract(Duration(days: i));
    final isToday = isCurrent && i == 0;
    last7.add(
      DayBar(
        label: isToday ? 'Today' : weekdayFormat.format(day),
        cents: byDay[formatDay(day)] ?? 0,
        highlight: isToday,
      ),
    );
  }
  final week = last7.fold<int>(0, (sum, b) => sum + b.cents);

  // Daily bars for the desktop chart: day 1 up to the reference day (nothing in the future).
  final lastBarDay = isCurrent ? today.day : (isPast ? days : 0);
  final monthDaily = [
    for (var d = 1; d <= lastBarDay; d++)
      DayBar(
        label: '$d',
        cents: byDay[formatDay(DateTime(month.year, month.month, d))] ?? 0,
      ),
  ];

  // Pace is what you may spend per calendar day; safe per day spreads what is left over the days left.
  final pace = budgetCents <= 0 ? 0 : _roundedDivide(budgetCents, days);
  final remaining = budgetCents - spent;
  final daysLeft = isCurrent ? days - today.day : (isPast ? 0 : days);
  final safePerDay = (remaining <= 0 || isPast)
      ? 0
      : _roundedDivide(remaining, daysLeft < 1 ? 1 : daysLeft);

  return HomeSummary(
    month: DateTime(month.year, month.month),
    spentCents: spent,
    budgetCents: budgetCents,
    todayCents: byDay[formatDay(ref)] ?? 0,
    weekCents: week,
    safePerDayCents: safePerDay,
    paceCents: pace,
    categories: _topCategories(monthExpenses, categoryById, topCategoryCount),
    last7: last7,
    monthDaily: monthDaily,
    recent: _recent(monthExpenses, categoryById, currentUser, recentCount),
  );
}

/// Integer division rounded half up (positive values only).
int _roundedDivide(int numerator, int denominator) =>
    (numerator + denominator ~/ 2) ~/ denominator;

/// Largest categories by spend. With more than [limit] categories the smallest ones are
/// folded into "Other" so the share bar always adds up to the month total.
List<CategorySpend> _topCategories(
  List<ExpenseRow> monthExpenses,
  Map<String, CategoryRow> categoryById,
  int limit,
) {
  final totals = <String, int>{};
  for (final e in monthExpenses) {
    final id = categoryById.containsKey(e.categoryId)
        ? e.categoryId
        : otherCategoryId;
    totals[id] = (totals[id] ?? 0) + e.amountCents;
  }

  CategorySpend spend(String id, int cents) {
    final c = categoryById[id];
    return CategorySpend(
      name: c?.name ?? 'Other',
      colorKey: c?.color ?? 'other',
      cents: cents,
    );
  }

  // Named categories largest first; "Other" always goes last, like the mockups.
  final named = totals.entries.where((e) => e.key != otherCategoryId).toList()
    ..sort((a, b) {
      final byAmount = b.value.compareTo(a.value);
      return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
    });
  final otherTotal = totals[otherCategoryId] ?? 0;
  final fits = named.length + (otherTotal > 0 ? 1 : 0) <= limit;
  if (fits) {
    return [
      for (final e in named) spend(e.key, e.value),
      if (otherTotal > 0) spend(otherCategoryId, otherTotal),
    ];
  }
  // Too many: fold the smallest into Other so the bar still adds up to the month total.
  final shown = named.take(limit - 1);
  final folded =
      named.skip(limit - 1).fold<int>(0, (sum, e) => sum + e.value) +
      otherTotal;
  return [
    for (final e in shown) spend(e.key, e.value),
    spend(otherCategoryId, folded),
  ];
}

List<RecentExpense> _recent(
  List<ExpenseRow> monthExpenses,
  Map<String, CategoryRow> categoryById,
  String currentUser,
  int count,
) {
  final sorted = [...monthExpenses]
    ..sort((a, b) {
      final byDay = b.spentOn.compareTo(a.spentOn);
      return byDay != 0 ? byDay : b.updatedAt.compareTo(a.updatedAt);
    });
  return [
    for (final e in sorted.take(count))
      RecentExpense(
        id: e.id,
        note: e.note.isEmpty
            ? (categoryById[e.categoryId]?.name ?? 'Expense')
            : e.note,
        categoryName: categoryById[e.categoryId]?.name ?? 'Other',
        spentOn: parseDay(e.spentOn),
        addedBy: (e.createdBy == null || e.createdBy == currentUser)
            ? 'You'
            : e.createdBy!,
        cents: e.amountCents,
      ),
  ];
}
