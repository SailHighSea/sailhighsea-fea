import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// "Now", injectable so tests and goldens are deterministic.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// First day of a month, at midnight.
DateTime monthStart(DateTime date) => DateTime(date.year, date.month);

/// The month shown on Home and the expense list.
class SelectedMonth extends Notifier<DateTime> {
  @override
  DateTime build() => monthStart(ref.read(clockProvider)());

  void previous() => state = DateTime(state.year, state.month - 1);
  void next() => state = DateTime(state.year, state.month + 1);
  void select(DateTime month) => state = monthStart(month);
}

final selectedMonthProvider = NotifierProvider<SelectedMonth, DateTime>(
  SelectedMonth.new,
);

extension DateOnly on DateTime {
  DateTime get dateOnly => DateTime(year, month, day);
}

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// "Today", "Yesterday", or "Oct 21".
String relativeDateLabel(DateTime date, DateTime now) {
  final day = date.dateOnly;
  final today = now.dateOnly;
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('MMM d', 'en_US').format(day);
}
