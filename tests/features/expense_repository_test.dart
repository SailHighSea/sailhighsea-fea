import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/features/expenses/data/category_repository.dart';
import 'package:family_expenses/features/expenses/data/day_format.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository expenses;
  late CategoryRepository categories;
  var clock = DateTime(2026, 10, 23, 12);

  setUp(() {
    clock = DateTime(2026, 10, 23, 12);
    db = AppDatabase(NativeDatabase.memory(), clock: () => clock);
    expenses = ExpenseRepository(db, clock: () => clock);
    categories = CategoryRepository(db, clock: () => clock);
  });
  tearDown(() => db.close());

  test('day format round trips and sorts as text', () {
    expect(formatDay(DateTime(2026, 3, 7)), '2026-03-07');
    expect(parseDay('2026-03-07'), DateTime(2026, 3, 7));
    expect(
      formatDay(DateTime(2026, 10, 9))
          .compareTo(formatDay(DateTime(2026, 10, 10))),
      lessThan(0),
    );
  });

  group('expenses', () {
    test(
      'add stores integer cents, trims the note and marks the row dirty',
      () async {
        final id = await expenses.add(
          amountCents: 4820,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 23),
          note: '  Groceries ',
          createdBy: 'You',
        );
        final row = (await expenses.getById(id))!;
        expect(row.amountCents, 4820);
        expect(row.note, 'Groceries');
        expect(row.spentOn, '2026-10-23');
        expect(row.createdBy, 'You');
        expect(row.dirty, isTrue);
        expect(row.deletedAt, isNull);
        expect(row.updatedAt, clock);
        expect(row.householdId, 'local');
      },
    );

    test('rejects zero and negative amounts', () async {
      for (final bad in [0, -1]) {
        expect(
          () => expenses.add(
            amountCents: bad,
            categoryId: 'default-food',
            spentOn: DateTime(2026, 10, 1),
          ),
          throwsArgumentError,
        );
      }
    });

    test(
      'update changes fields, bumps updated_at and keeps it dirty',
      () async {
        final id = await expenses.add(
          amountCents: 100,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 1),
        );
        await (db.update(db.expenses)..where((e) => e.id.equals(id))).write(
          const ExpensesCompanion(dirty: Value(false)),
        );
        clock = DateTime(2026, 10, 24, 9);
        await expenses.update(
          id,
          amountCents: 250,
          categoryId: 'default-bills',
          spentOn: DateTime(2026, 10, 2),
          note: 'Rent',
        );
        final row = (await expenses.getById(id))!;
        expect(row.amountCents, 250);
        expect(row.categoryId, 'default-bills');
        expect(row.spentOn, '2026-10-02');
        expect(row.note, 'Rent');
        expect(row.updatedAt, clock);
        expect(row.dirty, isTrue);
      },
    );

    test(
      'soft delete hides the row but keeps it, and restore brings it back',
      () async {
        final id = await expenses.add(
          amountCents: 500,
          categoryId: 'default-food',
          spentOn: DateTime(2026, 10, 3),
        );
        clock = DateTime(2026, 10, 25);
        await expenses.softDelete(id);

        expect(await expenses.getById(id), isNull);
        final raw = await (db.select(
          db.expenses,
        )..where((e) => e.id.equals(id))).getSingle();
        expect(
          raw.deletedAt,
          clock,
          reason: 'row is kept so the delete can sync',
        );
        expect(raw.dirty, isTrue);
        expect(await expenses.watchMonth(DateTime(2026, 10)).first, isEmpty);

        await expenses.restore(id);
        expect((await expenses.getById(id))!.deletedAt, isNull);
        expect(
          await expenses.watchMonth(DateTime(2026, 10)).first,
          hasLength(1),
        );
      },
    );

    test(
      'range and month queries include both ends and nothing outside',
      () async {
        for (final day in [
          '2026-09-30',
          '2026-10-01',
          '2026-10-31',
          '2026-11-01',
        ]) {
          await expenses.add(
            amountCents: 100,
            categoryId: 'default-food',
            spentOn: parseDay(day),
          );
        }
        final october = await expenses.watchMonth(DateTime(2026, 10)).first;
        expect(october.map((e) => e.spentOn), ['2026-10-31', '2026-10-01']);
        final range = await expenses
            .watchRange(DateTime(2026, 9, 30), DateTime(2026, 10, 1))
            .first;
        expect(range.map((e) => e.spentOn), ['2026-10-01', '2026-09-30']);
      },
    );

    test('streams update when data changes', () async {
      final emissions = <int>[];
      final sub = expenses
          .watchMonth(DateTime(2026, 10))
          .listen((rows) => emissions.add(rows.length));
      await pumpEventQueue();
      await expenses.add(
        amountCents: 100,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 5),
      );
      await pumpEventQueue();
      expect(emissions, [0, 1]);
      await sub.cancel();
    });

    test('same-day expenses are ordered newest edit first', () async {
      await expenses.add(
        amountCents: 100,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 5),
        note: 'first',
      );
      clock = DateTime(2026, 10, 23, 13);
      await expenses.add(
        amountCents: 200,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 5),
        note: 'second',
      );
      final rows = await expenses.watchMonth(DateTime(2026, 10)).first;
      expect(rows.map((e) => e.note), ['second', 'first']);
    });

    test('categories are enforced by a foreign key', () async {
      await expectLater(
        expenses.add(
          amountCents: 100,
          categoryId: 'no-such-category',
          spentOn: DateTime(2026, 10, 1),
        ),
        throwsA(anything),
      );
    });
  });

  group('categories', () {
    test('defaults come first in order', () async {
      final all = await categories.getAll();
      expect(all.map((c) => c.name), [
        'Food',
        'Bills',
        'Transport',
        'Fun',
        'Health',
        'Other',
      ]);
      expect(all.map((c) => c.color), [
        'food',
        'bills',
        'transport',
        'fun',
        'health',
        'other',
      ]);
    });

    test('add appends a category with the next colour and ignores duplicates by name', () async {
      final pets = await categories.add('  Hobby ');
      expect(pets.name, 'Hobby');
      expect(pets.sort, 6);
      expect(pets.color, newCategoryColorKeys.first);
      expect(pets.dirty, isTrue);

      final again = await categories.add('hobby');
      expect(again.id, pets.id);
      expect(await categories.getAll(), hasLength(7));

      final school = await categories.add('Stuff');
      expect(school.color, newCategoryColorKeys[1]);
    });

    test('a name with a known word gets that icon and colour', () async {
      final c = await categories.add('Grocery run');
      expect(c.icon, 'local_grocery_store');
      expect(c.color, 'green');
      final plain = await categories.add('Hobby');
      expect(plain.icon, isNull);
    });

    test(
      'update changes name, icon and colour; another name is refused',
      () async {
        final a = await categories.add('Hobby');
        await categories.add('Stuff');
        await categories.update(
          a.id,
          name: 'Crafts',
          color: 'violet',
          icon: 'toys',
        );
        final row = (await categories.getAll()).firstWhere((c) => c.id == a.id);
        expect([row.name, row.color, row.icon], ['Crafts', 'violet', 'toys']);
        expect(row.dirty, isTrue);
        expect(
          () =>
              categories.update(a.id, name: 'stuff', color: 'red', icon: null),
          throwsArgumentError,
        );
      },
    );

    test(
      'delete moves the expenses to Other and removes the category',
      () async {
        final a = await categories.add('Hobby');
        final id = await expenses.add(
          amountCents: 500,
          categoryId: a.id,
          spentOn: DateTime(2026, 10, 1),
          note: 'Glue',
          createdBy: 'You',
        );
        await categories.delete(a.id);
        expect((await categories.getAll()).any((c) => c.id == a.id), isFalse);
        final e = await (db.select(
          db.expenses,
        )..where((x) => x.id.equals(id))).getSingle();
        expect(e.categoryId, 'default-other');
        await categories.delete('default-other');
        expect(
          (await categories.getAll()).any((c) => c.id == 'default-other'),
          isTrue,
        );
      },
    );

    test('empty names are rejected', () async {
      expect(() => categories.add('   '), throwsArgumentError);
    });
  });
}
