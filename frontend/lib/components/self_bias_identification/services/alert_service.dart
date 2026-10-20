import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/alert_rules.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';

/// Keeps the alert settings and what was already shown or dismissed, on this
/// phone and per student, and sends the one notification a day.
///
/// The check runs when the app opens or the Home screen refreshes, and after a
/// new entry. The phone is told through a local notification, so it needs no
/// server push. (A notification while the app is fully closed would need a
/// server push, which this does not do.)
class AlertService {
  static const channelId = 'truthlens_critical_alerts';
  static const _payload = 'truthlens_critical_alert';

  static String get _user => AppState.userId;
  static String get _settingsKey => 'alert_settings_$_user';
  static String get _dismissedKey => 'alerts_dismissed_$_user';
  static String get _notifiedKey => 'alerts_notified_$_user';
  static String get _lastKey => 'alert_last_notified_$_user';

  /// Tests replace this so nothing touches the platform.
  static Future<void> Function(String title, String body) show = _show;

  /// Tests replace this to supply a history without a server.
  static Future<List<HistoryEntry>> Function(String userId) loadHistory =
      _loadHistory;

  static Future<List<HistoryEntry>> _loadHistory(String userId) async {
    final rows = await ApiService.fetchHistory(userId);
    final faces = <Map<String, dynamic>>[];
    try {
      faces.addAll(await ApiService.fetchFaceChecks(userId));
    } catch (_) {}
    return [...rows, ...faces].map(HistoryEntry.fromJson).toList();
  }

  // ---------------- settings ----------------

  static Map<String, dynamic> _rangeJson(DayRange r) =>
      {'s': r.startMinute, 'e': r.endMinute};
  static DayRange _range(Object? j, DayRange fallback) => j is Map
      ? DayRange((j['s'] as num).toInt(), (j['e'] as num).toInt())
      : fallback;

  static Future<AlertSettings> loadSettings() async {
    const d = AlertSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_settingsKey);
      if (raw == null) return d;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final blocks = (j['blocks'] as List?)
              ?.map((b) => _range(b, const DayRange(0, 0)))
              .toList() ??
          d.lectureBlocks;
      return AlertSettings(
        alertsOn: j['alertsOn'] as bool? ?? d.alertsOn,
        quietHoursOn: j['quietOn'] as bool? ?? d.quietHoursOn,
        quietHours: _range(j['quiet'], d.quietHours),
        lectureModeOn: j['lectureOn'] as bool? ?? d.lectureModeOn,
        lectureBlocks: blocks,
      );
    } catch (_) {
      return d;
    }
  }

  static Future<void> saveSettings(AlertSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _settingsKey,
      jsonEncode({
        'alertsOn': s.alertsOn,
        'quietOn': s.quietHoursOn,
        'quiet': _rangeJson(s.quietHours),
        'lectureOn': s.lectureModeOn,
        'blocks': s.lectureBlocks.map(_rangeJson).toList(),
      }),
    );
  }

  // ---------------- state ----------------

  static Future<Set<String>> dismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_dismissedKey) ?? const []).toSet();
  }

  /// "Got it": this alert stays closed until a new pattern appears.
  static Future<void> dismiss(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_dismissedKey) ?? <String>[]).toSet()
      ..add(id);
    await prefs.setStringList(_dismissedKey, set.toList());
  }

  // ---------------- check ----------------

  /// The alerts that are open now. Sends at most one notification a day, and
  /// not during quiet hours or a lecture.
  static Future<List<CriticalAlert>> check({DateTime? now}) async {
    final time = now ?? DateTime.now();
    if (_user.isEmpty) return const [];
    try {
      final history = await loadHistory(_user);
      final dismissed = await dismissedIds();
      final open = evaluateAlerts(history, now: time)
          .where((a) => !dismissed.contains(a.id))
          .toList();
      if (open.isEmpty) return open;

      final settings = await loadSettings();
      final prefs = await SharedPreferences.getInstance();
      final notified = (prefs.getStringList(_notifiedKey) ?? const []).toSet();
      final lastMs = prefs.getInt(_lastKey);
      final last =
          lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs);

      final first = open.first;
      if (shouldNotify(
        alert: first,
        settings: settings,
        dismissed: dismissed,
        notified: notified,
        lastNotifiedAt: last,
        now: time,
      )) {
        await show(first.notificationTitle, first.notificationBody);
        await prefs.setStringList(_notifiedKey, (notified..add(first.id)).toList());
        await prefs.setInt(_lastKey, time.millisecondsSinceEpoch);
      }
      return open;
    } catch (e) {
      debugPrint('Alert check failed: $e');
      return const [];
    }
  }

  static Future<void> _show(String title, String body) async {
    final plugin = FlutterLocalNotificationsPlugin();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Critical alerts',
        channelDescription: 'A critical bias or a stress trend. At most one a day.',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    await plugin.show(
      id: 7301,
      title: title,
      body: body,
      notificationDetails: details,
      payload: _payload,
    );
  }
}
