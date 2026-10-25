import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/time.dart';
import '../family/member_providers.dart';
import 'data/goal_repository.dart';
import 'domain/goal_calculations.dart';

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
    householdId: ref.watch(activeHouseholdIdProvider),
  ),
);

final goalRowsProvider = StreamProvider<List<GoalRow>>(
  (ref) => ref.watch(goalRepositoryProvider).watchGoals(),
);

final contributionRowsProvider = StreamProvider<List<GoalContributionRow>>(
  (ref) => ref.watch(goalRepositoryProvider).watchContributions(),
);

/// Live goals with what has been saved and when each finishes.
final goalViewsProvider = Provider<AsyncValue<List<GoalView>>>((ref) {
  final goals = ref.watch(goalRowsProvider);
  final contributions = ref.watch(contributionRowsProvider);
  if (goals.hasError) {
    return AsyncError(goals.error!, goals.stackTrace ?? StackTrace.empty);
  }
  if (contributions.hasError) {
    return AsyncError(
      contributions.error!,
      contributions.stackTrace ?? StackTrace.empty,
    );
  }
  if (!goals.hasValue || !contributions.hasValue) return const AsyncLoading();
  return AsyncData(
    buildGoalViews(
      goals: goals.requireValue,
      contributions: contributions.requireValue,
      now: ref.watch(clockProvider)(),
    ),
  );
});

final recentContributionsProvider = Provider<List<ContributionEntry>>((ref) {
  final goals = ref.watch(goalRowsProvider).value ?? const [];
  final contributions = ref.watch(contributionRowsProvider).value ?? const [];
  return recentContributions(goals: goals, contributions: contributions);
});
