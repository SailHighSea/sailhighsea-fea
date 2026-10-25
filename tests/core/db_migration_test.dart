import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'a version 1 database (no households yet) upgrades without clashes',
    () async {
      final dir = Directory.systemTemp.createTempSync('migration1');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/app.db');
      var db = AppDatabase(NativeDatabase(file));
      await db.select(db.categories).get();
      await db.close();
      db = AppDatabase(
        NativeDatabase(
          file,
          setup: (raw) => raw
            ..execute('DROP TABLE sync_state')
            ..execute('DROP TABLE sync_issues')
            ..execute('DROP TABLE budgets')
            ..execute('DROP TABLE goals')
            ..execute('DROP TABLE goal_contributions')
            ..execute('DROP TABLE bills')
            ..execute('DROP TABLE members')
            ..execute('DROP TABLE households')
            ..execute('PRAGMA user_version = 1'),
        ),
      );
      addTearDown(db.close);
      expect(await db.select(db.members).get(), isEmpty);
      expect(await db.select(db.budgets).get(), isEmpty);
      expect(await db.select(db.categories).get(), isNotEmpty);
    },
  );

  test('a version 2 database upgrades to the current version and keeps its expenses', () async {
    final dir = Directory.systemTemp.createTempSync('migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/app.db');

    var db = AppDatabase(NativeDatabase(file));
    await db.select(db.categories).get(); // create the current schema
    await db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: 'e1',
            amountCents: 500,
            categoryId: 'default-food',
            spentOn: '2026-10-01',
            updatedAt: DateTime(2026, 10, 1),
          ),
        );
    await db.close();

    // Reopen it as what Phase 3 shipped: no sync tables, user_version 2.
    db = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) => raw
          ..execute('DROP TABLE sync_state')
          ..execute('DROP TABLE sync_issues')
          ..execute('DROP TABLE budgets')
          ..execute('DROP TABLE goals')
          ..execute('DROP TABLE goal_contributions')
          ..execute('DROP TABLE bills')
          ..execute('ALTER TABLE members DROP COLUMN visibility')
          ..execute('PRAGMA user_version = 2'),
      ),
    );
    addTearDown(db.close);
    expect(await db.select(db.syncState).get(), isEmpty);
    expect(await db.select(db.syncIssues).get(), isEmpty);
    expect((await db.select(db.expenses).get()).single.id, 'e1');
    expect(await db.select(db.budgets).get(), isEmpty);
    expect(await db.select(db.members).get(), isEmpty);
  });

  test(
    'a version 5 database gains the Google Sheets tables and keeps its data',
    () async {
      final dir = Directory.systemTemp.createTempSync('migration5');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/app.db');

      var db = AppDatabase(NativeDatabase(file));
      await db.select(db.categories).get();
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: 'e1',
              amountCents: 500,
              categoryId: 'default-food',
              spentOn: '2026-10-01',
              updatedAt: DateTime(2026, 10, 1),
            ),
          );
      await db.close();

      // What Phase 4c shipped: no sheet_pairs, no suggestions, user_version 5.
      db = AppDatabase(
        NativeDatabase(
          file,
          setup: (raw) => raw
            ..execute('DROP TABLE sheet_pairs')
            ..execute('DROP TABLE suggestions')
            ..execute('PRAGMA user_version = 5'),
        ),
      );
      addTearDown(db.close);
      expect((await db.select(db.expenses).get()).single.id, 'e1');
      expect(await db.select(db.sheetPairs).get(), isEmpty);
      await db
          .into(db.suggestions)
          .insert(
            SuggestionsCompanion.insert(
              id: 's1',
              memberEmail: 'm@x.test',
              kind: 'budget',
              action: 'add',
              payloadJson: '{}',
              createdAt: DateTime(2026, 10, 1),
              updatedAt: DateTime(2026, 10, 1),
            ),
          );
      expect(await db.select(db.suggestions).get(), hasLength(1));
    },
  );
}
