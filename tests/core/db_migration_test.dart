import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('a version 2 database upgrades to 3 and keeps its expenses', () async {
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
          ..execute('PRAGMA user_version = 2'),
      ),
    );
    addTearDown(db.close);
    expect(await db.select(db.syncState).get(), isEmpty);
    expect(await db.select(db.syncIssues).get(), isEmpty);
    expect((await db.select(db.expenses).get()).single.id, 'e1');
  });
}
