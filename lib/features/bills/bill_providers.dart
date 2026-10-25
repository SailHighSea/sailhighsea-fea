import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/time.dart';
import '../family/member_providers.dart';
import 'data/bill_repository.dart';
import 'domain/bill_calculations.dart';
import 'reminders/reminder_providers.dart';

final billRepositoryProvider = Provider<BillRepository>(
  (ref) => BillRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
    householdId: ref.watch(activeHouseholdIdProvider),
  ),
);

final billRowsProvider = StreamProvider<List<BillRow>>(
  (ref) => ref.watch(billRepositoryProvider).watchAll(),
);

/// Bills that still need paying, soonest first.
final upcomingBillsProvider = Provider<AsyncValue<List<BillView>>>((ref) {
  final rows = ref.watch(billRowsProvider);
  if (rows.hasError) {
    return AsyncError(rows.error!, rows.stackTrace ?? StackTrace.empty);
  }
  if (!rows.hasValue) return const AsyncLoading();
  return AsyncData(
    upcomingBills(rows.requireValue, ref.watch(clockProvider)()),
  );
});

const defaultReminderLeadDays = 3;
const _kRemindersOn = 'bills.remindersOn';
const _kLeadDays = 'bills.reminderLeadDays';

/// "Remind everyone, 3 days before each due date". Stored on this device: every device
/// reminds its own person.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = true,
    this.leadDays = defaultReminderLeadDays,
  });

  final bool enabled;
  final int leadDays;

  ReminderSettings copyWith({bool? enabled, int? leadDays}) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    leadDays: leadDays ?? this.leadDays,
  );
}

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  @override
  ReminderSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return ReminderSettings(
      enabled: prefs.getBool(_kRemindersOn) ?? true,
      leadDays: prefs.getInt(_kLeadDays) ?? defaultReminderLeadDays,
    );
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    await ref.read(sharedPreferencesProvider).setBool(_kRemindersOn, value);
    // Ask for notification permission when reminders are switched on.
    if (value) await ref.read(reminderSchedulerProvider)?.requestPermission();
  }

  Future<void> setLeadDays(int days) {
    state = state.copyWith(leadDays: days);
    return ref.read(sharedPreferencesProvider).setInt(_kLeadDays, days);
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
      ReminderSettingsNotifier.new,
    );
