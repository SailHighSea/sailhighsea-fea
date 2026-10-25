import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase memoryDb() => AppDatabase(
  NativeDatabase.memory(),
  clock: () => DateTime(2026, 10, 23, 12),
);

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDb());
  tearDown(() => db.close());

  test('a new database is seeded with the six default categories', () async {
    final rows = await (db.select(
      db.categories,
    )..orderBy([(c) => OrderingTerm.asc(c.sort)])).get();
    expect(rows.map((r) => r.name), [
      'Food',
      'Bills',
      'Transport',
      'Fun',
      'Health',
      'Other',
    ]);
    expect(rows.every((r) => r.dirty && r.deletedAt == null), isTrue);
  });
}
