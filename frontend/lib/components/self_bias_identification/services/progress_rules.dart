import 'package:frontend/components/self_bias_identification/services/history_data.dart';

// Pure rules for "My productivity progress": the student against their own
// first week. Study time here is the verified study time (what the phone
// showed), not what the student claimed. No widgets and no network.

const baselineDays = 7;
const lowStudyMinutes = 45.0;

enum ProgressLevel { up, steady, dip, low }

class WindowStats {
  final int entries;
  final int activeDays;

  /// Verified study minutes, social media minutes and app switches, averaged
  /// over the days that have an entry.
  final double? studyPerDay;
  final double? socialPerDay;
  final double? switchesPerDay;
  final double? pas;

  /// Mean stress (0 to 1) of the camera scans in the window.
  final double? stress;

  const WindowStats({
    required this.entries,
    required this.activeDays,
    this.studyPerDay,
    this.socialPerDay,
    this.switchesPerDay,
    this.pas,
    this.stress,
  });
}

class ProgressSummary {
  /// True when there are 7 days of history and entries in both weeks.
  final bool ready;

  /// How far through the first week the student is (1 to 7).
  final int dayCount;
  final int entryCount;
  final int scanCount;
  final WindowStats baseline;
  final WindowStats current;
  final ProgressLevel level;

  /// Average verified study minutes per day for the last 4 weeks, oldest
  /// first. A week with no entry is null.
  final List<double?> weeklyStudy;
  final int resetsDone;

  /// Mean stress points lowered by the resets in this week, when compared.
  final double? resetDrop;

  /// Share of this week's entries that matched the phone (PAS 70 or more).
  final int? matchPercent;

  const ProgressSummary({
    required this.ready,
    required this.dayCount,
    required this.entryCount,
    required this.scanCount,
    required this.baseline,
    required this.current,
    required this.level,
    required this.weeklyStudy,
    required this.resetsDone,
    required this.resetDrop,
    required this.matchPercent,
  });

  bool get hasAnyEntry => entryCount > 0;

  /// Minutes per day against the first week (positive means more).
  double? get studyDelta {
    final a = current.studyPerDay, b = baseline.studyPerDay;
    return a == null || b == null ? null : a - b;
  }
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

double _num(Object? v) => v is num ? v.toDouble() : 0;

WindowStats _stats(
  List<HistoryEntry> diary,
  List<HistoryEntry> withFace,
  DateTime from,
  DateTime to,
) {
  bool inside(HistoryEntry e) =>
      e.time != null && !e.time!.isBefore(from) && e.time!.isBefore(to);
  final rows = diary.where(inside).toList();
  final days = <DateTime, List<HistoryEntry>>{};
  for (final e in rows) {
    days.putIfAbsent(_day(e.time!), () => []).add(e);
  }
  double? perDay(double Function(HistoryEntry) f) {
    if (days.isEmpty) return null;
    final sums = days.values
        .map((list) => list.fold<double>(0, (s, e) => s + f(e)))
        .toList();
    return sums.reduce((a, b) => a + b) / sums.length;
  }

  Map<String, dynamic> cmp(HistoryEntry e) => e.raw['comparison'] is Map
      ? Map<String, dynamic>.from(e.raw['comparison'] as Map)
      : <String, dynamic>{};

  final stresses =
      withFace.where(inside).map((e) => e.stress).whereType<double>().toList();
  return WindowStats(
    entries: rows.length,
    activeDays: days.length,
    studyPerDay: perDay((e) => _num(cmp(e)['verified_educational'])),
    socialPerDay: perDay((e) => _num(cmp(e)['social_media_minutes'])),
    switchesPerDay: perDay((e) => _num(cmp(e)['app_switches'])),
    pas: rows.isEmpty
        ? null
        : rows.map((e) => e.pas).reduce((a, b) => a + b) / rows.length,
    stress: stresses.isEmpty
        ? null
        : stresses.reduce((a, b) => a + b) / stresses.length,
  );
}

ProgressSummary computeProgress(
  List<HistoryEntry> history,
  List<ResetRecord> resets, {
  DateTime? now,
}) {
  final today = _day(now ?? DateTime.now());
  final tomorrow = today.add(const Duration(days: 1));
  final diary = history.where((e) => !e.faceOnly && e.time != null).toList();
  final faces = history.where((e) => e.time != null).toList();

  const empty = WindowStats(entries: 0, activeDays: 0);
  if (diary.isEmpty) {
    return ProgressSummary(
      ready: false,
      dayCount: 0,
      entryCount: 0,
      scanCount: faces.where((e) => e.stress != null).length,
      baseline: empty,
      current: empty,
      level: ProgressLevel.steady,
      weeklyStudy: const [null, null, null, null],
      resetsDone: 0,
      resetDrop: null,
      matchPercent: null,
    );
  }

  final first = _day(
      diary.map((e) => e.time!).reduce((a, b) => a.isBefore(b) ? a : b));
  final spanDays = today.difference(first).inDays;
  final baseEnd = first.add(const Duration(days: baselineDays));
  final base = _stats(diary, faces, first, baseEnd);

  var curFrom = today.subtract(const Duration(days: 6));
  if (curFrom.isBefore(baseEnd)) curFrom = baseEnd;
  final cur = _stats(diary, faces, curFrom, tomorrow);

  final ready = spanDays >= baselineDays && base.entries > 0 && cur.entries > 0;

  var level = ProgressLevel.steady;
  final cs = cur.studyPerDay, bs = base.studyPerDay;
  if (ready && cs != null) {
    if (cs < lowStudyMinutes || (bs != null && bs > 0 && cs <= bs * 0.6)) {
      level = ProgressLevel.low;
    } else if (bs != null && cs <= bs - 10) {
      level = ProgressLevel.dip;
    } else if (bs != null && cs >= bs + 10) {
      level = ProgressLevel.up;
    }
  }

  final weekly = <double?>[];
  for (var i = 3; i >= 0; i--) {
    final to = tomorrow.subtract(Duration(days: 7 * i));
    final from = to.subtract(const Duration(days: 7));
    weekly.add(_stats(diary, faces, from, to).studyPerDay);
  }

  final weekResets = resets
      .where((r) =>
          r.time != null && !r.time!.isBefore(curFrom) && r.time!.isBefore(tomorrow))
      .toList();
  final deltas = weekResets.map((r) => r.deltaPoints).whereType<int>().toList();

  final weekDiary = diary
      .where((e) => !e.time!.isBefore(curFrom) && e.time!.isBefore(tomorrow))
      .toList();

  return ProgressSummary(
    ready: ready,
    dayCount: (spanDays + 1).clamp(1, baselineDays),
    entryCount: diary.length,
    scanCount: faces.where((e) => e.stress != null).length,
    baseline: base,
    current: cur,
    level: level,
    weeklyStudy: weekly,
    resetsDone: weekResets.length,
    resetDrop: deltas.isEmpty
        ? null
        : deltas.reduce((a, b) => a + b) / deltas.length,
    matchPercent: weekDiary.isEmpty
        ? null
        : (100 * weekDiary.where((e) => e.pas >= 70).length / weekDiary.length)
            .round(),
  );
}

/// "2h 05m", "28m".
String formatMinutes(double minutes) {
  final m = minutes.round();
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}
