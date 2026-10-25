import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../budgets/domain/budget_calculations.dart';
import '../../expenses/data/day_format.dart';

enum InsightsPeriod {
  week('Week'),
  month('Month'),
  year('Year');

  const InsightsPeriod(this.label);
  final String label;
}

/// First and last day the expense query must cover so every chart for [period] has its data:
/// six months back for the month trend, the whole year for the year view, 14 days for
/// "versus the previous week".
({DateTime from, DateTime to}) insightsRange(
  InsightsPeriod period,
  DateTime month,
  DateTime now,
) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month, daysInMonth(month));
  switch (period) {
    case InsightsPeriod.week:
      final end = _referenceDay(month, now);
      return (from: end.subtract(const Duration(days: 13)), to: end);
    case InsightsPeriod.month:
      return (from: DateTime(first.year, first.month - 5), to: last);
    case InsightsPeriod.year:
      return (from: DateTime(month.year), to: DateTime(month.year, 12, 31));
  }
}

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

class StatTile {
  const StatTile(this.label, this.cents, {this.text});
  final String label;
  final int cents;

  /// Shown instead of money (for "+12%").
  final String? text;
}

class TrendBar {
  const TrendBar({
    required this.label,
    required this.cents,
    this.highlight = false,
  });
  final String label;
  final int cents;

  /// The month or day the page is about.
  final bool highlight;
}

class DayPoint {
  const DayPoint({required this.day, required this.cents});
  final int day;
  final int cents;
}

class BreakdownLine {
  const BreakdownLine({
    required this.name,
    required this.colorKey,
    required this.cents,
  });
  final String name;
  final String colorKey;
  final int cents;
}

class MemberShare {
  const MemberShare({required this.name, required this.cents});
  final String name;
  final int cents;
}

enum NoteKind { good, warning }

class InsightNote {
  const InsightNote(this.kind, this.text);
  final NoteKind kind;
  final String text;
}

/// Everything Insights shows for one period. Money is integer cents.
class InsightsData {
  const InsightsData({
    required this.period,
    required this.month,
    required this.totalCents,
    required this.stats,
    required this.trendTitle,
    required this.trend,
    required this.daily,
    required this.dailyTitle,
    required this.paceCents,
    required this.categories,
    required this.members,
    required this.notes,
  });

  final InsightsPeriod period;
  final DateTime month;
  final int totalCents;

  /// Four tiles (the phone shows the first three).
  final List<StatTile> stats;

  /// "Last 6 months", "Last 12 months" or "Last 7 days".
  final String trendTitle;
  final List<TrendBar> trend;

  /// Per day bars (month view only), day 1 up to the last day with data.
  final List<DayPoint> daily;
  final String dailyTitle;

  /// Daily budget pace: the dashed line. 0 when there is no pace to show.
  final int paceCents;
  final List<BreakdownLine> categories;
  final List<MemberShare> members;
  final List<InsightNote> notes;
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

int _div(int n, int d) => d <= 0 ? 0 : (n + d ~/ 2) ~/ d;

/// [expenses] must cover [insightsRange]. [overallBudgetCents] and [lines] come from the
/// budgets for the month. [memberName] turns `created_by` into the name shown.
InsightsData buildInsights({
  required InsightsPeriod period,
  required DateTime month,
  required DateTime now,
  required List<ExpenseRow> expenses,
  required List<CategoryRow> categories,
  required int overallBudgetCents,
  required List<BudgetLine> budgetLines,
  required String Function(String?) memberName,
  required String Function(int cents) money,
}) {
  final live = expenses.where((e) => e.deletedAt == null).toList();
  final byDay = <String, int>{};
  for (final e in live) {
    byDay[e.spentOn] = (byDay[e.spentOn] ?? 0) + e.amountCents;
  }
  int dayTotal(DateTime d) => byDay[formatDay(d)] ?? 0;

  final today = now.dateOnly;
  final ref = _referenceDay(month, now);
  final days = daysInMonth(month);
  final first = DateTime(month.year, month.month);
  final isCurrent = today.year == month.year && today.month == month.month;
  final isPast = first.isBefore(DateTime(today.year, today.month));
  final elapsed = isCurrent ? today.day : (isPast ? days : 0);
  final pace = overallBudgetCents <= 0 ? 0 : _div(overallBudgetCents, days);

  // Rows that belong to the period.
  late final DateTime from;
  late final DateTime to;
  switch (period) {
    case InsightsPeriod.week:
      to = ref;
      from = ref.subtract(const Duration(days: 6));
    case InsightsPeriod.month:
      from = first;
      to = DateTime(month.year, month.month, days);
    case InsightsPeriod.year:
      from = DateTime(month.year);
      to = DateTime(month.year, 12, 31);
  }
  final fromText = formatDay(from);
  final toText = formatDay(to);
  final inPeriod = live
      .where(
        (e) =>
            e.spentOn.compareTo(fromText) >= 0 &&
            e.spentOn.compareTo(toText) <= 0,
      )
      .toList();
  final total = inPeriod.fold<int>(0, (s, e) => s + e.amountCents);

  // Highest single day (or month, for the year view).
  var highest = 0;
  final stats = <StatTile>[];
  final notes = <InsightNote>[];
  var trend = <TrendBar>[];
  var daily = <DayPoint>[];
  var trendTitle = '';
  var dailyTitle = '';
  var tilePace = 0;

  switch (period) {
    case InsightsPeriod.week:
      for (var i = 0; i < 7; i++) {
        final d = from.add(Duration(days: i));
        final c = dayTotal(d);
        if (c > highest) highest = c;
        trend.add(
          TrendBar(
            label: (isCurrent && d == today)
                ? 'Today'
                : _weekdays[d.weekday - 1],
            cents: c,
            highlight: isCurrent && d == today,
          ),
        );
      }
      trendTitle = 'Last 7 days';
      final previous = [
        for (var i = 7; i < 14; i++) dayTotal(ref.subtract(Duration(days: i))),
      ].fold<int>(0, (s, c) => s + c);
      final change = previous <= 0
          ? 'New'
          : '${total >= previous ? '+' : '-'}${_div((total - previous).abs() * 100, previous)}%';
      stats
        ..add(StatTile('Spent', total))
        ..add(StatTile('Daily average', _div(total, 7)))
        ..add(StatTile('Highest day', highest))
        ..add(StatTile('Vs previous week', 0, text: change));
      tilePace = pace;
    case InsightsPeriod.month:
      for (var d = 1; d <= elapsed; d++) {
        final c = dayTotal(DateTime(month.year, month.month, d));
        if (c > highest) highest = c;
        daily.add(DayPoint(day: d, cents: c));
      }
      dailyTitle = elapsed <= 1
          ? 'Daily spending, ${_shortMonths[month.month - 1]} 1'
          : 'Daily spending, 1 to $elapsed ${_shortMonths[month.month - 1]}';
      for (var i = 5; i >= 0; i--) {
        final m = DateTime(month.year, month.month - i);
        final prefix = formatDay(m).substring(0, 7);
        var c = 0;
        for (final e in live) {
          if (e.spentOn.startsWith(prefix)) c += e.amountCents;
        }
        trend.add(
          TrendBar(
            label: _shortMonths[m.month - 1],
            cents: c,
            highlight: i == 0,
          ),
        );
      }
      trendTitle = 'Last 6 months';
      final average = _div(total, elapsed < 1 ? 1 : elapsed);
      final projected = isCurrent ? average * days : total;
      stats
        ..add(StatTile('Spent', total))
        ..add(StatTile('Daily average', average))
        ..add(StatTile('Highest day', highest))
        ..add(StatTile('Projected month-end', projected));
      tilePace = pace;
      final name = _monthNames[month.month - 1];
      if (isCurrent && total > 0) {
        final diff = (projected - overallBudgetCents).abs();
        notes.add(
          projected <= overallBudgetCents
              ? InsightNote(
                  NoteKind.good,
                  'At this pace you finish $name at about ${money(projected)}, '
                  'under your ${money(overallBudgetCents)} budget.',
                )
              : InsightNote(
                  NoteKind.warning,
                  'At this pace you finish $name at about ${money(projected)}, '
                  '${money(diff)} over your ${money(overallBudgetCents)} budget.',
                ),
        );
      }
    case InsightsPeriod.year:
      var year = <int>[for (var m = 0; m < 12; m++) 0];
      for (final e in live) {
        if (!e.spentOn.startsWith('${month.year}-')) continue;
        final m = int.parse(e.spentOn.substring(5, 7)) - 1;
        year[m] += e.amountCents;
      }
      final lastMonth = month.year < today.year
          ? 12
          : (month.year == today.year ? today.month : 0);
      var best = 0;
      for (var m = 0; m < 12; m++) {
        if (year[m] > best) best = year[m];
        trend.add(
          TrendBar(
            label: _shortMonths[m],
            cents: year[m],
            highlight: month.year == today.year && m + 1 == today.month,
          ),
        );
      }
      highest = best;
      trendTitle = 'Last 12 months';
      final average = _div(total, lastMonth < 1 ? 1 : lastMonth);
      stats
        ..add(StatTile('Spent', total))
        ..add(StatTile('Monthly average', average))
        ..add(StatTile('Highest month', best))
        ..add(
          StatTile(
            'Projected year-end',
            month.year == today.year ? average * 12 : total,
          ),
        );
  }

  // Budget alerts for the month the page is about.
  if (period == InsightsPeriod.month) {
    final daysLeft = isCurrent ? days - today.day : (isPast ? 0 : days);
    for (final line in budgetLines) {
      final left = daysLeft == 1 ? '1 day' : '$daysLeft days';
      if (line.state == BudgetState.over) {
        notes.add(
          InsightNote(
            NoteKind.warning,
            '${line.name} is over its budget by ${money(line.overCents)}.',
          ),
        );
      } else if (line.state == BudgetState.nearLimit && !isPast) {
        notes.add(
          InsightNote(
            NoteKind.warning,
            '${line.name} is at ${line.percent}% of its budget with $left left.',
          ),
        );
      }
    }
  }

  // Categories and members over the period.
  final byCategory = <String, int>{};
  final byMember = <String, int>{};
  for (final e in inPeriod) {
    byCategory[e.categoryId] = (byCategory[e.categoryId] ?? 0) + e.amountCents;
    final who = memberName(e.createdBy);
    byMember[who] = (byMember[who] ?? 0) + e.amountCents;
  }
  final catById = {for (final c in categories) c.id: c};
  final categoryLines =
      [
        for (final e in byCategory.entries)
          BreakdownLine(
            name: catById[e.key]?.name ?? 'Other',
            colorKey: catById[e.key]?.color ?? 'other',
            cents: e.value,
          ),
      ]..sort((a, b) {
        final byAmount = b.cents.compareTo(a.cents);
        return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
      });
  final memberShares =
      [
        for (final e in byMember.entries)
          MemberShare(name: e.key, cents: e.value),
      ]..sort((a, b) {
        // "You" first, then biggest spender.
        if (a.name == 'You') return -1;
        if (b.name == 'You') return 1;
        final byAmount = b.cents.compareTo(a.cents);
        return byAmount != 0 ? byAmount : a.name.compareTo(b.name);
      });

  return InsightsData(
    period: period,
    month: first,
    totalCents: total,
    stats: stats,
    trendTitle: trendTitle,
    trend: trend,
    daily: daily,
    dailyTitle: dailyTitle,
    paceCents: tilePace,
    categories: categoryLines,
    members: memberShares,
    notes: notes,
  );
}
