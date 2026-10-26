import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/app_info.dart';
import 'reminder_plan.dart';

/// Shows and schedules the bill reminders. Hardware-specific, so it sits behind an interface
/// (rule 1 allows platform code for notifications only).
abstract class ReminderScheduler {
  /// Asks the person for permission to show notifications. Returns whether it is granted.
  Future<bool> requestPermission();

  /// Replaces everything: cancels what was scheduled before, schedules the plans that have a
  /// time, and shows the immediate ones. Returns the keys it took care of.
  Future<Set<String>> apply(List<ReminderPlan> plans);

  Future<void> cancelAll();

  void dispose();
}

/// Uses `flutter_local_notifications`. Android, iOS and macOS schedule with the system, so
/// reminders arrive with the app closed. Linux (and Windows toasts, which only work well for
/// packaged apps) cannot, so while the app is running a timer shows reminders when they fall
/// due.
class LocalNotificationsScheduler implements ReminderScheduler {
  LocalNotificationsScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  Timer? _timer;
  List<ReminderPlan> _waiting = const [];

  static bool get _systemSchedules =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'bill_reminders',
      'Bill reminders',
      channelDescription: 'Reminds you before a bill is due',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
  );

  Future<bool> _init() async {
    if (_ready) return true;
    tzdata.initializeTimeZones();
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: kAppName,
            appUserModelId: 'app.familyexpenses.FamilyExpenses',
            guid: '6f3b2a54-7d7e-4c55-9d52-3d5c4f9a0b11',
          ),
        ),
      );
      _ready = ok ?? true;
    } on Object {
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (Platform.isMacOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  @override
  Future<Set<String>> apply(List<ReminderPlan> plans) async {
    if (!await _init()) return const {};
    await _plugin.cancelAll();
    _timer?.cancel();
    final handled = <String>{};
    final timed = <ReminderPlan>[];
    for (final plan in plans) {
      if (plan.immediate) {
        await _show(plan);
        handled.add(plan.key);
      } else if (_systemSchedules) {
        await _plugin.zonedSchedule(
          id: plan.id,
          title: plan.title,
          body: plan.body,
          scheduledDate: tz.TZDateTime.from(plan.when!, tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        handled.add(plan.key);
      } else {
        timed.add(plan);
      }
    }
    _waiting = timed;
    if (timed.isNotEmpty) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _fireDue());
    }
    return handled;
  }

  Future<void> _show(ReminderPlan plan) => _plugin.show(
    id: plan.id,
    title: plan.title,
    body: plan.body,
    notificationDetails: _details,
  );

  Future<void> _fireDue() async {
    final now = DateTime.now();
    final due = _waiting.where((p) => !p.when!.isAfter(now)).toList();
    if (due.isEmpty) return;
    _waiting = _waiting.where((p) => p.when!.isAfter(now)).toList();
    for (final plan in due) {
      await _show(plan);
    }
  }

  @override
  Future<void> cancelAll() async {
    _timer?.cancel();
    _waiting = const [];
    if (_ready) await _plugin.cancelAll();
  }

  @override
  void dispose() => _timer?.cancel();
}
