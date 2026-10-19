import 'dart:math' as math;

import 'package:frontend/components/self_bias_identification/services/history_data.dart';

/// A student's personal baseline: what is usual for them, worked out from their
/// own past analysed entries. Plain averages, nothing is trained, and nothing
/// here changes a score or a bias type. It only adds context.
///
/// Pure functions, no widgets and no network, so every rule is unit-tested.

enum TrendMetric { pas, stress, social, switches }

extension TrendMetricInfo on TrendMetric {
  String get label {
    switch (this) {
      case TrendMetric.pas:
        return 'Alignment (PAS)';
      case TrendMetric.stress:
        return 'Facial stress';
      case TrendMetric.social:
        return 'Social media';
      case TrendMetric.switches:
        return 'App switches';
    }
  }

  /// The short name used on the chart's tabs.
  String get tab {
    switch (this) {
      case TrendMetric.pas:
        return 'PAS';
      case TrendMetric.stress:
        return 'Facial stress';
      case TrendMetric.social:
        return 'Social media';
      case TrendMetric.switches:
        return 'App switches';
    }
  }

  /// For PAS a higher number is better. For stress, social media and app
  /// switches a higher number is worse.
  bool get higherIsBetter => this == TrendMetric.pas;

  String get unit {
    switch (this) {
      case TrendMetric.stress:
        return '%';
      case TrendMetric.social:
        return ' min';
      case TrendMetric.pas:
      case TrendMetric.switches:
        return '';
    }
  }

  /// The "usual range" is never narrower than this on either side of the
  /// average, so a steady student does not get a band thinner than a line.
  double get minHalfWidth {
    switch (this) {
      case TrendMetric.pas:
        return 5;
      case TrendMetric.stress:
        return 3;
      case TrendMetric.social:
        return 3;
      case TrendMetric.switches:
        return 1;
    }
  }

  /// Scores and stress are percentages; the other two have no fixed top.
  double? get ceiling =>
      (this == TrendMetric.pas || this == TrendMetric.stress) ? 100 : null;
}

/// This entry's value for [metric], or null when it was not measured (for
/// example no usable face scan, so no stress).
double? metricValue(HistoryEntry e, TrendMetric metric) {
  final comparison = e.raw['comparison'];
  switch (metric) {
    case TrendMetric.pas:
      final v = e.raw['pas_score'];
      return v is num ? v.toDouble() : null;
    case TrendMetric.stress:
      final s = e.stress;
      return s == null ? null : s * 100;
    case TrendMetric.social:
      final v = comparison is Map ? comparison['social_media_minutes'] : null;
      return v is num ? v.toDouble() : null;
    case TrendMetric.switches:
      final v = comparison is Map ? comparison['app_switches'] : null;
      return v is num ? v.toDouble() : null;
  }
}

class MetricBaseline {
  final double average;
  final double low;
  final double high;

  /// How many entries the average is made from.
  final int count;

  const MetricBaseline({
    required this.average,
    required this.low,
    required this.high,
    required this.count,
  });
}

class PersonalBaseline {
  /// How many past entries are needed before anything is compared.
  static const minEntries = 5;

  /// Only the most recent entries count, so the baseline follows the student.
  static const window = 10;

  /// How many past entries were looked at (up to [window]).
  final int entries;
  final Map<TrendMetric, MetricBaseline> metrics;

  const PersonalBaseline({required this.entries, required this.metrics});

  /// Enough history to say what is usual.
  bool get ready => entries >= minEntries;

  MetricBaseline? of(TrendMetric metric) => ready ? metrics[metric] : null;
}

int _byTimeDesc(HistoryEntry a, HistoryEntry b) {
  if (a.time == null && b.time == null) return 0;
  if (a.time == null) return 1; // unknown dates last
  if (b.time == null) return -1;
  return b.time!.compareTo(a.time!);
}

/// The student's usual levels, from their [window] most recent entries in
/// [past]. A measure needs [PersonalBaseline.minEntries] values of its own, so one that
/// was rarely measured (like stress, when scans are skipped) gets no baseline.
PersonalBaseline computeBaseline(List<HistoryEntry> past) {
  final recent = (List<HistoryEntry>.of(past)..sort(_byTimeDesc))
      .take(PersonalBaseline.window)
      .toList();
  final metrics = <TrendMetric, MetricBaseline>{};
  for (final m in TrendMetric.values) {
    final values = recent.map((e) => metricValue(e, m)).whereType<double>().toList();
    if (values.length < PersonalBaseline.minEntries) continue;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
    final half = math.max(math.sqrt(variance), m.minHalfWidth);
    final ceiling = m.ceiling;
    metrics[m] = MetricBaseline(
      average: mean,
      low: math.max(mean - half, 0),
      high: ceiling == null ? mean + half : math.min(mean + half, ceiling),
      count: values.length,
    );
  }
  return PersonalBaseline(entries: recent.length, metrics: metrics);
}

/// The entries that came before [today], so a result is always compared with
/// what the student had done up to then (also when it is opened later).
List<HistoryEntry> entriesBefore(List<HistoryEntry> all, HistoryEntry today) {
  return all.where((e) {
    if (e.entryId.isNotEmpty && e.entryId == today.entryId) return false;
    if (today.time == null || e.time == null) return true;
    return e.time!.isBefore(today.time!);
  }).toList();
}

enum Verdict { better, worse, usual }

Verdict verdictFor(TrendMetric metric, double value, MetricBaseline b) {
  if (value > b.high) return metric.higherIsBetter ? Verdict.better : Verdict.worse;
  if (value < b.low) return metric.higherIsBetter ? Verdict.worse : Verdict.better;
  return Verdict.usual;
}

class UsualComparison {
  final TrendMetric metric;
  final double today;
  final MetricBaseline usual;
  final Verdict verdict;

  /// The short phrase beside the bar, for example "3.5× your usual".
  final String headline;

  const UsualComparison({
    required this.metric,
    required this.today,
    required this.usual,
    required this.verdict,
    required this.headline,
  });
}

String _headline(TrendMetric m, double today, MetricBaseline b, Verdict v) {
  if (v == Verdict.usual) return 'about your usual';
  switch (m) {
    case TrendMetric.pas:
      final d = (today - b.average).round().abs();
      return v == Verdict.better ? '$d above usual' : '$d below usual';
    case TrendMetric.stress:
      final d = (today - b.average).round().abs();
      return v == Verdict.better ? 'calmer than usual' : '+$d points';
    case TrendMetric.social:
      if (v == Verdict.better) return 'below your usual';
      if (b.average >= 1 && today / b.average >= 1.5) {
        return '${(today / b.average).toStringAsFixed(1)}× your usual';
      }
      return 'a little higher';
    case TrendMetric.switches:
      if (v == Verdict.better) return 'below your usual';
      return today > b.average * 1.5 ? 'higher than usual' : 'a little higher';
  }
}

/// One row per measure that this entry has and that has a baseline.
List<UsualComparison> compareWithUsual(HistoryEntry today, PersonalBaseline baseline) {
  final rows = <UsualComparison>[];
  for (final m in TrendMetric.values) {
    final b = baseline.of(m);
    final value = metricValue(today, m);
    if (b == null || value == null) continue;
    final verdict = verdictFor(m, value, b);
    rows.add(UsualComparison(
      metric: m,
      today: value,
      usual: b,
      verdict: verdict,
      headline: _headline(m, value, b, verdict),
    ));
  }
  return rows;
}

/// The last [count] entries that have a value for [metric], oldest first, for
/// the trend chart.
List<({HistoryEntry entry, double value})> trendSeries(
  List<HistoryEntry> entries,
  TrendMetric metric, {
  int count = 7,
}) {
  final sorted = List<HistoryEntry>.of(entries)..sort(_byTimeDesc);
  final points = <({HistoryEntry entry, double value})>[];
  for (final e in sorted) {
    final v = metricValue(e, metric);
    if (v == null) continue;
    points.add((entry: e, value: v));
    if (points.length == count) break;
  }
  return points.reversed.toList();
}
