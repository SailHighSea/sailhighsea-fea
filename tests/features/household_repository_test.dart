import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/tables.dart';
import 'package:family_expenses/features/expenses/data/category_repository.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/family/data/household_remote.dart';
import 'package:family_expenses/features/family/data/household_repository.dart';
import 'package:family_expenses/features/family/domain/role.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late HouseholdRepository repo;
  final now = DateTime(2026, 10, 25, 9);

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory(), clock: () => now);
    repo = HouseholdRepository(db, clock: () => now);
  });

  tearDown(() => db.close());

  test('stores the household and its members, owner first', () async {
    await repo.replaceFromRemote(sampleHousehold());
    final household = await repo.watchMine('user-maya').first;
    expect(household?.name, 'Our household');
    expect(household?.ownerId, 'user-you');

    final members = await repo.watchMembers('household-1').first;
    expect(members.map((m) => m.displayName), ['You', 'Maya', 'Sam', 'Ed']);
    expect(members.map((m) => m.role), ['owner', 'admin', 'viewer', 'editor']);
  });

  test('a refresh follows the server: new roles, removed members', () async {
    await repo.replaceFromRemote(sampleHousehold());
    final changed = RemoteHousehold(
      id: 'household-1',
      name: 'Our household',
      currency: 'SGD',
      ownerId: 'user-you',
      members: [
        for (final m in sampleHousehold().members)
          if (m.userId != 'user-sam')
            RemoteMember(
              userId: m.userId,
              role: m.userId == 'user-ed' ? Role.admin : m.role,
              displayName: m.displayName,
              joinedAt: m.joinedAt,
            ),
      ],
    );
    await repo.replaceFromRemote(changed);
    final members = await repo.watchMembers('household-1').first;
    expect(members.map((m) => m.userId), isNot(contains('user-sam')));
    expect(members.firstWhere((m) => m.userId == 'user-ed').role, 'admin');
    expect(await repo.watchMine('user-sam').first, isNull);
  });

  test('forgetting a household removes it and its members', () async {
    await repo.replaceFromRemote(sampleHousehold());
    await repo.forget('household-1');
    expect(await repo.watchMine('user-maya').first, isNull);
    expect(await repo.watchMembers('household-1').first, isEmpty);
  });

  group('adopting what was entered before signing in', () {
    Future<void> seedLocal() async {
      final expenses = ExpenseRepository(db, clock: () => now);
      await expenses.add(
        amountCents: 1200,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 20),
        note: 'Lunch',
        createdBy: 'You',
      );
      await CategoryRepository(db, clock: () => now).add('Pets');
    }

    test(
      'creating a household takes everything along and marks it for sync',
      () async {
        await seedLocal();
        await repo.adoptLocalData(
          householdId: 'household-1',
          userId: 'user-maya',
          everything: true,
        );

        final mine = ExpenseRepository(db, householdId: 'household-1');
        final rows = await mine.watchMonth(DateTime(2026, 10)).first;
        expect(rows.single.note, 'Lunch');
        expect(
          rows.single.createdBy,
          'user-maya',
          reason: '"You" becomes the real user',
        );
        expect(rows.single.dirty, isTrue);

        final categories = await CategoryRepository(
          db,
          householdId: 'household-1',
        ).getAll();
        expect(categories.map((c) => c.name), containsAll(['Food', 'Pets']));
        expect(
          await ExpenseRepository(db).watchMonth(DateTime(2026, 10)).first,
          isEmpty,
          reason: 'nothing is left under the local household',
        );
      },
    );

    test('joining keeps local entries off the shared household', () async {
      await seedLocal();
      await repo.adoptLocalData(
        householdId: 'household-1',
        userId: 'user-maya',
        everything: false,
      );

      final shared = ExpenseRepository(db, householdId: 'household-1');
      expect(await shared.watchMonth(DateTime(2026, 10)).first, isEmpty);
      final local = await ExpenseRepository(db)
          .watchMonth(DateTime(2026, 10))
          .first;
      expect(
        local.single.note,
        'Lunch',
        reason: 'not deleted, still on this device',
      );

      final categories = await CategoryRepository(
        db,
        householdId: 'household-1',
      ).getAll();
      expect(categories.map((c) => c.name), isNot(contains('Pets')));
      expect(categories.map((c) => c.id), contains('default-food'));
    });
  });

  test(
    'households are separate: one household never sees another\'s expenses',
    () async {
      final a = ExpenseRepository(db, clock: () => now, householdId: 'a');
      final b = ExpenseRepository(db, clock: () => now, householdId: 'b');
      await db
          .into(db.households)
          .insert(
            HouseholdsCompanion.insert(
              id: 'a',
              name: 'A',
              ownerId: 'u',
              updatedAt: now,
            ),
          );
      // Category ids are unique on the device, so the household's categories are re-keyed.
      await db.customStatement("UPDATE categories SET household_id = 'a'");
      await a.add(
        amountCents: 100,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 1),
      );
      await b.add(
        amountCents: 999,
        categoryId: 'default-food',
        spentOn: DateTime(2026, 10, 1),
      );
      expect(
        (await a.watchMonth(DateTime(2026, 10)).first).single.amountCents,
        100,
      );
      expect(
        (await b.watchMonth(DateTime(2026, 10)).first).single.amountCents,
        999,
      );
      expect(localHouseholdId, 'local');
    },
  );

  test('schema version covers the new tables', () {
    expect(db.schemaVersion, 2);
  });
}
