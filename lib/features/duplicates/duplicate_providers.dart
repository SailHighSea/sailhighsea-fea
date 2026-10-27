import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/time.dart';
import '../auth/auth_providers.dart';
import '../expenses/expense_providers.dart';
import '../family/member_providers.dart';
import 'duplicate_finder.dart';

const _kResolved = 'duplicates.resolved';

/// Pairs the person has already answered ("same" or "different"), kept on this device so the
/// question is not asked again.
class DuplicateDecisions extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_kResolved);
    if (raw == null) return {};
    try {
      return {...(jsonDecode(raw) as List).cast<String>()};
    } on Object {
      return {};
    }
  }

  Future<void> resolve(DuplicatePair pair) {
    state = {...state, pair.key};
    // Keep the list from growing for ever: the newest 500 answers are enough.
    final list = state.toList();
    final kept = list.length > 500 ? list.sublist(list.length - 500) : list;
    return ref
        .read(sharedPreferencesProvider)
        .setString(_kResolved, jsonEncode(kept));
  }
}

final duplicateDecisionsProvider =
    NotifierProvider<DuplicateDecisions, Set<String>>(DuplicateDecisions.new);

/// Expenses of the last three months, for the duplicate check.
final _recentExpensesProvider = StreamProvider<List<ExpenseRow>>((ref) {
  final now = ref.watch(clockProvider)();
  return ref
      .watch(expenseRepositoryProvider)
      .watchRange(
        DateTime(now.year, now.month - 3),
        DateTime(now.year, now.month + 1, 0),
      );
});

/// Entries that two different people probably both added, not answered yet.
final duplicatePairsProvider = Provider<List<DuplicatePair>>((ref) {
  // Only where other people's entries arrive: a person using the app alone has nothing to compare.
  if (!ref.watch(canSeeEveryoneProvider)) return const [];
  final rows = ref.watch(_recentExpensesProvider).value;
  if (rows == null) return const [];
  return findSharedDuplicates(
    rows,
    me: ref.watch(currentUserIdProvider),
    resolved: ref.watch(duplicateDecisionsProvider),
  );
});

/// Pairs the person chose to look at later, this session only.
final duplicatesLaterProvider = NotifierProvider<DuplicatesLater, Set<String>>(
  DuplicatesLater.new,
);

class DuplicatesLater extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};
  void add(String key) => state = {...state, key};
}

/// Used by the dialog's hint text.
String duplicateWhy(ExpenseRow a, ExpenseRow b) =>
    a.note.trim().isEmpty && b.note.trim().isEmpty
    ? 'Same day and same amount.'
    : 'Same day, amount and description.';
