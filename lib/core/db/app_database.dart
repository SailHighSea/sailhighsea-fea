import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// A category every household starts with. Ids are fixed so two devices that both
/// created the defaults offline end up with the same rows once they sync.
class DefaultCategory {
  const DefaultCategory(this.id, this.name, this.color, this.icon);
  final String id;
  final String name;
  final String color;
  final String icon;
}

/// docs/phases/phase-2-core-expenses.md: Food, Bills, Transport, Fun, Health, Other.
const defaultCategories = <DefaultCategory>[
  DefaultCategory('default-food', 'Food', 'food', 'restaurant'),
  DefaultCategory('default-bills', 'Bills', 'bills', 'receipt'),
  DefaultCategory(
    'default-transport',
    'Transport',
    'transport',
    'directions_bus',
  ),
  DefaultCategory('default-fun', 'Fun', 'fun', 'celebration'),
  DefaultCategory('default-health', 'Health', 'health', 'favorite'),
  DefaultCategory('default-other', 'Other', 'other', 'category'),
];

/// Id of the fallback category.
const otherCategoryId = 'default-other';

@DriftDatabase(
  tables: [
    Categories,
    Expenses,
    Households,
    Members,
    SyncState,
    SyncIssues,
    Budgets,
    Goals,
    GoalContributions,
    Bills,
    SheetPairs,
    Suggestions,
    CategoryRules,
    IncomeEntries,
    SavingsBalances,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Bump when a table changes and add a step to [migration].
  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedDefaultCategories();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Phase 3: the household and its members, cached from the server.
        await m.createTable(households);
        await m.createTable(members);
      }
      if (from < 3) {
        // Phase 4: sync cursors and the changes the server refused.
        await m.createTable(syncState);
        await m.createTable(syncIssues);
      }
      if (from < 4) {
        // Phase 5: budgets, goals (with contributions) and bills.
        await m.createTable(budgets);
        await m.createTable(goals);
        await m.createTable(goalContributions);
        await m.createTable(bills);
      }
      if (from < 5) {
        // Phase 4c: who may see whose spending, and per-person allowances.
        // Tables created earlier in this same upgrade already have the new columns.
        if (from >= 2) await m.addColumn(members, members.visibility);
        if (from >= 4) await m.addColumn(budgets, budgets.userId);
      }
      if (from < 6) {
        // Phase 8: Google Sheets mode (paired family members and their suggestions).
        await m.createTable(sheetPairs);
        await m.createTable(suggestions);
      }
      if (from < 7) {
        // Remembered shop -> category decisions for imports.
        await m.createTable(categoryRules);
      }
      if (from < 8) {
        // Monthly income and total savings (on this device only).
        await m.createTable(incomeEntries);
        await m.createTable(savingsBalances);
      }
      // Future versions add steps here, for example:
      //   if (from < 6) await m.addColumn(expenses, expenses.someNewColumn);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seedDefaultCategories() async {
    final now = _clock();
    await batch((b) {
      b.insertAll(categories, [
        for (var i = 0; i < defaultCategories.length; i++)
          CategoriesCompanion.insert(
            id: defaultCategories[i].id,
            name: defaultCategories[i].name,
            color: defaultCategories[i].color,
            icon: Value(defaultCategories[i].icon),
            sort: Value(i),
            updatedAt: now,
          ),
      ]);
    });
  }
}
