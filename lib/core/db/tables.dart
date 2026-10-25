import 'package:drift/drift.dart';

/// Tables mirror docs/SPEC.md section 5. Every synced table carries `updated_at`,
/// `deleted_at` (soft delete) and `dirty` (changed locally, not yet pushed).

/// Local-only households (no account yet) use this id until Phase 3 creates real ones.
const localHouseholdId = 'local';

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get householdId =>
      text().withDefault(const Constant(localHouseholdId))();
  TextColumn get name => text()();

  /// Token key (`food`, `bills`, ...) resolved to a colour by the active theme, so
  /// categories stay readable in every mode and in the colour-blind palette.
  TextColumn get color => text()();
  TextColumn get icon => text().nullable()();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExpenseRow')
@TableIndex(name: 'expenses_spent_on', columns: {#spentOn})
@TableIndex(name: 'expenses_category', columns: {#categoryId})
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get householdId =>
      text().withDefault(const Constant(localHouseholdId))();

  /// Integer cents. Never a double (rule 4).
  IntColumn get amountCents => integer()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// Calendar day as `yyyy-MM-dd`, so time zones never shift an expense to another day.
  TextColumn get spentOn => text()();
  TextColumn get createdBy => text().nullable()();
  TextColumn get receiptPath => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// The household this device belongs to. Read-only copy of the server row (the server is the
/// authority for ownership, roles and names), so no `dirty` flag.
@DataClassName('HouseholdRow')
class Households extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get currency => text().withDefault(const Constant('SGD'))();
  TextColumn get ownerId => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Members of a household with their role. Read-only copy of the server rows; the app uses it
/// offline for "who added" names and to decide which buttons to show.
@DataClassName('MemberRow')
class Members extends Table {
  TextColumn get householdId => text()();
  TextColumn get userId => text()();

  /// `owner`, `admin`, `editor` or `viewer`.
  TextColumn get role => text()();
  TextColumn get displayName => text()();
  DateTimeColumn get joinedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {householdId, userId};
}

/// Where sync stopped last time, per household and table. `value` is the newest `updated_at`
/// the server sent, kept as the server's own text so no precision is lost.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// A local change the server refused (for example the person was demoted while offline). The
/// local row is put back to the server's version; this row remembers what was lost so the app
/// can say so clearly.
@DataClassName('SyncIssueRow')
class SyncIssues extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get householdId => text()();

  /// `expenses` or `categories`.
  TextColumn get syncTable => text()();
  TextColumn get rowId => text()();

  /// What the change was, in words ("Lunch, S$12.00").
  TextColumn get summary => text()();
  DateTimeColumn get createdAt => dateTime()();
}
