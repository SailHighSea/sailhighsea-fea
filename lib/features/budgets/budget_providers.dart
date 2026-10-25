import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/appearance_provider.dart';

/// Monthly budget in cents used by Home until Phase 5 adds real budgets (overall and per
/// category). Defaults to the mockups' S$2,500.
const defaultMonthlyBudgetCents = 250000;

const _kMonthlyBudget = 'budget.monthlyCents';

class MonthlyBudget extends Notifier<int> {
  @override
  int build() =>
      ref.watch(sharedPreferencesProvider).getInt(_kMonthlyBudget) ??
      defaultMonthlyBudgetCents;

  Future<void> set(int cents) {
    state = cents;
    return ref.read(sharedPreferencesProvider).setInt(_kMonthlyBudget, cents);
  }
}

final monthlyBudgetCentsProvider = NotifierProvider<MonthlyBudget, int>(
  MonthlyBudget.new,
);
