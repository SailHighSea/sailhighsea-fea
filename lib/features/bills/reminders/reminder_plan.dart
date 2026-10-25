import '../../../core/time.dart';
import '../domain/bill_calculations.dart';

/// Hour of the day (local time) a reminder is sent.
const reminderHour = 9;

/// One reminder: when to send it (or now), and what it says.
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.key,
    required this.title,
    required this.body,
    required this.when,
  });

  /// Stable notification id for this bill and due date (same bill, same date, same id).
  final int id;

  /// `billId|dueDate|leadDays`: remembers a reminder was handled so it is not repeated.
  final String key;
  final String title;
  final String body;

  /// When to show it. `null` means right now (the reminder window already started).
  final DateTime? when;

  bool get immediate => when == null;
}

/// FNV-1a, folded to a positive 31-bit number (notification ids are 32-bit ints).
int stableId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

String reminderKey(BillView bill, int leadDays) =>
    '${bill.bill.id}|${bill.bill.nextDueOn}|$leadDays';

String _whenText(int daysUntil) {
  if (daysUntil < 0) {
    return daysUntil == -1
        ? 'is 1 day overdue'
        : 'is ${-daysUntil} days overdue';
  }
  if (daysUntil == 0) return 'is due today';
  if (daysUntil == 1) return 'is due tomorrow';
  return 'is due in $daysUntil days';
}

/// Which reminders to schedule. For each bill still to pay:
/// * [leadDays] before the due date at 09:00, if that time is still ahead, schedule it;
/// * otherwise the reminder window has started: show it now, unless that reminder was
///   already handled ([handled]), so it is not repeated every time the app opens.
/// A changed due date or lead time makes a new key, so it is planned again.
List<ReminderPlan> planReminders({
  required List<BillView> bills,
  required DateTime now,
  required int leadDays,
  required Set<String> handled,
  required String Function(int cents) money,
}) {
  final plans = <ReminderPlan>[];
  for (final bill in bills) {
    if (bill.settled) continue;
    final key = reminderKey(bill, leadDays);
    final due = bill.dueOn;
    final at = DateTime(due.year, due.month, due.day - leadDays, reminderHour);
    final title = 'Bill coming up: ${bill.bill.name}';
    if (at.isAfter(now)) {
      plans.add(
        ReminderPlan(
          id: stableId(key),
          key: key,
          title: title,
          body:
              '${bill.bill.name} (${money(bill.amountCents)}) ${_whenText(leadDays)}.',
          when: at,
        ),
      );
    } else if (!handled.contains(key)) {
      plans.add(
        ReminderPlan(
          id: stableId(key),
          key: key,
          title: title,
          body:
              '${bill.bill.name} (${money(bill.amountCents)}) ${_whenText(bill.daysUntil)}.',
          when: null,
        ),
      );
    }
  }
  return plans;
}

/// The day a reminder for [bill] first appears, for tests and labels.
DateTime reminderDay(BillView bill, int leadDays) => DateTime(
  bill.dueOn.year,
  bill.dueOn.month,
  bill.dueOn.day - leadDays,
).dateOnly;
