import '../models/Diary_entry.dart';

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _weekdayNames = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class DiaryWeekGroup {
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final List<DiaryEntry> entries;

  const DiaryWeekGroup({
    required this.weekStart,
    required this.weekEnd,
    required this.entries,
  });
}

/// Groups entries into Monday-to-Sunday diary weeks.
///
/// Backend-provided week bounds are preferred. If an older entry has no week
/// metadata, its week is derived from [DiaryEntry.entryDate]. Groups and entries
/// are returned newest first so the most recent diary activity stays in reach.
List<DiaryWeekGroup> groupDiaryEntriesByWeek(List<DiaryEntry> entries) {
  final groups = <String, _MutableDiaryWeekGroup>{};

  for (final entry in entries) {
    var start = _parseDate(entry.weekStart);
    var end = _parseDate(entry.weekEnd);
    final entryDate = _parseDate(entry.entryDate);

    if (start == null && entryDate != null) {
      start = entryDate.subtract(Duration(days: entryDate.weekday - 1));
    }
    end ??= start?.add(const Duration(days: 6));

    final key = start == null ? 'undated' : _dateKey(start);
    final group = groups.putIfAbsent(
      key,
      () => _MutableDiaryWeekGroup(weekStart: start, weekEnd: end),
    );
    group.entries.add(entry);
  }

  final result = groups.values.map((group) {
    group.entries.sort(_compareEntriesNewestFirst);
    return DiaryWeekGroup(
      weekStart: group.weekStart,
      weekEnd: group.weekEnd,
      entries: List.unmodifiable(group.entries),
    );
  }).toList();

  result.sort((a, b) {
    if (a.weekStart == null && b.weekStart == null) return 0;
    if (a.weekStart == null) return 1;
    if (b.weekStart == null) return -1;
    return b.weekStart!.compareTo(a.weekStart!);
  });

  return List.unmodifiable(result);
}

String diaryWeekHeading(DiaryWeekGroup group, {DateTime? today}) {
  final start = group.weekStart;
  if (start == null) return 'Earlier entries';

  final currentDate = _dateOnly(today ?? DateTime.now());
  final currentWeekStart = currentDate.subtract(
    Duration(days: currentDate.weekday - 1),
  );

  if (start == currentWeekStart) return 'This week';
  if (start == currentWeekStart.subtract(const Duration(days: 7))) {
    return 'Last week';
  }

  final year = start.year == currentDate.year ? '' : ', ${start.year}';
  return 'Week of ${_monthNames[start.month - 1]} ${start.day}$year';
}

String diaryWeekRange(DiaryWeekGroup group) {
  final start = group.weekStart;
  final end = group.weekEnd;
  if (start == null || end == null) return 'Date not available';

  final startMonth = _monthNames[start.month - 1];
  final endMonth = _monthNames[end.month - 1];

  if (start.year != end.year) {
    return '$startMonth ${start.day}, ${start.year} - '
        '$endMonth ${end.day}, ${end.year}';
  }
  if (start.month != end.month) {
    return '$startMonth ${start.day} - $endMonth ${end.day}, ${end.year}';
  }
  return '$startMonth ${start.day}-${end.day}, ${end.year}';
}

String diaryWeekRangeFromValues(String? weekStart, String? weekEnd) {
  return diaryWeekRange(
    DiaryWeekGroup(
      weekStart: _parseDate(weekStart ?? ''),
      weekEnd: _parseDate(weekEnd ?? ''),
      entries: const [],
    ),
  );
}

String diaryEntryDayName(String entryDate) {
  final date = _parseDate(entryDate);
  return date == null ? 'DAY' : _weekdayNames[date.weekday - 1].toUpperCase();
}

String diaryEntryDayNumber(String entryDate) {
  final date = _parseDate(entryDate);
  return date == null ? '--' : date.day.toString();
}

String diaryEntryFriendlyDate(String entryDate) {
  final date = _parseDate(entryDate);
  if (date == null) return entryDate.isEmpty ? 'Date not available' : entryDate;
  return '${_weekdayNames[date.weekday - 1]}, '
      '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
}

class _MutableDiaryWeekGroup {
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final List<DiaryEntry> entries = [];

  _MutableDiaryWeekGroup({required this.weekStart, required this.weekEnd});
}

int _compareEntriesNewestFirst(DiaryEntry a, DiaryEntry b) {
  final dateComparison = _compareNullableDates(
    _parseDate(b.entryDate),
    _parseDate(a.entryDate),
  );
  if (dateComparison != 0) return dateComparison;

  final timeComparison = _timeInMinutes(
    b.startTime,
  ).compareTo(_timeInMinutes(a.startTime));
  if (timeComparison != 0) return timeComparison;

  final createdComparison = _compareNullableDates(
    DateTime.tryParse(b.createdAt),
    DateTime.tryParse(a.createdAt),
  );
  if (createdComparison != 0) return createdComparison;

  return b.id.toString().compareTo(a.id.toString());
}

int _compareNullableDates(DateTime? left, DateTime? right) {
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return left.compareTo(right);
}

int _timeInMinutes(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
  if (match == null) return -1;

  final hour = int.tryParse(match.group(1)!) ?? -1;
  final minute = int.tryParse(match.group(2)!) ?? -1;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;
  return (hour * 60) + minute;
}

DateTime? _parseDate(String value) {
  final parsed = DateTime.tryParse(value.trim());
  return parsed == null ? null : _dateOnly(parsed);
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}
