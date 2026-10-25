import 'package:family_expenses/core/db/app_database.dart';

final _stamp = DateTime(2026, 10, 1, 8);

/// An in-memory [ExpenseRow] for calculation tests.
ExpenseRow expenseRow({
  required String spentOn,
  required int cents,
  String category = 'default-food',
  String id = '',
  String note = '',
  String? createdBy,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return ExpenseRow(
    id: id.isEmpty ? 'e-$spentOn-$cents-$category-$note' : id,
    householdId: 'local',
    amountCents: cents,
    categoryId: category,
    note: note,
    spentOn: spentOn,
    createdBy: createdBy,
    receiptPath: null,
    updatedAt: updatedAt ?? _stamp,
    deletedAt: deletedAt,
    dirty: true,
  );
}

/// The six default categories as rows.
List<CategoryRow> defaultCategoryRows() => [
  for (var i = 0; i < defaultCategories.length; i++)
    CategoryRow(
      id: defaultCategories[i].id,
      householdId: 'local',
      name: defaultCategories[i].name,
      color: defaultCategories[i].color,
      icon: defaultCategories[i].icon,
      sort: i,
      updatedAt: _stamp,
      deletedAt: null,
      dirty: true,
    ),
];
