import 'package:frontend/components/self_bias_identification/services/history_data.dart';

/// Pure data for the 4 week mood heatmap on the facial scan screen: one cell
/// per day, coloured by that day's facial stress. No widgets, no network.

class HeatCell {
  final DateTime date;
  final bool isToday;
  final bool isFuture;

  /// How many face scans were taken that day.
  final int scans;

  /// Mean facial stress (0..1) of that day's scans, null when none.
  final double? stress;
  final String dominantEmotion;

  const HeatCell({
    required this.date,
    required this.isToday,
    required this.isFuture,
    required this.scans,
    required this.stress,
    required this.dominantEmotion,
  });

  bool get hasScan => scans > 0 && stress != null;

  StressBand? get band => hasScan ? stressBand(stress!) : null;
}

class MoodHeatmap {
  /// Monday first, [weeks] x 7, the last row holds today.
  final List<HeatCell> cells;
  final int scans;
  final int streak;
  final double? averageStress;

  const MoodHeatmap({
    required this.cells,
    required this.scans,
    required this.streak,
    required this.averageStress,
  });

  bool get isEmpty => scans == 0;
}

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

MoodHeatmap buildMoodHeatmap(
  List<HistoryEntry> entries,
  DateTime now, {
  int weeks = 4,
}) {
  final today = _dayOf(now);
  // Monday of this week, then back to the first week shown.
  final thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final start = thisMonday.subtract(Duration(days: (weeks - 1) * 7));

  // Per day: the face readings of that day, oldest to newest.
  final byDay = <DateTime, List<HistoryEntry>>{};
  for (final e in entries) {
    if (!e.hasFace || e.time == null) continue;
    byDay.putIfAbsent(_dayOf(e.time!), () => []).add(e);
  }
  for (final list in byDay.values) {
    list.sort((a, b) => a.time!.compareTo(b.time!));
  }

  final cells = <HeatCell>[];
  for (var i = 0; i < weeks * 7; i++) {
    final date = DateTime(start.year, start.month, start.day + i);
    final list = byDay[date] ?? const <HistoryEntry>[];
    final stresses = list.map((e) => e.stress).whereType<double>().toList();
    cells.add(HeatCell(
      date: date,
      isToday: date == today,
      isFuture: date.isAfter(today),
      scans: list.length,
      stress: stresses.isEmpty
          ? null
          : stresses.reduce((a, b) => a + b) / stresses.length,
      dominantEmotion: list.isEmpty ? '' : list.last.dominantEmotion,
    ));
  }

  final scanned = cells.where((c) => c.hasScan).toList();
  final totalScans = scanned.fold<int>(0, (sum, c) => sum + c.scans);
  final average = scanned.isEmpty
      ? null
      : scanned.map((c) => c.stress!).reduce((a, b) => a + b) / scanned.length;

  // Days in a row with a scan. A missing scan today does not break the run
  // yet: the day is not over.
  var streak = 0;
  final todayIndex = cells.indexWhere((c) => c.isToday);
  var i = todayIndex;
  if (i >= 0 && !cells[i].hasScan) i--;
  while (i >= 0 && cells[i].hasScan) {
    streak++;
    i--;
  }

  return MoodHeatmap(
    cells: cells,
    scans: totalScans,
    streak: streak,
    averageStress: average,
  );
}

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Wed 15 Oct", with " (today)" for today.
String heatDayLabel(HeatCell cell) {
  final d = cell.date;
  final base =
      '${_weekdayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]}';
  return cell.isToday ? '$base (today)' : base;
}

/// The reason line for a tapped day, e.g. "Stress 17% · Neutral face".
String heatReason(HeatCell cell) {
  if (!cell.hasScan) return 'No scan this day.';
  final pct = (cell.stress! * 100).round();
  final emotion = cell.dominantEmotion.isEmpty
      ? ''
      : ' · ${cell.dominantEmotion[0].toUpperCase()}${cell.dominantEmotion.substring(1)} face';
  final many = cell.scans > 1 ? ' (average of ${cell.scans} scans)' : '';
  return 'Stress $pct%$emotion$many';
}
