import 'package:frontend/components/self_bias_identification/services/history_data.dart';

// Pure rules for the critical alert: what counts as critical, and when the
// phone may be told about it. No widgets and no network, so it is unit-tested.
//
// Critical means one of:
//   repeat_bias   the same bias in the last 3 diary entries in a row
//   low_pas       the newest diary entry scored a PAS below 30
//   stress_trend  stress was high on each of the last 3 days with a scan
// Nothing else raises an alert.

enum AlertKind { repeatBias, lowPas, stressTrend }

class CriticalAlert {
  final AlertKind kind;

  /// The same pattern with the same newest entry gives the same id, so a
  /// dismissed alert stays dismissed until something new happens.
  final String id;
  final String title;
  final String body;

  /// The notification text. Calm wording, never a diagnosis.
  final String notificationTitle;
  final String notificationBody;
  final List<HistoryEntry> entries;
  final List<String> steps;

  const CriticalAlert({
    required this.kind,
    required this.id,
    required this.title,
    required this.body,
    required this.notificationTitle,
    required this.notificationBody,
    required this.entries,
    required this.steps,
  });

  bool get isStress => kind == AlertKind.stressTrend;
}

const criticalPas = 30;
const stressTrendLevel = 0.4;

/// The alerts that are open right now, most important first. [history] is the
/// student's entries in any order.
List<CriticalAlert> evaluateAlerts(List<HistoryEntry> history, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final diary = history.where((e) => !e.faceOnly && e.time != null).toList()
    ..sort((a, b) => b.time!.compareTo(a.time!));
  final out = <CriticalAlert>[];

  if (diary.length >= 3) {
    final last3 = diary.take(3).toList();
    final type = last3.first.biasType;
    if (type.isNotEmpty &&
        type != 'accurate_perception' &&
        last3.every((e) => e.biasType == type)) {
      out.add(CriticalAlert(
        kind: AlertKind.repeatBias,
        id: 'repeat_bias:$type:${last3.first.entryId}',
        title: 'Same bias, 3 times',
        body: 'The same bias appeared in your last 3 entries: '
            '${formatBiasType(type)}.',
        notificationTitle: 'Something needs your attention',
        notificationBody: 'The same bias showed up in your last 3 diary '
            'entries. Tap to see what it means.',
        entries: last3,
        steps: const [
          'Plan a shorter study block (45 min) and finish it.',
          'Check your phone use right after each block.',
        ],
      ));
    }
  }

  if (diary.isNotEmpty && diary.first.pas < criticalPas) {
    final e = diary.first;
    out.add(CriticalAlert(
      kind: AlertKind.lowPas,
      id: 'low_pas:${e.entryId}',
      title: 'Your latest entry is far from the evidence',
      body: 'Your newest entry scored ${e.pas} out of 100 for how close it '
          'was to what your phone showed.',
      notificationTitle: 'Something needs your attention',
      notificationBody: 'Your latest diary entry was far from what your '
          'phone showed. Tap to see why.',
      entries: [e],
      steps: const [
        'Open the entry and read what differed.',
        'Next time, note the start and end time as you finish.',
      ],
    ));
  }

  final stress = _stressTrend(history, today);
  if (stress != null) out.add(stress);
  return out;
}

CriticalAlert? _stressTrend(List<HistoryEntry> history, DateTime today) {
  final byDay = <DateTime, List<HistoryEntry>>{};
  for (final e in history) {
    final s = e.stress;
    if (s == null || e.time == null) continue;
    final d = DateTime(e.time!.year, e.time!.month, e.time!.day);
    byDay.putIfAbsent(d, () => []).add(e);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  if (days.length < 3) return null;
  final recent = days.take(3).toList();
  final limit = DateTime(today.year, today.month, today.day)
      .subtract(const Duration(days: 4));
  if (recent.first.isBefore(limit)) return null;
  final picked = <HistoryEntry>[];
  for (final d in recent) {
    final list = byDay[d]!;
    final avg = list.map((e) => e.stress!).reduce((a, b) => a + b) / list.length;
    if (avg < stressTrendLevel) return null;
    list.sort((a, b) => b.time!.compareTo(a.time!));
    picked.add(list.first);
  }
  return CriticalAlert(
    kind: AlertKind.stressTrend,
    id: 'stress_trend:${picked.first.entryId}',
    title: 'A quick check-in',
    body: 'Your scans have shown higher stress on each of the last 3 days.',
    notificationTitle: 'A quick check-in',
    notificationBody: 'Your stress has been higher for 3 days. A 2-minute '
        'reset might help.',
    entries: picked,
    steps: const [
      'Try the 2-minute Mood Reset.',
      'Take a short walk and drink some water.',
      'If this keeps going, talk to someone you trust or your university '
          'counsellor.',
    ],
  );
}

/// A time of day as minutes after midnight.
class DayRange {
  final int startMinute;
  final int endMinute;
  const DayRange(this.startMinute, this.endMinute);

  /// True when [minute] falls inside. A range such as 22:00 to 07:00 crosses
  /// midnight.
  bool contains(int minute) => startMinute <= endMinute
      ? minute >= startMinute && minute < endMinute
      : minute >= startMinute || minute < endMinute;
}

class AlertSettings {
  final bool alertsOn;
  final bool quietHoursOn;
  final DayRange quietHours;
  final bool lectureModeOn;
  final List<DayRange> lectureBlocks;

  const AlertSettings({
    this.alertsOn = true,
    this.quietHoursOn = true,
    this.quietHours = const DayRange(22 * 60, 7 * 60),
    this.lectureModeOn = false,
    this.lectureBlocks = const [
      DayRange(8 * 60 + 30, 12 * 60 + 30),
      DayRange(13 * 60 + 30, 16 * 60 + 30),
    ],
  });

  AlertSettings copyWith({
    bool? alertsOn,
    bool? quietHoursOn,
    DayRange? quietHours,
    bool? lectureModeOn,
    List<DayRange>? lectureBlocks,
  }) =>
      AlertSettings(
        alertsOn: alertsOn ?? this.alertsOn,
        quietHoursOn: quietHoursOn ?? this.quietHoursOn,
        quietHours: quietHours ?? this.quietHours,
        lectureModeOn: lectureModeOn ?? this.lectureModeOn,
        lectureBlocks: lectureBlocks ?? this.lectureBlocks,
      );

  /// The end of the lecture block that [now] is inside, or null.
  DateTime? lectureEnd(DateTime now) {
    if (!lectureModeOn || now.weekday > DateTime.friday) return null;
    final m = now.hour * 60 + now.minute;
    for (final b in lectureBlocks) {
      if (b.contains(m)) {
        final base = DateTime(now.year, now.month, now.day);
        return base.add(Duration(minutes: b.endMinute));
      }
    }
    return null;
  }

  bool inQuietHours(DateTime now) =>
      quietHoursOn && quietHours.contains(now.hour * 60 + now.minute);
}

/// Whether the phone may be told about [alert] now: alerts on, not already
/// dismissed, nothing sent yet today, and not in quiet hours or a lecture.
/// A held alert is simply sent by the next check after class ends.
bool shouldNotify({
  required CriticalAlert alert,
  required AlertSettings settings,
  required Set<String> dismissed,
  required Set<String> notified,
  required DateTime? lastNotifiedAt,
  required DateTime now,
}) {
  if (!settings.alertsOn) return false;
  if (dismissed.contains(alert.id) || notified.contains(alert.id)) return false;
  if (lastNotifiedAt != null &&
      lastNotifiedAt.year == now.year &&
      lastNotifiedAt.month == now.month &&
      lastNotifiedAt.day == now.day) {
    return false;
  }
  if (settings.inQuietHours(now)) return false;
  if (settings.lectureEnd(now) != null) return false;
  return true;
}
