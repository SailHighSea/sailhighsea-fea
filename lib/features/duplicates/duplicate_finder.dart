import '../../core/db/app_database.dart';
import '../import/category_guess.dart' show descriptionKey;

/// Whether two descriptions could be the same purchase: the same words once digits and
/// punctuation are ignored, one of them empty, or one containing the other ("Lulu" and
/// "Lulu Hypermarket, Doha").
bool similarDescriptions(String a, String b) {
  final x = descriptionKey(a), y = descriptionKey(b);
  if (x.isEmpty || y.isEmpty || x == y) return true;
  final (short, long) = x.length <= y.length ? (x, y) : (y, x);
  return short.length >= 4 && long.contains(short);
}

/// Two expenses on the same day, for the same amount and about the same thing, added by different
/// people: probably one purchase that two people both wrote down.
class DuplicatePair {
  const DuplicatePair(this.first, this.second);

  final ExpenseRow first;
  final ExpenseRow second;

  /// Stable for the pair, whichever order the rows come in.
  String get key => first.id.compareTo(second.id) < 0
      ? '${first.id}|${second.id}'
      : '${second.id}|${first.id}';
}

/// Looks through [expenses] for pairs that two different people probably both entered. [me] is the
/// signed-in person's id (entries without an owner, or "You", are theirs). Pairs in [resolved]
/// (already answered) are left out. Two identical purchases by the same person are not reported:
/// buying the same coffee twice is normal.
List<DuplicatePair> findSharedDuplicates(
  List<ExpenseRow> expenses, {
  required String? me,
  Set<String> resolved = const {},
  int limit = 50,
}) {
  String owner(ExpenseRow e) {
    final by = e.createdBy;
    return (by == null || by == 'You') ? (me ?? 'You') : by;
  }

  final groups = <String, List<ExpenseRow>>{};
  for (final e in expenses) {
    if (e.deletedAt != null) continue;
    groups.putIfAbsent('${e.spentOn}|${e.amountCents}', () => []).add(e);
  }
  final out = <DuplicatePair>[];
  for (final g in groups.values) {
    if (g.length < 2) continue;
    g.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    for (var i = 0; i < g.length; i++) {
      for (var j = i + 1; j < g.length; j++) {
        if (owner(g[i]) == owner(g[j])) continue;
        if (!similarDescriptions(g[i].note, g[j].note)) continue;
        final pair = DuplicatePair(g[i], g[j]);
        if (resolved.contains(pair.key)) continue;
        out.add(pair);
        if (out.length >= limit) return out;
      }
    }
  }
  out.sort((a, b) => b.second.spentOn.compareTo(a.second.spentOn));
  return out;
}
