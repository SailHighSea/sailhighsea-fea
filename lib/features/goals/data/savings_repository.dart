import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../expenses/data/day_format.dart';

String monthKey(DateTime month) =>
    formatDay(DateTime(month.year, month.month)).substring(0, 7);

/// Monthly income and the total held in savings. Both stay on this device (they are private) and
/// are included in the backup file.
class SavingsRepository {
  SavingsRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Stream<List<IncomeRow>> watchIncome() => (_db.select(
    _db.incomeEntries,
  )..orderBy([(i) => OrderingTerm.asc(i.month)])).watch();

  Stream<List<SavingsBalanceRow>> watchBalances() => (_db.select(
    _db.savingsBalances,
  )..orderBy([(b) => OrderingTerm.asc(b.asOn)])).watch();

  /// Income of [cents] from [from]'s month on, until a later month changes it.
  Future<void> setIncome(DateTime from, int cents) => _db
      .into(_db.incomeEntries)
      .insertOnConflictUpdate(
        IncomeEntriesCompanion.insert(
          month: monthKey(from),
          amountCents: cents < 0 ? 0 : cents,
          updatedAt: _clock(),
        ),
      );

  /// The total held in savings on [day] (today by default).
  Future<void> setTotal(int cents, {DateTime? day}) => _db
      .into(_db.savingsBalances)
      .insertOnConflictUpdate(
        SavingsBalancesCompanion.insert(
          asOn: formatDay(day ?? _clock()),
          amountCents: cents < 0 ? 0 : cents,
          updatedAt: _clock(),
        ),
      );
}
