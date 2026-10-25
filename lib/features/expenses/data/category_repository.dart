import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/ids.dart';
import '../../../core/db/tables.dart' show localHouseholdId;

/// Colour keys handed to new categories in turn; the theme turns a key into a colour.
const newCategoryColorKeys = [
  'purple2',
  'teal',
  'pink',
  'indigo',
  'lime',
  'brown',
];

class CategoryRepository {
  CategoryRepository(
    this._db, {
    DateTime Function()? clock,
    this.householdId = localHouseholdId,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;

  /// Only this household's categories are read and written.
  final String householdId;
  final DateTime Function() _clock;

  Stream<List<CategoryRow>> watchAll() {
    final query = _db.select(_db.categories)
      ..where((c) => c.householdId.equals(householdId) & c.deletedAt.isNull())
      ..orderBy([
        (c) => OrderingTerm.asc(c.sort),
        (c) => OrderingTerm.asc(c.name),
      ]);
    return query.watch();
  }

  Future<List<CategoryRow>> getAll() =>
      (_db.select(_db.categories)
            ..where(
              (c) => c.householdId.equals(householdId) & c.deletedAt.isNull(),
            )
            ..orderBy([(c) => OrderingTerm.asc(c.sort)]))
          .get();

  /// Adds a category after the existing ones and returns it. Names are unique ignoring case.
  Future<CategoryRow> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final existing = await getAll();
    for (final c in existing) {
      if (c.name.toLowerCase() == trimmed.toLowerCase()) return c;
    }
    final custom = existing.where((c) => !c.id.startsWith('default-')).length;
    final row = CategoriesCompanion.insert(
      id: newId(),
      householdId: Value(householdId),
      name: trimmed,
      color: newCategoryColorKeys[custom % newCategoryColorKeys.length],
      sort: Value(existing.isEmpty ? 0 : existing.last.sort + 1),
      updatedAt: _clock(),
    );
    await _db.into(_db.categories).insert(row);
    return (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(row.id.value))).getSingle();
  }
}
