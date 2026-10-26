import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../expenses/data/day_format.dart';

/// One person's month in the "Everyone" overview. Money is integer cents.
class PersonSpend {
  const PersonSpend({
    required this.userId,
    required this.name,
    required this.isYou,
    required this.hasLeft,
    required this.role,
    required this.spentCents,
    required this.sharePercent,
    required this.todayCents,
    required this.weekCents,
    required this.expenseCount,
    this.topCategoryName,
    this.topCategoryColorKey,
    this.allowanceCents,
  });

  final String userId;
  final String name;
  final bool isYou;

  /// No longer in the household; their past expenses stay.
  final bool hasLeft;

  /// `owner`, `admin`, `editor` or `viewer`; `null` for someone who left.
  final String? role;
  final int spentCents;

  /// Whole percent of the family total; all shares add up to 100.
  final int sharePercent;
  final int todayCents;
  final int weekCents;
  final int expenseCount;
  final String? topCategoryName;
  final String? topCategoryColorKey;

  /// The monthly allowance set for this person, if any.
  final int? allowanceCents;

  int? get allowanceLeftCents =>
      allowanceCents == null ? null : allowanceCents! - spentCents;
  bool get overAllowance =>
      allowanceCents != null && spentCents > allowanceCents!;
  double get allowanceFraction => allowanceCents == null || allowanceCents! <= 0
      ? 0
      : (spentCents / allowanceCents!).clamp(0.0, 1.0);
}

class OverviewData {
  const OverviewData({
    required this.month,
    required this.totalCents,
    required this.budgetCents,
    required this.people,
  });

  final DateTime month;
  final int totalCents;
  final int budgetCents;

  /// Biggest spender first.
  final List<PersonSpend> people;

  int get leftCents => budgetCents - totalCents;
  bool get isOver => totalCents > budgetCents;
  int get percentUsed => budgetCents <= 0
      ? 0
      : (totalCents * 100 + budgetCents ~/ 2) ~/ budgetCents;
  double get usedFraction =>
      budgetCents <= 0 ? 0 : (totalCents / budgetCents).clamp(0.0, 1.0);
}

/// Splits 100 over [amounts] by size so the result always adds up to 100 (largest remainder).
/// All zeros give all zeros.
List<int> sharePercents(List<int> amounts) {
  final total = amounts.fold<int>(0, (s, a) => s + a);
  if (total <= 0) return List.filled(amounts.length, 0);
  final whole = [for (final a in amounts) a * 100 ~/ total];
  final remainders = [for (final a in amounts) a * 100 % total];
  var missing = 100 - whole.fold<int>(0, (s, w) => s + w);
  final order = List<int>.generate(amounts.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      return byRemainder != 0 ? byRemainder : amounts[b].compareTo(amounts[a]);
    });
  for (final i in order) {
    if (missing <= 0) break;
    whole[i]++;
    missing--;
  }
  return whole;
}

/// The day Today and This week are measured to: today for the current month, the last day of
/// a past month, the first day of a future month (like Home).
DateTime overviewReferenceDay(DateTime month, DateTime now) {
  final today = now.dateOnly;
  final monthIndex = month.year * 12 + month.month;
  final todayIndex = today.year * 12 + today.month;
  if (monthIndex == todayIndex) return today;
  if (monthIndex < todayIndex) {
    return DateTime(month.year, month.month, daysInMonth(month));
  }
  return DateTime(month.year, month.month);
}

/// First day [buildOverview] needs expenses from (the week can reach into the month before).
DateTime overviewRangeStart(DateTime month, DateTime now) {
  final weekStart = overviewReferenceDay(
    month,
    now,
  ).subtract(const Duration(days: 6));
  final first = DateTime(month.year, month.month);
  return weekStart.isBefore(first) ? weekStart : first;
}

/// Per-person spending for [month]. [expenses] must cover [overviewRangeStart] to the end of
/// the month. Every member is listed, even with nothing spent; someone who left appears only
/// if they have spending. `created_by` of `null` or "You" (entries made before accounts) is
/// [currentUserId].
OverviewData buildOverview({
  required DateTime month,
  required DateTime now,
  required List<ExpenseRow> expenses,
  required List<CategoryRow> categories,
  required List<MemberRow> members,
  required String? currentUserId,
  required int budgetCents,
  Map<String, int> allowances = const {},
}) {
  final prefix = formatDay(DateTime(month.year, month.month)).substring(0, 7);
  final ref = overviewReferenceDay(month, now);
  final refText = formatDay(ref);
  final weekStartText = formatDay(ref.subtract(const Duration(days: 6)));
  final categoryById = {for (final c in categories) c.id: c};

  String keyOf(String? createdBy) {
    if (createdBy == null || createdBy == 'You') return currentUserId ?? 'You';
    return createdBy;
  }

  final spent = <String, int>{};
  final today = <String, int>{};
  final week = <String, int>{};
  final counts = <String, int>{};
  final byCategory = <String, Map<String, int>>{};
  for (final e in expenses) {
    if (e.deletedAt != null) continue;
    final who = keyOf(e.createdBy);
    if (e.spentOn.startsWith(prefix)) {
      spent[who] = (spent[who] ?? 0) + e.amountCents;
      counts[who] = (counts[who] ?? 0) + 1;
      final cats = byCategory.putIfAbsent(who, () => {});
      cats[e.categoryId] = (cats[e.categoryId] ?? 0) + e.amountCents;
    }
    if (e.spentOn == refText) {
      today[who] = (today[who] ?? 0) + e.amountCents;
    }
    if (e.spentOn.compareTo(weekStartText) >= 0 &&
        e.spentOn.compareTo(refText) <= 0) {
      week[who] = (week[who] ?? 0) + e.amountCents;
    }
  }

  final memberById = {for (final m in members) m.userId: m};
  final ids = <String>{
    for (final m in members) m.userId,
    for (final id in spent.keys) id,
  };

  final rows = <({String id, int spent})>[
    for (final id in ids) (id: id, spent: spent[id] ?? 0),
  ];
  final total = rows.fold<int>(0, (s, r) => s + r.spent);

  // Order first so the shares line up with the sorted list.
  String nameOf(String id) {
    final m = memberById[id];
    if (id == currentUserId || (currentUserId == null && id == 'You')) {
      return 'You';
    }
    return m?.displayName ?? 'Former member';
  }

  rows.sort((a, b) {
    final bySpent = b.spent.compareTo(a.spent);
    if (bySpent != 0) return bySpent;
    return nameOf(a.id).toLowerCase().compareTo(nameOf(b.id).toLowerCase());
  });
  final shares = sharePercents([for (final r in rows) r.spent]);

  final people = <PersonSpend>[];
  for (var i = 0; i < rows.length; i++) {
    final id = rows[i].id;
    final member = memberById[id];
    final left = member == null;
    if (left && rows[i].spent == 0) continue;
    String? topName;
    String? topColor;
    final cats = byCategory[id];
    if (cats != null && cats.isNotEmpty) {
      final top = cats.entries.reduce(
        (a, b) =>
            b.value > a.value ||
                (b.value == a.value && b.key.compareTo(a.key) < 0)
            ? b
            : a,
      );
      topName = categoryById[top.key]?.name ?? 'Other';
      topColor = categoryById[top.key]?.color ?? 'other';
    }
    people.add(
      PersonSpend(
        userId: id,
        name: left ? 'Former member (left)' : nameOf(id),
        isYou: nameOf(id) == 'You',
        hasLeft: left,
        role: member?.role,
        spentCents: rows[i].spent,
        sharePercent: shares[i],
        todayCents: today[id] ?? 0,
        weekCents: week[id] ?? 0,
        expenseCount: counts[id] ?? 0,
        topCategoryName: topName,
        topCategoryColorKey: topColor,
        allowanceCents: allowances[id],
      ),
    );
  }
  return OverviewData(
    month: DateTime(month.year, month.month),
    totalCents: total,
    budgetCents: budgetCents,
    people: people,
  );
}

/// One category's month split by person: [byPerson] holds cents per person id (the ids in
/// [OverviewData.people]).
class CategoryByPerson {
  const CategoryByPerson({
    required this.name,
    required this.colorKey,
    required this.totalCents,
    required this.byPerson,
  });

  final String name;
  final String colorKey;
  final int totalCents;
  final Map<String, int> byPerson;
}

/// The biggest categories of [month], each split by who spent it. Same person keys as
/// [buildOverview] (`null` or "You" is [currentUserId]).
List<CategoryByPerson> buildCategoriesByPerson({
  required DateTime month,
  required List<ExpenseRow> expenses,
  required List<CategoryRow> categories,
  required String? currentUserId,
}) {
  final prefix = formatDay(DateTime(month.year, month.month)).substring(0, 7);
  final categoryById = {for (final c in categories) c.id: c};
  final split = <String, Map<String, int>>{};
  for (final e in expenses) {
    if (e.deletedAt != null || !e.spentOn.startsWith(prefix)) continue;
    final by = e.createdBy;
    final who = (by == null || by == 'You') ? (currentUserId ?? 'You') : by;
    final cats = split.putIfAbsent(e.categoryId, () => {});
    cats[who] = (cats[who] ?? 0) + e.amountCents;
  }
  final out = [
    for (final entry in split.entries)
      CategoryByPerson(
        name: categoryById[entry.key]?.name ?? 'Other',
        colorKey: categoryById[entry.key]?.color ?? 'other',
        totalCents: entry.value.values.fold<int>(0, (s, v) => s + v),
        byPerson: entry.value,
      ),
  ];
  out.sort((a, b) {
    final c = b.totalCents.compareTo(a.totalCents);
    return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}
