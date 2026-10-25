import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money_provider.dart';
import '../../../core/theme/appearance_provider.dart';
import '../../../core/time.dart';
import '../bill_providers.dart';
import 'reminder_plan.dart';
import 'reminder_scheduler.dart';

/// `null` where notifications are not available (tests, web). `main()` sets the real one.
final reminderSchedulerProvider = Provider<ReminderScheduler?>((ref) => null);

const _kHandled = 'bills.remindersHandled';

/// Keeps the scheduled reminders in step with the bills and the Remind everyone switch. It
/// is read once from the app root so it stays alive; every change of bills or settings
/// re-plans. Reminders already handled are remembered so they are never repeated.
final reminderSyncProvider = Provider<void>((ref) {
  final scheduler = ref.watch(reminderSchedulerProvider);
  if (scheduler == null) return;
  final settings = ref.watch(reminderSettingsProvider);
  final bills = ref.watch(upcomingBillsProvider).value;
  if (bills == null) return;
  final prefs = ref.watch(sharedPreferencesProvider);
  final money = ref.watch(moneyFormatterProvider);
  final now = ref.watch(clockProvider)();

  if (!settings.enabled) {
    unawaited(scheduler.cancelAll());
    unawaited(prefs.remove(_kHandled));
    return;
  }
  final handled = (prefs.getStringList(_kHandled) ?? const <String>[]).toSet();
  final plans = planReminders(
    bills: bills,
    now: now,
    leadDays: settings.leadDays,
    handled: handled,
    money: money.format,
  );
  unawaited(() async {
    final done = await scheduler.apply(plans);
    // Keep only keys that still matter (current bills) plus what was just handled.
    final current = {for (final b in bills) reminderKey(b, settings.leadDays)};
    final next = {...handled.where(current.contains), ...done};
    await prefs.setStringList(_kHandled, next.toList());
  }());
});
