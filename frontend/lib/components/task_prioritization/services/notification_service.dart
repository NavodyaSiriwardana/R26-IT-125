import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'notification_preferences_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'intelligent_diary_task_reminders';

  static const String channelName = 'Task reminders';

  static const String channelDescription =
      'Reminders for scheduled tasks and snoozed tasks';

  bool _initialized = false;

  final StreamController<String> _notificationTapController =
      StreamController<String>.broadcast();

  String? _launchPayload;

  Stream<String> get notificationTapStream => _notificationTapController.stream;

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload?.trim();

    if (payload == null || payload.isEmpty) {
      return;
    }

    debugPrint('Notification selected: $payload');

    _notificationTapController.add(payload);
  }

  String? takeLaunchPayload() {
    final payload = _launchPayload;

    // Consume it only once.
    _launchPayload = null;

    return payload;
  }

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();

    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();

      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

      debugPrint('Notification timezone: ${timezoneInfo.identifier}');
    } catch (error) {
      tz.setLocalLocation(tz.getLocation('Asia/Colombo'));

      debugPrint(
        'Could not detect timezone. '
        'Using Asia/Colombo: $error',
      );
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload?.trim();

      if (payload != null && payload.isNotEmpty) {
        _launchPayload = payload;

        debugPrint('Application launched from notification: $payload');
      }
    }

    _initialized = true;

    debugPrint('Local notification service initialized.');
  }

  // -------------------------------------------------------------------------
  // Permissions
  // -------------------------------------------------------------------------

  Future<void> requestPermissions() async {
    await initialize();

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      final notificationPermission = await androidPlugin
          .requestNotificationsPermission();

      debugPrint(
        'Android notification permission: '
        '$notificationPermission',
      );

      final exactAlarmPermission = await androidPlugin
          .requestExactAlarmsPermission();

      debugPrint(
        'Android exact-alarm permission: '
        '$exactAlarmPermission',
      );
    }

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    if (iosPlugin != null) {
      final permission = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint('iOS notification permission: $permission');
    }
  }

  // -------------------------------------------------------------------------
  // Shared notification appearance
  // -------------------------------------------------------------------------

  NotificationDetails get _notificationDetails {
    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  // -------------------------------------------------------------------------
  // Deterministic notification IDs
  // -------------------------------------------------------------------------

  /// Generates the same notification ID for the same task, part and type.
  ///
  /// We do not use Dart's hashCode because it should not be relied on as a
  /// persistent identifier between different application executions.
  int _stableNotificationId(String value) {
    int hash = 0x811C9DC5;

    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }

    // Notification ID zero is valid, but avoiding it makes debugging clearer.
    return hash == 0 ? 1 : hash;
  }

  String? _readTaskId(Map<String, dynamic> task) {
    final value = task['_doc_id'] ?? task['id'] ?? task['task_id'];

    final taskId = value?.toString().trim();

    if (taskId == null || taskId.isEmpty) {
      return null;
    }

    return taskId;
  }

  DateTime? _readLocalDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    final parsed = DateTime.tryParse(value.toString());

    if (parsed == null) {
      return null;
    }

    return parsed.isUtc ? parsed.toLocal() : parsed;
  }

  // -------------------------------------------------------------------------
  // Individual scheduled notification
  // -------------------------------------------------------------------------

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    final localScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);

    if (!localScheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
      debugPrint(
        'Skipped past notification: '
        '$title at $localScheduledDate',
      );

      return;
    }

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: localScheduledDate,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (error) {
      // If exact alarms are unavailable, still provide a reminder using
      // Android's inexact scheduling mode.
      debugPrint(
        'Exact notification scheduling failed. '
        'Trying inexact scheduling: $error',
      );

      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: localScheduledDate,
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Cancel task notifications
  // -------------------------------------------------------------------------

  Future<void> cancelTaskNotifications(String taskId) async {
    await initialize();

    final pendingRequests = await _plugin.pendingNotificationRequests();

    final payloadPrefix = 'task:$taskId|';

    for (final request in pendingRequests) {
      if (request.payload?.startsWith(payloadPrefix) ?? false) {
        await _plugin.cancel(id: request.id);

        debugPrint('Cancelled task notification: ${request.id}');
      }
    }
  }

  Future<int> cancelAllTaskNotifications() async {
    await initialize();

    final pendingRequests = await _plugin.pendingNotificationRequests();

    int cancelledCount = 0;

    for (final request in pendingRequests) {
      if (request.payload?.startsWith('task:') ?? false) {
        await _plugin.cancel(id: request.id);

        cancelledCount++;
      }
    }

    debugPrint(
      'Cancelled $cancelledCount '
      'task notifications.',
    );

    return cancelledCount;
  }

  Future<bool> scheduleSnoozeReminder({
    required String taskId,
    required String taskTitle,
    required DateTime snoozedUntil,
  }) async {
    await initialize();

    /*
   * Always cancel existing reminders first, even if snooze
   * notifications have been disabled.
   */
    await cancelTaskNotifications(taskId);

    final preferences = await NotificationPreferencesService.instance.load();

    if (!preferences.notificationsEnabled) {
      debugPrint(
        'Snooze reminder skipped because '
        'notifications are disabled.',
      );

      return false;
    }

    if (!preferences.snoozeNotificationsEnabled) {
      debugPrint(
        'Snooze reminder skipped because '
        'snooze reminders are disabled.',
      );

      return false;
    }

    final localSnoozeTime = snoozedUntil.isUtc
        ? snoozedUntil.toLocal()
        : snoozedUntil;

    if (!localSnoozeTime.isAfter(DateTime.now())) {
      debugPrint(
        'Snooze reminder skipped because the '
        'snooze time has already passed.',
      );

      return false;
    }

    final notificationId = _stableNotificationId('$taskId|snooze');

    await _scheduleNotification(
      id: notificationId,
      title: 'Snooze finished',
      body: '“$taskTitle” is ready for your attention again.',
      scheduledDate: localSnoozeTime,
      payload: 'task:$taskId|type:snooze',
    );

    debugPrint(
      'Snooze reminder scheduled for '
      '$taskTitle at $localSnoozeTime.',
    );

    return true;
  }

  // -------------------------------------------------------------------------
  // Schedule all notifications for an accepted daily plan
  // -------------------------------------------------------------------------

  Future<int> schedulePlanNotifications(Map<String, dynamic> plan) async {
    await initialize();

    final preferences = await NotificationPreferencesService.instance.load();

    final scheduledTasks = List<Map<String, dynamic>>.from(
      (plan['scheduled_tasks'] as List?)?.map(
            (item) => Map<String, dynamic>.from(item as Map),
          ) ??
          const [],
    );

    final unscheduledTasks = List<Map<String, dynamic>>.from(
      (plan['unscheduled_tasks'] as List?)?.map(
            (item) => Map<String, dynamic>.from(item as Map),
          ) ??
          const [],
    );

    /*
     * Cancel previous reminders for every task participating in this plan.
     *
     * This is important when:
     * - a plan is regenerated;
     * - a task's scheduled time changes;
     * - a previously scheduled task becomes unscheduled.
     */
    final affectedTaskIds = <String>{};

    for (final task in [...scheduledTasks, ...unscheduledTasks]) {
      final taskId = _readTaskId(task);

      if (taskId != null) {
        affectedTaskIds.add(taskId);
      }
    }

    for (final taskId in affectedTaskIds) {
      await cancelTaskNotifications(taskId);
    }

    if (!preferences.notificationsEnabled) {
      debugPrint(
        'Plan notifications skipped because '
        'notifications are disabled.',
      );

      return 0;
    }

    int scheduledNotificationCount = 0;

    for (int index = 0; index < scheduledTasks.length; index++) {
      final task = scheduledTasks[index];

      final taskId = _readTaskId(task);

      if (taskId == null) {
        debugPrint('Notification skipped because the task ID is missing.');

        continue;
      }

      final taskTitle = task['title']?.toString().trim();

      if (taskTitle == null || taskTitle.isEmpty) {
        debugPrint('Notification skipped because the task title is missing.');

        continue;
      }

      final scheduledStart = _readLocalDateTime(task['scheduled_start']);

      if (scheduledStart == null) {
        debugPrint(
          'Notification skipped because scheduled_start '
          'is missing or invalid for $taskTitle.',
        );

        continue;
      }

      final partNumber = (task['part_number'] as num?)?.toInt() ?? index + 1;

      final beforeId = _stableNotificationId('$taskId|$partNumber|before');

      final startId = _stableNotificationId('$taskId|$partNumber|start');

      final advanceMinutes = preferences.advanceReminderMinutes;

      final beforeTime = scheduledStart.subtract(
        Duration(minutes: advanceMinutes),
      );

      final beforePayload = 'task:$taskId|part:$partNumber|type:before';

      final startPayload = 'task:$taskId|part:$partNumber|type:start';

      if (beforeTime.isAfter(DateTime.now())) {
        await _scheduleNotification(
          id: beforeId,
          title: 'Task starts in $advanceMinutes minutes',
          body: 'Get ready for “$taskTitle”.',
          scheduledDate: beforeTime,
          payload: beforePayload,
        );

        scheduledNotificationCount++;
      }

      if (preferences.taskStartNotificationsEnabled &&
          scheduledStart.isAfter(DateTime.now())) {
        await _scheduleNotification(
          id: startId,
          title: 'It is time to begin',
          body: 'Your planned task “$taskTitle” starts now.',
          scheduledDate: scheduledStart,
          payload: startPayload,
        );

        scheduledNotificationCount++;
      }
    }

    debugPrint(
      'Scheduled $scheduledNotificationCount '
      'daily-plan notifications.',
    );

    return scheduledNotificationCount;
  }

  // -------------------------------------------------------------------------
  // Debugging
  // -------------------------------------------------------------------------

  Future<void> printPendingNotifications() async {
    await initialize();

    final requests = await _plugin.pendingNotificationRequests();

    debugPrint('Pending notification count: ${requests.length}');

    for (final request in requests) {
      debugPrint(
        'Pending notification: '
        'id=${request.id}, '
        'title=${request.title}, '
        'payload=${request.payload}',
      );
    }
  }

  // Keep temporarily available for future diagnostics.
  Future<void> showTestNotification() async {
    await initialize();

    await _plugin.show(
      id: 900001,
      title: 'Notifications are ready',
      body: 'Intelligent Diary can now send task reminders.',
      notificationDetails: _notificationDetails,
      payload: 'notification_test',
    );
  }
}
