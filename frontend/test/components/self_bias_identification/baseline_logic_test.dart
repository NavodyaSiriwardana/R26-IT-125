import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/self_bias_identification/services/baseline_data.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';

final _start = DateTime(2026, 10, 1, 9).millisecondsSinceEpoch;

/// One saved analysis, [index] hours after the first.
HistoryEntry _entry(
  int index, {
  num pas = 60,
  num social = 20,
  num switches = 9,
  double? stress,
}) {
  final ms = _start + index * 3600 * 1000;
  return HistoryEntry.fromJson({
    'entry_id': 'ENT_LEADER_$ms',
    'pas_score': pas,
    'primary_bias': {'bias_type': 'focus_mismatch'},
    'comparison': {
      'social_media_minutes': social,
      'app_switches': switches,
      if (stress != null)
        'facial_emotion': {'status': 'success', 'stress_indicator': stress},
    },
  });
}

List<HistoryEntry> _steady(int n, {double stress = 0.08}) => [
      for (var i = 0; i < n; i++)
        _entry(i, pas: 60 + (i % 3), social: 20, switches: 9, stress: stress),
    ];

void main() {
  group('metricValue', () {
    test('reads each measure', () {
      final e = _entry(0, pas: 72, social: 30, switches: 11, stress: 0.25);
      expect(metricValue(e, TrendMetric.pas), 72);
      expect(metricValue(e, TrendMetric.social), 30);
      expect(metricValue(e, TrendMetric.switches), 11);
      expect(metricValue(e, TrendMetric.stress), closeTo(25, 1e-9));
    });

    test('no usable face scan means no stress value', () {
      expect(metricValue(_entry(0), TrendMetric.stress), isNull);
      final skipped = HistoryEntry.fromJson({
        'entry_id': 'ENT_LEADER_$_start',
        'comparison': {'facial_emotion': {'status': 'low_light'}},
      });
      expect(metricValue(skipped, TrendMetric.stress), isNull);
    });
  });

  group('computeBaseline', () {
    test('needs five past entries before it is ready', () {
      expect(computeBaseline(_steady(4)).ready, isFalse);
      expect(computeBaseline(_steady(5)).ready, isTrue);
      expect(computeBaseline(const []).ready, isFalse);
    });

    test('nothing is offered while it is not ready', () {
      final b = computeBaseline(_steady(4));
      expect(b.of(TrendMetric.pas), isNull);
      expect(b.entries, 4);
    });

    test('the average is the mean of the values', () {
      final b = computeBaseline([
        for (var i = 0; i < 5; i++) _entry(i, social: [10, 20, 30, 40, 50][i]),
      ]);
      expect(b.of(TrendMetric.social)!.average, 30);
    });

    test('only the ten most recent entries count', () {
      // 10 old entries at 100, then 10 recent ones at 20.
      final entries = [
        for (var i = 0; i < 10; i++) _entry(i, social: 100),
        for (var i = 10; i < 20; i++) _entry(i, social: 20),
      ];
      final b = computeBaseline(entries);
      expect(b.entries, 10);
      expect(b.of(TrendMetric.social)!.average, 20);
    });

    test('the order they are given in does not matter', () {
      final entries = _steady(8);
      final a = computeBaseline(entries).of(TrendMetric.pas)!;
      final b = computeBaseline(entries.reversed.toList()).of(TrendMetric.pas)!;
      expect(a.average, b.average);
    });

    test('the usual range is never thinner than the minimum', () {
      final b = computeBaseline([
        for (var i = 0; i < 6; i++) _entry(i, social: 20),
      ]);
      final social = b.of(TrendMetric.social)!;
      expect(social.high - social.low, closeTo(6, 1e-9)); // 20 +/- 3
    });

    test('a wide spread gives a wide range', () {
      final b = computeBaseline([
        for (var i = 0; i < 6; i++) _entry(i, social: i.isEven ? 0 : 60),
      ]);
      final social = b.of(TrendMetric.social)!;
      expect(social.high - social.low, greaterThan(30));
    });

    test('percentages stay inside 0 to 100', () {
      final b = computeBaseline([
        for (var i = 0; i < 6; i++) _entry(i, pas: i.isEven ? 100 : 98),
      ]);
      final pas = b.of(TrendMetric.pas)!;
      expect(pas.high, lessThanOrEqualTo(100));
      expect(pas.low, greaterThanOrEqualTo(0));
    });

    test('a rarely measured thing gets no baseline of its own', () {
      // Five entries, but only three have a face scan.
      final entries = [
        for (var i = 0; i < 5; i++)
          _entry(i, stress: i < 3 ? 0.1 : null),
      ];
      final b = computeBaseline(entries);
      expect(b.ready, isTrue);
      expect(b.of(TrendMetric.stress), isNull);
      expect(b.of(TrendMetric.pas), isNotNull);
    });
  });

  group('entriesBefore', () {
    test('keeps only what came earlier, and not the entry itself', () {
      final all = [for (var i = 0; i < 6; i++) _entry(i)];
      final today = all[3];
      final before = entriesBefore(all, today);
      expect(before.length, 3);
      expect(before.any((e) => e.entryId == today.entryId), isFalse);
      expect(before.every((e) => e.time!.isBefore(today.time!)), isTrue);
    });
  });

  group('verdicts', () {
    final base = computeBaseline(_steady(8));

    test('for PAS, above the range is better and below is worse', () {
      final pas = base.of(TrendMetric.pas)!;
      expect(verdictFor(TrendMetric.pas, pas.high + 5, pas), Verdict.better);
      expect(verdictFor(TrendMetric.pas, pas.low - 5, pas), Verdict.worse);
      expect(verdictFor(TrendMetric.pas, pas.average, pas), Verdict.usual);
    });

    test('for stress, social media and switches it is the other way round', () {
      for (final m in [TrendMetric.stress, TrendMetric.social, TrendMetric.switches]) {
        final b = base.of(m)!;
        expect(verdictFor(m, b.high + 5, b), Verdict.worse, reason: '$m');
        expect(verdictFor(m, b.low - 5, b), Verdict.better, reason: '$m');
      }
    });

    test('exactly on the edge of the range is still usual', () {
      final social = base.of(TrendMetric.social)!;
      expect(verdictFor(TrendMetric.social, social.high, social), Verdict.usual);
      expect(verdictFor(TrendMetric.social, social.low, social), Verdict.usual);
    });
  });

  group('compareWithUsual', () {
    final base = computeBaseline(_steady(8));

    test('a heavy social media day reads as a multiple of the usual', () {
      final rows = compareWithUsual(_entry(20, social: 70, stress: 0.08), base);
      final social = rows.firstWhere((r) => r.metric == TrendMetric.social);
      expect(social.verdict, Verdict.worse);
      expect(social.headline, '3.5× your usual');
    });

    test('a stressed day reads in points', () {
      final rows = compareWithUsual(_entry(20, stress: 0.48), base);
      final stress = rows.firstWhere((r) => r.metric == TrendMetric.stress);
      expect(stress.verdict, Verdict.worse);
      expect(stress.headline, '+40 points');
    });

    test('a calm day reads as calmer', () {
      final calmBase = computeBaseline(_steady(8, stress: 0.30));
      final rows = compareWithUsual(_entry(20, stress: 0.02), calmBase);
      final stress = rows.firstWhere((r) => r.metric == TrendMetric.stress);
      expect(stress.verdict, Verdict.better);
      expect(stress.headline, 'calmer than usual');
    });

    test('PAS says how far above or below', () {
      final high = compareWithUsual(_entry(20, pas: 90), base)
          .firstWhere((r) => r.metric == TrendMetric.pas);
      expect(high.verdict, Verdict.better);
      expect(high.headline, endsWith('above usual'));
      final low = compareWithUsual(_entry(20, pas: 20), base)
          .firstWhere((r) => r.metric == TrendMetric.pas);
      expect(low.headline, endsWith('below usual'));
    });

    test('a measure that was not taken today is left out', () {
      final rows = compareWithUsual(_entry(20), base); // no face scan
      expect(rows.any((r) => r.metric == TrendMetric.stress), isFalse);
    });

    test('nothing at all is compared until the baseline is ready', () {
      expect(compareWithUsual(_entry(20), computeBaseline(_steady(3))), isEmpty);
    });
  });

  group('trendSeries', () {
    test('is the last entries, oldest first', () {
      final entries = [for (var i = 0; i < 12; i++) _entry(i, pas: i)];
      final s = trendSeries(entries.reversed.toList(), TrendMetric.pas, count: 7);
      expect(s.map((p) => p.value).toList(), [5, 6, 7, 8, 9, 10, 11]);
    });

    test('skips entries that do not have the measure', () {
      final entries = [
        _entry(0, stress: 0.1),
        _entry(1),
        _entry(2, stress: 0.2),
      ];
      final s = trendSeries(entries, TrendMetric.stress);
      expect(s.length, 2);
    });
  });
}
