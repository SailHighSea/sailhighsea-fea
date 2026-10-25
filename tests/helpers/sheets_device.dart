import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/sheets_sync/sheets_settings.dart';
import 'package:family_expenses/core/sheets_sync/sheets_sync.dart';
import 'package:family_expenses/features/bills/data/bill_repository.dart';
import 'package:family_expenses/features/budgets/data/budget_repository.dart';
import 'package:family_expenses/features/expenses/data/expense_repository.dart';
import 'package:family_expenses/features/goals/data/goal_repository.dart';
import 'package:family_expenses/features/pairing/pairing_service.dart';
import 'package:family_expenses/features/pairing/suggestion_service.dart';

import 'fake_google.dart';

/// One phone: its own database, its own Google account, and the Sheets-mode services wired the
/// way the app wires them.
class Device {
  Device(
    FakeGoogleWorld world,
    String email,
    String name,
    SheetsRole role, {
    DateTime Function()? clock,
    int batchSize = 200,
  }) : google = world.account(email, name: name),
       db = AppDatabase(NativeDatabase.memory()),
       email = email,
       name = name {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final base = clock;
    this.clock = base ?? () => now;
    settings = SheetsSettings(role: role, displayName: name);
    expenses = ExpenseRepository(db, clock: this.clock);
    pairing = PairingService(
      db: db,
      sheets: google,
      drive: google,
      settings: () => settings,
      updateSettings: (f) async => settings = f(settings),
      myEmail: () => email,
      myName: () => name,
      currencyCode: 'SGD',
      clock: this.clock,
    );
    sync = SheetsSyncCoordinator(
      db: db,
      sheets: google,
      settings: () => settings,
      updateSettings: (f) async => settings = f(settings),
      myEmail: () => email,
      myName: () => name,
      currencyCode: 'SGD',
      clock: this.clock,
    );
    budgets = BudgetRepository(db, clock: this.clock);
    goals = GoalRepository(db, clock: this.clock);
    bills = BillRepository(db, clock: this.clock);
    suggestions = SuggestionService(
      db,
      budgets: budgets,
      goals: goals,
      bills: bills,
      clock: this.clock,
    );
  }

  final FakeGoogle google;
  final AppDatabase db;
  final String email;
  final String name;

  /// Tests move this to let time pass on this phone.
  DateTime now = DateTime.utc(2026, 10, 23, 12);
  late DateTime Function() clock;
  late SheetsSettings settings;
  late ExpenseRepository expenses;
  late PairingService pairing;
  late SheetsSyncCoordinator sync;
  late BudgetRepository budgets;
  late GoalRepository goals;
  late BillRepository bills;
  late SuggestionService suggestions;

  Future<String> food() async => (await db.select(db.categories).get())
      .firstWhere((c) => c.name == 'Food')
      .id;

  Future<String> addExpense(
    int cents, {
    String note = '',
    DateTime? on,
  }) async => expenses.add(
    amountCents: cents,
    categoryId: await food(),
    spentOn: on ?? DateTime(2026, 10, 20),
    note: note,
    createdBy: 'You',
  );

  Future<List<ExpenseRow>> allExpenses() => db.select(db.expenses).get();

  /// Organiser and member pair up through the real three steps.
  static Future<void> pair(Device organiser, Device member) async {
    final invite = await organiser.pairing.createInvite();
    final code = await member.pairing.joinWithInvite(invite);
    await organiser.pairing.addMember(code);
  }
}
