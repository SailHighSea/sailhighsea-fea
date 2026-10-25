import '../../../core/db/app_database.dart';
import '../../../core/time.dart';
import '../../expenses/data/day_format.dart';

enum BillRepeat {
  monthly('monthly', 'Every month'),
  weekly('weekly', 'Every week'),
  yearly('yearly', 'Every year'),
  once('once', 'Once');

  const BillRepeat(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static BillRepeat fromDb(String value) => values.firstWhere(
    (r) => r.dbValue == value,
    orElse: () => BillRepeat.monthly,
  );
}

/// The date a repeating bill is due after [due], or `null` for a bill that is paid once.
/// Monthly and yearly bills keep to [dueDay] and snap back after short months
/// (due on the 31st: Jan 31, Feb 28, Mar 31).
DateTime? addPeriod(DateTime due, BillRepeat repeat, int dueDay) {
  switch (repeat) {
    case BillRepeat.once:
      return null;
    case BillRepeat.weekly:
      return DateTime(due.year, due.month, due.day + 7);
    case BillRepeat.monthly:
      return _clamped(due.year, due.month + 1, dueDay);
    case BillRepeat.yearly:
      return _clamped(due.year + 1, due.month, dueDay);
  }
}

DateTime _clamped(int year, int month, int day) {
  final firstOfMonth = DateTime(year, month);
  final last = daysInMonth(firstOfMonth);
  return DateTime(
    firstOfMonth.year,
    firstOfMonth.month,
    day > last ? last : day,
  );
}

class BillView {
  const BillView({
    required this.bill,
    required this.dueOn,
    required this.today,
  });

  final BillRow bill;
  final DateTime dueOn;
  final DateTime today;

  BillRepeat get repeat => BillRepeat.fromDb(bill.repeat);
  int get amountCents => bill.amountCents;

  /// Negative when overdue.
  int get daysUntil => dueOn.difference(today).inDays;
  bool get overdue => daysUntil < 0;

  /// A one-off bill that has been paid: nothing more to do.
  bool get settled => repeat == BillRepeat.once && bill.lastPaidOn != null;

  /// Due within [days] days (or already overdue): shown in amber.
  bool isSoon([int days = 5]) => !settled && daysUntil <= days;

  String get dueLabel {
    final d = daysUntil;
    if (d < 0) return d == -1 ? 'Overdue by 1 day' : 'Overdue by ${-d} days';
    if (d == 0) return 'Due today';
    if (d == 1) return 'Due tomorrow';
    return 'Due in $d days';
  }
}

/// Bills that still need paying, soonest first.
List<BillView> upcomingBills(List<BillRow> bills, DateTime now) {
  final today = now.dateOnly;
  final views =
      [
        for (final b in bills)
          if (b.deletedAt == null)
            BillView(bill: b, dueOn: parseDay(b.nextDueOn), today: today),
      ].where((v) => !v.settled).toList()..sort((a, b) {
        final byDate = a.dueOn.compareTo(b.dueOn);
        return byDate != 0 ? byDate : a.bill.name.compareTo(b.bill.name);
      });
  return views;
}

int totalDue(List<BillView> bills) =>
    bills.fold(0, (sum, b) => sum + b.amountCents);

/// "15 Nov": the last due date among [bills].
DateTime? dueBy(List<BillView> bills) => bills.isEmpty
    ? null
    : bills.map((b) => b.dueOn).reduce((a, b) => a.isAfter(b) ? a : b);

/// What "Mark paid" writes: the day it was paid and the next due date.
class PaidResult {
  const PaidResult({required this.lastPaidOn, required this.nextDueOn});
  final DateTime lastPaidOn;
  final DateTime nextDueOn;
}

PaidResult markPaidResult(BillRow bill, DateTime now) {
  final due = parseDay(bill.nextDueOn);
  final next = addPeriod(due, BillRepeat.fromDb(bill.repeat), bill.dueDay);
  return PaidResult(lastPaidOn: now.dateOnly, nextDueOn: next ?? due);
}

String shortMonth(DateTime d) => const [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
][d.month - 1];

String dayMonthLabel(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

String billDayText(DateTime d) => formatDay(d);
