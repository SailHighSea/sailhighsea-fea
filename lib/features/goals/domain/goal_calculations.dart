import '../../../core/db/app_database.dart';
import '../../expenses/data/day_format.dart';

class GoalView {
  const GoalView({
    required this.goal,
    required this.savedCents,
    required this.projectedFinish,
  });

  final GoalRow goal;

  /// Opening balance plus every live contribution.
  final int savedCents;

  /// When the goal is reached at the monthly amount: the first of that month. `null` when
  /// there is no monthly amount (the due date, if any, is then shown instead).
  final DateTime? projectedFinish;

  int get targetCents => goal.targetCents;
  int get remainingCents =>
      goal.targetCents > savedCents ? goal.targetCents - savedCents : 0;
  bool get reached => savedCents >= goal.targetCents;

  /// Whole percent (rounded down so 99.6% never reads as done).
  int get percent => goal.targetCents <= 0
      ? 0
      : (savedCents * 100 ~/ goal.targetCents).clamp(0, 100);
  double get fraction => goal.targetCents <= 0
      ? 0
      : (savedCents / goal.targetCents).clamp(0.0, 1.0);

  DateTime? get dueOn => goal.dueOn == null ? null : parseDay(goal.dueOn!);
}

/// The month a goal is reached when [monthlyCents] is added every month from [now].
/// `null` when nothing is added monthly. A goal already reached returns the current month.
DateTime? projectFinish({
  required int remainingCents,
  required int monthlyCents,
  required DateTime now,
}) {
  if (remainingCents <= 0) return DateTime(now.year, now.month);
  if (monthlyCents <= 0) return null;
  final months = (remainingCents + monthlyCents - 1) ~/ monthlyCents;
  return DateTime(now.year, now.month + months);
}

List<GoalView> buildGoalViews({
  required List<GoalRow> goals,
  required List<GoalContributionRow> contributions,
  required DateTime now,
}) {
  final added = <String, int>{};
  for (final c in contributions) {
    if (c.deletedAt != null) continue;
    added[c.goalId] = (added[c.goalId] ?? 0) + c.amountCents;
  }
  final views = [
    for (final g in goals)
      if (g.deletedAt == null)
        () {
          final saved = g.savedCents + (added[g.id] ?? 0);
          final remaining = g.targetCents > saved ? g.targetCents - saved : 0;
          return GoalView(
            goal: g,
            savedCents: saved,
            projectedFinish: projectFinish(
              remainingCents: remaining,
              monthlyCents: g.monthlyCents,
              now: now,
            ),
          );
        }(),
  ];
  views.sort(
    (a, b) => a.goal.name.toLowerCase().compareTo(b.goal.name.toLowerCase()),
  );
  return views;
}

int totalSaved(List<GoalView> goals) =>
    goals.fold(0, (sum, g) => sum + g.savedCents);

/// The goal Home shows: the unfinished one that finishes soonest, else the first.
GoalView? featuredGoal(List<GoalView> goals) {
  if (goals.isEmpty) return null;
  final open = goals.where((g) => !g.reached).toList();
  if (open.isEmpty) return goals.first;
  open.sort((a, b) {
    final fa = a.projectedFinish;
    final fb = b.projectedFinish;
    if (fa == null && fb == null) return 0;
    if (fa == null) return 1;
    if (fb == null) return -1;
    return fa.compareTo(fb);
  });
  return open.first;
}

/// "done by Oct 2027", "goal reached", or what is missing to give a date.
String doneByLabel(GoalView g, {String Function(DateTime)? monthYear}) {
  String fmt(DateTime d) =>
      monthYear != null ? monthYear(d) : '${_months[d.month - 1]} ${d.year}';
  if (g.reached) return 'goal reached';
  final finish = g.projectedFinish;
  if (finish != null) return 'done by ${fmt(finish)}';
  final due = g.dueOn;
  if (due != null) return 'aim for ${fmt(due)}';
  return 'no monthly amount yet';
}

/// "Oct 2027", or `null` for no date.
String? monthYearLabel(DateTime? d) =>
    d == null ? null : '${_months[d.month - 1]} ${d.year}';

const _months = [
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

/// Contribution of one goal for the "Recent contributions" list.
class ContributionEntry {
  const ContributionEntry({
    required this.id,
    required this.goalName,
    required this.addedByUserId,
    required this.day,
    required this.cents,
  });

  final String id;
  final String goalName;
  final String? addedByUserId;
  final DateTime day;
  final int cents;
}

List<ContributionEntry> recentContributions({
  required List<GoalRow> goals,
  required List<GoalContributionRow> contributions,
  int limit = 5,
}) {
  final names = {
    for (final g in goals)
      if (g.deletedAt == null) g.id: g.name,
  };
  final live =
      contributions
          .where((c) => c.deletedAt == null && names.containsKey(c.goalId))
          .toList()
        ..sort((a, b) {
          final byDay = b.contributedOn.compareTo(a.contributedOn);
          return byDay != 0 ? byDay : b.updatedAt.compareTo(a.updatedAt);
        });
  return [
    for (final c in live.take(limit))
      ContributionEntry(
        id: c.id,
        goalName: names[c.goalId]!,
        addedByUserId: c.addedBy,
        day: parseDay(c.contributedOn),
        cents: c.amountCents,
      ),
  ];
}
