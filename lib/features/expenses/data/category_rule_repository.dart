import '../../../core/db/app_database.dart';
import '../../import/category_guess.dart';

/// Remembers which category a shop (a description) was put in, so the same shop is sorted
/// automatically next time, in imports and everywhere else. Stored on this device only.
class CategoryRuleRepository {
  CategoryRuleRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<Map<String, String>> all() async => {
    for (final r in await _db.select(_db.categoryRules).get())
      r.key: r.categoryId,
  };

  /// A later decision for the same shop replaces the earlier one. Descriptions that carry no
  /// letters (or only one or two) are not remembered: they say nothing about a shop.
  Future<void> remember(String description, String categoryId) async {
    final key = descriptionKey(description);
    if (key.length < 3) {
      return;
    }
    await _db
        .into(_db.categoryRules)
        .insertOnConflictUpdate(
          CategoryRulesCompanion.insert(
            key: key,
            categoryId: categoryId,
            updatedAt: _clock(),
          ),
        );
  }

  Future<void> rememberAll(Iterable<(String, String)> decisions) async {
    for (final d in decisions) {
      await remember(d.$1, d.$2);
    }
  }
}
