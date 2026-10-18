import 'package:frontend/components/self_bias_identification/services/entry_time.dart';

/// Pure data helpers for the Bias History and Facial History pages: parsing,
/// grouping by day, filtering, sorting and the reset summaries. No widgets and
/// no network, so every rule here is unit-tested.

enum HistoryFilter { all, accurate, biased, stress, focus, productivity, context }

enum HistorySort { newest, lowestPas, highestPas }

/// One saved analysis (a `bias_results` document).
class HistoryEntry {
  final Map<String, dynamic> raw;
  final String entryId;
  final DateTime? time;
  final int pas;
  final String biasType;
  final String category;
  final int claimedMinutes;
  final Map<String, dynamic>? facial;

  /// A camera scan taken with no diary entry: no PAS and no bias type.
  final bool faceOnly;

  HistoryEntry._({
    required this.faceOnly,
    required this.raw,
    required this.entryId,
    required this.time,
    required this.pas,
    required this.biasType,
    required this.category,
    required this.claimedMinutes,
    required this.facial,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final comparison = json['comparison'] is Map
        ? Map<String, dynamic>.from(json['comparison'] as Map)
        : <String, dynamic>{};
    final face = comparison['facial_emotion'];
    final entryId = json['entry_id']?.toString() ?? '';
    return HistoryEntry._(
      faceOnly: json['kind'] == 'face_only',
      raw: json,
      entryId: entryId,
      time: _timeOf(entryId, json['created_at']),
      pas: (json['pas_score'] as num?)?.toInt() ?? 0,
      biasType: (json['primary_bias'] is Map
              ? (json['primary_bias'] as Map)['bias_type']
              : null)
          ?.toString() ??
          '',
      category: comparison['activity_category']?.toString() ?? '',
      claimedMinutes: (comparison['claimed_duration'] as num?)?.toInt() ?? 0,
      facial: face is Map ? Map<String, dynamic>.from(face) : null,
    );
  }

  bool get isAccurate => biasType == 'accurate_perception';

  bool get hasFace => facial != null && facial!['status'] == 'success';

  double? get stress =>
      hasFace ? (facial!['stress_indicator'] as num?)?.toDouble() : null;

  String get dominantEmotion => facial?['dominant_emotion']?.toString() ?? '';

  /// What the title of the card says, for example "Stress Underestimation".
  String get title => formatBiasType(biasType);

  /// "Self-study · 90 min", or whichever part is known.
  String get subtitle {
    final parts = <String>[
      if (category.isNotEmpty) category,
      if (claimedMinutes > 0) '$claimedMinutes min',
    ];
    return parts.join(' · ');
  }

  static DateTime? _timeOf(String entryId, Object? createdAt) {
    final ms = entryTimestampMs(entryId);
    // Entry ids carry a millisecond timestamp; ignore a number too small to be one.
    if (ms != null && ms > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    if (createdAt is String) return DateTime.tryParse(createdAt)?.toLocal();
    return null;
  }
}

String formatBiasType(String type) {
  if (type.isEmpty) return 'Unknown';
  return type
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

// ---------------------------------------------------------------------------
// Face / stress presentation (same bands as the scan result screen)
// ---------------------------------------------------------------------------

enum StressBand { low, moderate, high }

StressBand stressBand(double stress) {
  if (stress >= 0.5) return StressBand.high;
  if (stress >= 0.3) return StressBand.moderate;
  return StressBand.low;
}

String stressLabel(double stress) {
  switch (stressBand(stress)) {
    case StressBand.high:
      return 'Stressed';
    case StressBand.moderate:
      return 'Uneasy';
    case StressBand.low:
      return 'Calm';
  }
}

String faceEmoji(double stress, String dominantEmotion) {
  switch (stressBand(stress)) {
    case StressBand.high:
      return '😟';
    case StressBand.moderate:
      return '😕';
    case StressBand.low:
      return const ['happy', 'surprise'].contains(dominantEmotion) ? '😊' : '😐';
  }
}

// ---------------------------------------------------------------------------
// Grouping, filtering, sorting
// ---------------------------------------------------------------------------

String dayGroup(DateTime? time, DateTime now) {
  if (time == null) return 'Unknown date';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return 'Earlier this week';
  return 'Earlier';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "9:30 am" for today and yesterday, "Mon" within the week, else "Oct 7".
String shortTime(DateTime? time, DateTime now) {
  if (time == null) return '';
  final group = dayGroup(time, now);
  if (group == 'Today' || group == 'Yesterday') {
    final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m ${time.hour < 12 ? 'am' : 'pm'}';
  }
  if (group == 'Earlier this week') return _weekdays[time.weekday - 1];
  return '${_months[time.month - 1]} ${time.day}';
}

bool _matchesFilter(HistoryEntry e, HistoryFilter filter) {
  switch (filter) {
    case HistoryFilter.all:
      return true;
    case HistoryFilter.accurate:
      return e.isAccurate;
    case HistoryFilter.biased:
      return !e.isAccurate && e.biasType.isNotEmpty;
    case HistoryFilter.stress:
      return e.biasType == 'stress_underestimation';
    case HistoryFilter.focus:
      return e.biasType == 'focus_mismatch';
    case HistoryFilter.productivity:
      return e.biasType == 'productivity_overestimation';
    case HistoryFilter.context:
      return e.biasType == 'context_mismatch';
  }
}

/// Search matches the bias name and the activity category, ignoring case.
List<HistoryEntry> filterEntries(
  List<HistoryEntry> entries, {
  HistoryFilter filter = HistoryFilter.all,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return entries.where((e) {
    if (!_matchesFilter(e, filter)) return false;
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) ||
        e.biasType.toLowerCase().contains(q) ||
        e.category.toLowerCase().contains(q);
  }).toList();
}

/// Always the full totals, so the chips show what else exists.
Map<HistoryFilter, int> filterCounts(List<HistoryEntry> entries) => {
      for (final f in HistoryFilter.values)
        f: entries.where((e) => _matchesFilter(e, f)).length,
    };

List<HistoryEntry> sortEntries(List<HistoryEntry> entries, HistorySort sort) {
  final list = List<HistoryEntry>.of(entries);
  int byTimeDesc(HistoryEntry a, HistoryEntry b) {
    if (a.time == null && b.time == null) return 0;
    if (a.time == null) return 1; // unknown dates last
    if (b.time == null) return -1;
    return b.time!.compareTo(a.time!);
  }

  switch (sort) {
    case HistorySort.newest:
      list.sort(byTimeDesc);
    case HistorySort.lowestPas:
      list.sort((a, b) {
        final c = a.pas.compareTo(b.pas);
        return c != 0 ? c : byTimeDesc(a, b);
      });
    case HistorySort.highestPas:
      list.sort((a, b) {
        final c = b.pas.compareTo(a.pas);
        return c != 0 ? c : byTimeDesc(a, b);
      });
  }
  return list;
}

/// Groups in order of first appearance; call with newest-first entries.
List<MapEntry<String, List<HistoryEntry>>> groupByDay(
  List<HistoryEntry> entries,
  DateTime now,
) {
  final groups = <String, List<HistoryEntry>>{};
  for (final e in entries) {
    groups.putIfAbsent(dayGroup(e.time, now), () => []).add(e);
  }
  return groups.entries.toList();
}

double averagePas(List<HistoryEntry> entries) => entries.isEmpty
    ? 0
    : entries.map((e) => e.pas).reduce((a, b) => a + b) / entries.length;

// ---------------------------------------------------------------------------
// Facial history
// ---------------------------------------------------------------------------

/// null = all time.
bool withinDays(DateTime? time, int? days, DateTime now) {
  if (days == null) return true;
  if (time == null) return false;
  return now.difference(time).inHours < days * 24;
}

/// One saved Mood Reset (a `mood_resets` document).
class ResetRecord {
  final Map<String, dynamic> raw;
  final DateTime? time;
  final String entryId;
  final String condition;
  final double? before;
  final double? after;
  final int? deltaPoints;
  final String outcome;
  final int? selfBefore;
  final int? selfAfter;
  final int durationSeconds;
  final int rounds;

  ResetRecord(this.raw)
      : time = raw['created_at'] is String
            ? DateTime.tryParse(raw['created_at'] as String)?.toLocal()
            : null,
        entryId = raw['entry_id']?.toString() ?? '',
        condition = raw['condition']?.toString() ?? 'breathing',
        before = (raw['before_stress'] as num?)?.toDouble(),
        after = (raw['after_stress'] as num?)?.toDouble(),
        deltaPoints = (raw['delta_points'] as num?)?.toInt(),
        outcome = raw['outcome']?.toString() ?? 'unknown',
        selfBefore = (raw['self_before'] as num?)?.toInt(),
        selfAfter = (raw['self_after'] as num?)?.toInt(),
        durationSeconds = (raw['duration_seconds'] as num?)?.toInt() ?? 0,
        rounds = (raw['rounds_completed'] as num?)?.toInt() ?? 0;

  bool get isQuietRest => condition == 'control';
}

class ResetSummary {
  final int count;

  /// Mean stress points the resets lowered, over the ones that were compared.
  final double? averageDelta;
  final int? breathingCount;
  final double? breathingDelta;
  final int? restCount;
  final double? restDelta;

  const ResetSummary({
    required this.count,
    required this.averageDelta,
    required this.breathingCount,
    required this.breathingDelta,
    required this.restCount,
    required this.restDelta,
  });

  /// The breathing-versus-quiet-rest comparison needs both kinds.
  bool get hasComparison => breathingCount != null && restCount != null;
}

ResetSummary summarizeResets(List<ResetRecord> resets) {
  double? mean(Iterable<ResetRecord> rs) {
    final values = rs.map((r) => r.deltaPoints).whereType<int>().toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  final breathing = resets.where((r) => !r.isQuietRest).toList();
  final rest = resets.where((r) => r.isQuietRest).toList();
  return ResetSummary(
    count: resets.length,
    averageDelta: mean(resets),
    breathingCount: breathing.isEmpty ? null : breathing.length,
    breathingDelta: mean(breathing),
    restCount: rest.isEmpty ? null : rest.length,
    restDelta: mean(rest),
  );
}

/// The newest reset for each entry, to badge the entry cards.
Map<String, ResetRecord> latestResetByEntry(List<ResetRecord> resets) {
  final map = <String, ResetRecord>{};
  for (final r in resets) {
    if (r.entryId.isEmpty) continue;
    final existing = map[r.entryId];
    if (existing == null ||
        (r.time != null &&
            (existing.time == null || r.time!.isAfter(existing.time!)))) {
      map[r.entryId] = r;
    }
  }
  return map;
}

/// "Reset −38 pts" / "Reset +9 pts" / "Reset", for a badge.
String resetBadge(ResetRecord r) {
  final d = r.deltaPoints;
  if (d == null) return 'Reset';
  if (d == 0) return 'Reset ±0 pts';
  return d > 0 ? 'Reset −$d pts' : 'Reset +${d.abs()} pts';
}
