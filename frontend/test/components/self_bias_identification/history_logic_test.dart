import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';

final _now = DateTime(2026, 10, 14, 15, 0); // a Wednesday afternoon

HistoryEntry _entry({
  String? id,
  DateTime? at,
  int pas = 80,
  String bias = 'accurate_perception',
  String category = 'Self-study',
  int minutes = 60,
  Object? facial,
  String? createdAt,
}) {
  final ms = (at ?? _now).millisecondsSinceEpoch;
  return HistoryEntry.fromJson({
    'entry_id': id ?? 'ENT_$ms',
    'pas_score': pas,
    'primary_bias': {'bias_type': bias},
    'comparison': {
      'activity_category': category,
      'claimed_duration': minutes,
      'facial_emotion': ?facial,
    },
    'created_at': ?createdAt,
  });
}

Map<String, dynamic> _face(double stress, [String dominant = 'neutral']) => {
      'status': 'success',
      'stress_indicator': stress,
      'dominant_emotion': dominant,
    };

ResetRecord _reset({
  String entry = 'E1',
  String condition = 'breathing',
  int? delta,
  String? created,
  double? before,
  double? after,
}) =>
    ResetRecord({
      'entry_id': entry,
      'condition': condition,
      'delta_points': delta,
      'before_stress': before,
      'after_stress': after,
      'created_at': created,
    });

void main() {
  group('parsing an entry', () {
    test('takes the time from the entry id', () {
      final e = _entry(at: DateTime(2026, 10, 14, 9, 30));
      expect(e.time, DateTime(2026, 10, 14, 9, 30));
    });

    test('also reads ids mapped from the shared diary', () {
      final ms = DateTime(2026, 10, 13, 8, 0).millisecondsSinceEpoch;
      final e = _entry(id: 'ENT_LEADER_$ms');
      expect(e.time, DateTime(2026, 10, 13, 8, 0));
    });

    test('falls back to created_at when the id has no usable time', () {
      final e = _entry(id: 'ENT_00012', createdAt: '2026-10-10T06:00:00+00:00');
      expect(e.time, isNotNull);
      expect(e.time!.toUtc().hour, 6);
    });

    test('has no time when nothing is usable', () {
      expect(_entry(id: 'weird').time, isNull);
    });

    test('survives missing fields', () {
      final e = HistoryEntry.fromJson({'entry_id': 'ENT_1'});
      expect(e.pas, 0);
      expect(e.biasType, '');
      expect(e.title, 'Unknown');
      expect(e.hasFace, isFalse);
      expect(e.subtitle, '');
    });

    test('subtitle combines category and minutes', () {
      expect(_entry(category: 'Lecture', minutes: 45).subtitle, 'Lecture · 45 min');
      expect(_entry(category: 'Play', minutes: 0).subtitle, 'Play');
    });

    test('a good scan exposes its stress and dominant emotion', () {
      final e = _entry(facial: _face(0.62, 'sad'));
      expect(e.hasFace, isTrue);
      expect(e.stress, 0.62);
      expect(e.dominantEmotion, 'sad');
    });

    test('a failed scan is not a scan', () {
      final e = _entry(facial: {'status': 'no_face_detected'});
      expect(e.hasFace, isFalse);
      expect(e.stress, isNull);
    });

    test('titles read naturally', () {
      expect(formatBiasType('accurate_perception'), 'Accurate Perception');
      expect(formatBiasType('stress_underestimation'), 'Stress Underestimation');
      expect(formatBiasType(''), 'Unknown');
    });
  });

  group('stress presentation', () {
    test('bands match the scan result screen', () {
      expect(stressBand(0.29), StressBand.low);
      expect(stressBand(0.30), StressBand.moderate);
      expect(stressBand(0.49), StressBand.moderate);
      expect(stressBand(0.50), StressBand.high);
    });

    test('labels and faces follow the bands', () {
      expect(stressLabel(0.62), 'Stressed');
      expect(stressLabel(0.35), 'Uneasy');
      expect(stressLabel(0.1), 'Calm');
      expect(faceEmoji(0.62, 'sad'), '😟');
      expect(faceEmoji(0.35, 'sad'), '😕');
      expect(faceEmoji(0.1, 'happy'), '😊');
      expect(faceEmoji(0.1, 'neutral'), '😐');
    });
  });

  group('days and times', () {
    test('groups by calendar day, not by 24-hour windows', () {
      expect(dayGroup(DateTime(2026, 10, 14, 0, 5), _now), 'Today');
      expect(dayGroup(DateTime(2026, 10, 13, 23, 55), _now), 'Yesterday');
      expect(dayGroup(DateTime(2026, 10, 12, 10), _now), 'Earlier this week');
      expect(dayGroup(DateTime(2026, 10, 8, 10), _now), 'Earlier this week');
      expect(dayGroup(DateTime(2026, 10, 7, 10), _now), 'Earlier');
      expect(dayGroup(null, _now), 'Unknown date');
    });

    test('short times', () {
      expect(shortTime(DateTime(2026, 10, 14, 9, 5), _now), '9:05 am');
      expect(shortTime(DateTime(2026, 10, 14, 12, 0), _now), '12:00 pm');
      expect(shortTime(DateTime(2026, 10, 14, 0, 30), _now), '12:30 am');
      expect(shortTime(DateTime(2026, 10, 13, 17, 45), _now), '5:45 pm');
      expect(shortTime(DateTime(2026, 10, 12, 10), _now), 'Mon');
      expect(shortTime(DateTime(2026, 9, 30, 10), _now), 'Sep 30');
      expect(shortTime(null, _now), '');
    });

    test('groupByDay keeps newest-first order and counts', () {
      final list = [
        _entry(at: DateTime(2026, 10, 14, 10)),
        _entry(at: DateTime(2026, 10, 14, 9)),
        _entry(at: DateTime(2026, 10, 13, 9)),
        _entry(at: DateTime(2026, 10, 1, 9)),
      ];
      final groups = groupByDay(list, _now);
      expect(groups.map((g) => g.key), ['Today', 'Yesterday', 'Earlier']);
      expect(groups.map((g) => g.value.length), [2, 1, 1]);
    });

    test('withinDays', () {
      expect(withinDays(DateTime(2026, 10, 10, 15), 7, _now), isTrue);
      expect(withinDays(DateTime(2026, 10, 1, 15), 7, _now), isFalse);
      expect(withinDays(DateTime(2026, 1, 1), null, _now), isTrue);
      expect(withinDays(null, 7, _now), isFalse);
      expect(withinDays(null, null, _now), isTrue);
    });
  });

  group('filtering and search', () {
    final all = [
      _entry(pas: 92, bias: 'accurate_perception', category: 'Self-study'),
      _entry(pas: 89, bias: 'stress_underestimation', category: 'Assignment'),
      _entry(pas: 46, bias: 'productivity_overestimation', category: 'Self-study'),
      _entry(pas: 61, bias: 'focus_mismatch', category: 'Lecture'),
      _entry(pas: 58, bias: 'context_mismatch', category: 'Group work'),
    ];

    test('every filter', () {
      List<int> pas(HistoryFilter f) =>
          filterEntries(all, filter: f).map((e) => e.pas).toList();
      expect(pas(HistoryFilter.all), [92, 89, 46, 61, 58]);
      expect(pas(HistoryFilter.accurate), [92]);
      expect(pas(HistoryFilter.biased), [89, 46, 61, 58]);
      expect(pas(HistoryFilter.stress), [89]);
      expect(pas(HistoryFilter.focus), [61]);
      expect(pas(HistoryFilter.productivity), [46]);
      expect(pas(HistoryFilter.context), [58]);
    });

    test('search matches the bias name or the category, ignoring case', () {
      expect(filterEntries(all, query: 'LECTURE').map((e) => e.pas), [61]);
      expect(filterEntries(all, query: 'stress').map((e) => e.pas), [89]);
      expect(filterEntries(all, query: 'self-study').map((e) => e.pas), [92, 46]);
      expect(filterEntries(all, query: '  focus  ').map((e) => e.pas), [61]);
      expect(filterEntries(all, query: 'nothing like this'), isEmpty);
    });

    test('search and filter combine', () {
      expect(
        filterEntries(all, filter: HistoryFilter.biased, query: 'self-study')
            .map((e) => e.pas),
        [46],
      );
    });

    test('counts always describe the whole list', () {
      final c = filterCounts(all);
      expect(c[HistoryFilter.all], 5);
      expect(c[HistoryFilter.accurate], 1);
      expect(c[HistoryFilter.biased], 4);
      expect(c[HistoryFilter.stress], 1);
    });

    test('an entry with no bias type is neither accurate nor biased', () {
      final blank = [HistoryEntry.fromJson({'entry_id': 'ENT_1'})];
      expect(filterEntries(blank, filter: HistoryFilter.accurate), isEmpty);
      expect(filterEntries(blank, filter: HistoryFilter.biased), isEmpty);
      expect(filterEntries(blank), hasLength(1));
    });
  });

  group('sorting', () {
    test('newest first, unknown dates last', () {
      final list = [
        _entry(pas: 1, at: DateTime(2026, 10, 10)),
        _entry(pas: 2, id: 'weird'),
        _entry(pas: 3, at: DateTime(2026, 10, 14)),
      ];
      expect(sortEntries(list, HistorySort.newest).map((e) => e.pas), [3, 1, 2]);
    });

    test('by PAS, ties broken by newest', () {
      final list = [
        _entry(pas: 50, at: DateTime(2026, 10, 10)),
        _entry(pas: 50, at: DateTime(2026, 10, 14)),
        _entry(pas: 90, at: DateTime(2026, 10, 12)),
      ];
      final low = sortEntries(list, HistorySort.lowestPas);
      expect(low.map((e) => e.pas), [50, 50, 90]);
      expect(low.first.time, DateTime(2026, 10, 14));
      expect(sortEntries(list, HistorySort.highestPas).first.pas, 90);
    });

    test('does not change the list it was given', () {
      final list = [_entry(pas: 9), _entry(pas: 1)];
      sortEntries(list, HistorySort.lowestPas);
      expect(list.first.pas, 9);
    });

    test('average PAS', () {
      expect(averagePas([]), 0);
      expect(averagePas([_entry(pas: 80), _entry(pas: 60)]), 70);
    });
  });

  group('resets', () {
    test('summary averages only the resets that were compared', () {
      final s = summarizeResets([
        _reset(delta: 38),
        _reset(delta: 8, condition: 'control'),
        _reset(delta: null),
      ]);
      expect(s.count, 3);
      expect(s.averageDelta, closeTo(23, 0.001));
      expect(s.breathingCount, 2);
      expect(s.breathingDelta, 38);
      expect(s.restCount, 1);
      expect(s.restDelta, 8);
      expect(s.hasComparison, isTrue);
    });

    test('no comparison without both kinds', () {
      expect(summarizeResets([_reset(delta: 5)]).hasComparison, isFalse);
      expect(summarizeResets([_reset(delta: 5, condition: 'control')]).hasComparison,
          isFalse);
    });

    test('an empty list is safe', () {
      final s = summarizeResets([]);
      expect(s.count, 0);
      expect(s.averageDelta, isNull);
      expect(s.hasComparison, isFalse);
    });

    test('a raised stress shows as a negative average', () {
      expect(summarizeResets([_reset(delta: -9)]).averageDelta, -9);
    });

    test('the newest reset wins for an entry', () {
      final map = latestResetByEntry([
        _reset(entry: 'E1', delta: 5, created: '2026-10-10T08:00:00+00:00'),
        _reset(entry: 'E1', delta: 38, created: '2026-10-11T08:00:00+00:00'),
        _reset(entry: 'E2', delta: 1, created: '2026-10-09T08:00:00+00:00'),
        _reset(entry: '', delta: 99),
      ]);
      expect(map.keys.toSet(), {'E1', 'E2'});
      expect(map['E1']!.deltaPoints, 38);
    });

    test('badges', () {
      expect(resetBadge(_reset(delta: 38)), 'Reset −38 pts');
      expect(resetBadge(_reset(delta: -9)), 'Reset +9 pts');
      expect(resetBadge(_reset(delta: 0)), 'Reset ±0 pts');
      expect(resetBadge(_reset(delta: null)), 'Reset');
    });

    test('a reset knows its kind and defaults to breathing', () {
      expect(_reset(condition: 'control').isQuietRest, isTrue);
      expect(ResetRecord({}).condition, 'breathing');
      expect(ResetRecord({}).isQuietRest, isFalse);
    });
  });
}
