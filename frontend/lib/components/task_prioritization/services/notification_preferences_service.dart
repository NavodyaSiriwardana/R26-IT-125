import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class NotificationPreferences {
  final bool notificationsEnabled;
  final int advanceReminderMinutes;
  final bool taskStartNotificationsEnabled;
  final bool snoozeNotificationsEnabled;

  const NotificationPreferences({
    required this.notificationsEnabled,
    required this.advanceReminderMinutes,
    required this.taskStartNotificationsEnabled,
    required this.snoozeNotificationsEnabled,
  });

  static const NotificationPreferences defaults = NotificationPreferences(
    notificationsEnabled: true,
    advanceReminderMinutes: 10,
    taskStartNotificationsEnabled: true,
    snoozeNotificationsEnabled: true,
  );

  NotificationPreferences copyWith({
    bool? notificationsEnabled,
    int? advanceReminderMinutes,
    bool? taskStartNotificationsEnabled,
    bool? snoozeNotificationsEnabled,
  }) {
    return NotificationPreferences(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      advanceReminderMinutes:
          advanceReminderMinutes ?? this.advanceReminderMinutes,
      taskStartNotificationsEnabled:
          taskStartNotificationsEnabled ?? this.taskStartNotificationsEnabled,
      snoozeNotificationsEnabled:
          snoozeNotificationsEnabled ?? this.snoozeNotificationsEnabled,
    );
  }
}

class NotificationPreferencesService {
  NotificationPreferencesService._();

  static final NotificationPreferencesService instance =
      NotificationPreferencesService._();

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  static const String _masterEnabledKey = 'task_notifications_enabled';

  static const String _advanceMinutesKey = 'task_notification_advance_minutes';

  static const String _taskStartEnabledKey = 'task_start_notifications_enabled';

  static const String _snoozeEnabledKey = 'snooze_notifications_enabled';

  static const Set<int> supportedAdvanceMinutes = {5, 10, 15, 30};

  Future<NotificationPreferences> load() async {
    final notificationsEnabled =
        await _preferences.getBool(_masterEnabledKey) ??
        NotificationPreferences.defaults.notificationsEnabled;

    final storedAdvanceMinutes =
        await _preferences.getInt(_advanceMinutesKey) ??
        NotificationPreferences.defaults.advanceReminderMinutes;

    final advanceReminderMinutes =
        supportedAdvanceMinutes.contains(storedAdvanceMinutes)
        ? storedAdvanceMinutes
        : NotificationPreferences.defaults.advanceReminderMinutes;

    final taskStartEnabled =
        await _preferences.getBool(_taskStartEnabledKey) ??
        NotificationPreferences.defaults.taskStartNotificationsEnabled;

    final snoozeEnabled =
        await _preferences.getBool(_snoozeEnabledKey) ??
        NotificationPreferences.defaults.snoozeNotificationsEnabled;

    return NotificationPreferences(
      notificationsEnabled: notificationsEnabled,
      advanceReminderMinutes: advanceReminderMinutes,
      taskStartNotificationsEnabled: taskStartEnabled,
      snoozeNotificationsEnabled: snoozeEnabled,
    );
  }

  Future<void> save(NotificationPreferences preferences) async {
    if (!supportedAdvanceMinutes.contains(preferences.advanceReminderMinutes)) {
      throw ArgumentError.value(
        preferences.advanceReminderMinutes,
        'advanceReminderMinutes',
        'Supported values are 5, 10, 15 and 30.',
      );
    }

    await Future.wait([
      _preferences.setBool(_masterEnabledKey, preferences.notificationsEnabled),
      _preferences.setInt(
        _advanceMinutesKey,
        preferences.advanceReminderMinutes,
      ),
      _preferences.setBool(
        _taskStartEnabledKey,
        preferences.taskStartNotificationsEnabled,
      ),
      _preferences.setBool(
        _snoozeEnabledKey,
        preferences.snoozeNotificationsEnabled,
      ),
    ]);

    debugPrint(
      'Notification preferences saved: '
      'enabled=${preferences.notificationsEnabled}, '
      'advance=${preferences.advanceReminderMinutes}, '
      'start=${preferences.taskStartNotificationsEnabled}, '
      'snooze=${preferences.snoozeNotificationsEnabled}',
    );
  }

  Future<void> restoreDefaults() async {
    await save(NotificationPreferences.defaults);
  }
}
