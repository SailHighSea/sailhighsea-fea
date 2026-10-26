import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/ids.dart';
import '../../../core/db/tables.dart' show localHouseholdId;
import '../../../core/theme/category_style.dart';

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
  ///
  /// With no [color] or [icon], they come from the name's words ("Grocery run" gets the grocery
  /// icon) and otherwise the next colour in turn.
  Future<CategoryRow> add(String name, {String? color, String? icon}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    final existing = await getAll();
    for (final c in existing) {
      if (c.name.toLowerCase() == trimmed.toLowerCase()) return c;
    }
    final custom = existing.where((c) => !c.id.startsWith('default-')).length;
    final turn = newCategoryColorKeys[custom % newCategoryColorKeys.length];
    final guess = guessCategoryStyle(trimmed, fallbackColor: turn);
    final row = CategoriesCompanion.insert(
      id: newId(),
      householdId: Value(householdId),
      name: trimmed,
      color: color ?? guess.color,
      icon: Value(icon ?? (guess.icon == 'category' ? null : guess.icon)),
      sort: Value(existing.isEmpty ? 0 : existing.last.sort + 1),
      updatedAt: _clock(),
    );
    await _db.into(_db.categories).insert(row);
    return (_db.select(
      _db.categories,
    )..where((c) => c.id.equals(row.id.value))).getSingle();
  }

  /// Changes a category's name, icon and colour. Another category's name is refused.
  Future<void> update(
    String id, {
    required String name,
    required String color,
    required String? icon,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    for (final c in await getAll()) {
      if (c.id != id && c.name.toLowerCase() == trimmed.toLowerCase()) {
        throw ArgumentError.value(name, 'name', 'is used by another category');
      }
    }
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(trimmed),
        color: Value(color),
        icon: Value(icon),
        updatedAt: Value(_clock()),
        dirty: const Value(true),
      ),
    );
  }

  /// Removes a category; its expenses move to Other. "Other" itself stays.
  Future<void> delete(String id) async {
    if (id == otherCategoryId) return;
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.expenses,
      )..where((e) => e.categoryId.equals(id))).write(
        ExpensesCompanion(
          categoryId: const Value(otherCategoryId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
    });
  }
}
