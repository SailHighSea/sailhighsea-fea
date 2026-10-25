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

@DriftDatabase(tables: [Categories, Expenses, Households, Members])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Bump when a table changes and add a step to [migration].
  @override
  int get schemaVersion => 2;

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
      // Future versions add steps here, for example:
      //   if (from < 3) await m.addColumn(expenses, expenses.someNewColumn);
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
