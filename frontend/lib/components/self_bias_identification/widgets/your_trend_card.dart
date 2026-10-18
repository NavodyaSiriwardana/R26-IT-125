import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/baseline_data.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';

/// "Your trend" on Weekly Trends: a line over the student's last entries with
/// their usual level drawn as a dashed line and a shaded band. A switch picks
/// PAS, facial stress, social media or app switches. Context only: nothing
/// here changes a score.
class YourTrendCard extends StatefulWidget {
  final List<HistoryEntry> entries;

  /// How many of the latest entries the line shows.
  final int count;

  const YourTrendCard({super.key, required this.entries, this.count = 7});

  @override
  State<YourTrendCard> createState() => _YourTrendCardState();
}

class _YourTrendCardState extends State<YourTrendCard> {
  TrendMetric _metric = TrendMetric.pas;

  static const _surface = Color(0xFF0D131D);
  static const _violet = Color(0xFF8B7BFF);
  static const _green = Color(0xFF35E47B);
  static const _red = Color(0xFFFF6977);

  // What "better" and "worse" are called for each measure.
  static String _betterWord(TrendMetric m) => switch (m) {
        TrendMetric.pas => 'Better',
        TrendMetric.stress => 'Calmer',
        TrendMetric.social => 'Less',
        TrendMetric.switches => 'Fewer',
      };

  static String _worseWord(TrendMetric m) => switch (m) {
        TrendMetric.pas => 'Worse',
        TrendMetric.stress => 'More stressed',
        TrendMetric.social => 'More',
        TrendMetric.switches => 'More',
      };

  static String _betterSummary(TrendMetric m) => switch (m) {
        TrendMetric.pas => 'better than your usual',
        TrendMetric.stress => 'calmer than your usual',
        TrendMetric.social => 'below your usual',
        TrendMetric.switches => 'below your usual',
      };

  static String _worseSummary(TrendMetric m) => switch (m) {
        TrendMetric.pas => 'worse than your usual',
        TrendMetric.stress => 'more stressed than usual',
        TrendMetric.social => 'above your usual',
        TrendMetric.switches => 'above your usual',
      };

  @override
  Widget build(BuildContext context) {
    final baseline = computeBaseline(widget.entries);
    final series = trendSeries(widget.entries, _metric, count: widget.count);
    final band = baseline.of(_metric);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your trend',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in TrendMetric.values) _tab(m),
            ],
          ),
          const SizedBox(height: 14),
          if (series.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  'Not enough ${_metric.tab.toLowerCase()} readings to draw a line yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 190,
              child: CustomPaint(
                key: const Key('trend-chart'),
                painter: _TrendPainter(
                  metric: _metric,
                  values: [for (final p in series) p.value],
                  labels: [for (final p in series) _dayLabel(p.entry.time)],
                  band: band,
                ),
                size: const Size(double.infinity, 190),
              ),
            ),
            const SizedBox(height: 10),
            if (band != null) ..._withBaseline(series, band) else _building(baseline),
          ],
        ],
      ),
    );
  }

  Widget _tab(TrendMetric m) {
    final on = m == _metric;
    return InkWell(
      key: Key('trend-tab-${m.name}'),
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _metric = m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? _violet.withValues(alpha: 0.16) : const Color(0xFF111A27),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: on ? _violet.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.09),
          ),
        ),
        child: Text(
          m.tab,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: on ? _violet : Colors.white.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }

  List<Widget> _withBaseline(
      List<({HistoryEntry entry, double value})> series, MetricBaseline band) {
    var better = 0, worse = 0;
    for (final p in series) {
      final v = verdictFor(_metric, p.value, band);
      if (v == Verdict.better) better++;
      if (v == Verdict.worse) worse++;
    }
    Widget legend(Widget swatch, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch,
            const SizedBox(width: 5),
            Text(text,
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.65))),
          ],
        );
    Widget dot(Color c) => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );
    Widget summary(String big, Color c, String small) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF111A27),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Column(
              children: [
                Text(big,
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.w800, color: c)),
                const SizedBox(height: 2),
                Text(small,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.5))),
              ],
            ),
          ),
        );
    return [
      Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          legend(
            Container(
              width: 16,
              height: 10,
              decoration: BoxDecoration(
                color: _violet.withValues(alpha: 0.18),
                border: Border.all(color: _violet.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            'Your usual range',
          ),
          legend(
            Container(
              width: 16,
              height: 0,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF4F7FB), width: 2)),
              ),
            ),
            'Your average (${band.average.round()}${_metric.unit})',
          ),
          legend(dot(_green), _betterWord(_metric)),
          legend(dot(_red), _worseWord(_metric)),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          summary('$better of ${series.length}', _green, _betterSummary(_metric)),
          const SizedBox(width: 10),
          summary('$worse of ${series.length}', _red, _worseSummary(_metric)),
        ],
      ),
    ];
  }

  Widget _building(PersonalBaseline baseline) {
    final have = baseline.entries.clamp(0, PersonalBaseline.minEntries);
    if (baseline.ready) {
      // Enough entries overall, but too few readings of this one measure.
      return Text(
        'Your usual ${_metric.tab.toLowerCase()} shows after '
        '${PersonalBaseline.minEntries} readings.',
        style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.55)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your usual level appears after ${PersonalBaseline.minEntries} entries. Until '
          'then you can see the line only.',
          style: TextStyle(
              fontSize: 13.5, height: 1.45, color: Colors.white.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 10),
        Text('Building your baseline',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < PersonalBaseline.minEntries; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: i < have ? _violet : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$have of ${PersonalBaseline.minEntries} entries',
                style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
            Text('${PersonalBaseline.minEntries - have} to go',
                style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
          ],
        ),
      ],
    );
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _dayLabel(DateTime? t) {
    if (t == null) return '';
    return dayGroup(t, DateTime.now()) == 'Today' ? 'Today' : _weekdays[t.weekday - 1];
  }
}

class _TrendPainter extends CustomPainter {
  final TrendMetric metric;
  final List<double> values;
  final List<String> labels;
  final MetricBaseline? band;

  const _TrendPainter({
    required this.metric,
    required this.values,
    required this.labels,
    required this.band,
  });

  static const _green = Color(0xFF35E47B);
  static const _red = Color(0xFFFF6977);
  static const _violet = Color(0xFF8B7BFF);

  /// The top of the chart: 100 for percentages, otherwise a little above the
  /// highest value (or the top of the usual range).
  double get top {
    if (metric.ceiling != null) {
      if (metric == TrendMetric.pas) return 100;
      final high = math.max(values.reduce(math.max), band?.high ?? 0);
      return math.max(30, (high * 1.15 / 10).ceil() * 10.0).clamp(30, 100).toDouble();
    }
    final high = math.max(values.reduce(math.max), band?.high ?? 0);
    final step = metric == TrendMetric.switches ? 2.0 : 10.0;
    final floor = metric == TrendMetric.switches ? 6.0 : 30.0;
    return math.max(floor, (high * 1.15 / step).ceil() * step);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0, right = 8.0, topPad = 12.0, bottomPad = 26.0;
    final w = size.width - left - right;
    final h = size.height - topPad - bottomPad;
    final maxV = top;
    double y(double v) => topPad + h - (v / maxV).clamp(0.0, 1.0) * h;
    double x(int i) => left + (values.length == 1 ? w / 2 : w * i / (values.length - 1));

    void text(String s, Offset at,
        {double size = 10, Color color = const Color(0xFF738093), FontWeight weight = FontWeight.w500, bool rightAlign = false, bool center = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = at.dx;
      if (rightAlign) dx -= tp.width;
      if (center) dx -= tp.width / 2;
      tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
    }

    // Grid with the value at each line.
    final grid = Paint()..color = Colors.white.withValues(alpha: 0.07);
    for (final g in [0.0, maxV / 2, maxV]) {
      canvas.drawLine(Offset(left, y(g)), Offset(left + w, y(g)), grid);
      text('${g.round()}${metric == TrendMetric.stress ? '%' : ''}', Offset(left - 6, y(g)),
          rightAlign: true);
    }

    // The usual range and the average.
    final b = band;
    if (b != null) {
      final rect = Rect.fromLTRB(left, y(b.high), left + w, y(b.low));
      canvas.drawRect(rect, Paint()..color = _violet.withValues(alpha: 0.16));
      canvas.drawRect(
        rect,
        Paint()
          ..color = _violet.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final avgPaint = Paint()
        ..color = const Color(0xFFF4F7FB)
        ..strokeWidth = 1.6;
      for (double dx = left; dx < left + w; dx += 9) {
        canvas.drawLine(Offset(dx, y(b.average)), Offset(math.min(dx + 5, left + w), y(b.average)), avgPaint);
      }
      text('usual ${b.average.round()}${metric.unit}', Offset(left + w - 2, y(b.average) - 8),
          size: 10, color: const Color(0xFFF4F7FB), weight: FontWeight.w700, rightAlign: true);
    }

    // The line.
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      i == 0 ? line.moveTo(x(i), y(values[i])) : line.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // The points: green when better than usual, red when worse.
    for (var i = 0; i < values.length; i++) {
      var c = const Color(0xFFA5AFBE);
      if (b != null) {
        final v = verdictFor(metric, values[i], b);
        if (v == Verdict.better) c = _green;
        if (v == Verdict.worse) c = _red;
      }
      canvas.drawCircle(Offset(x(i), y(values[i])), 4.5, Paint()..color = c);
      if (i == values.length - 1) {
        canvas.drawCircle(
          Offset(x(i), y(values[i])),
          9,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    // Day labels, counted back from the latest so the last one is always shown.
    for (var i = 0; i < values.length; i++) {
      if ((values.length - 1 - i) % 2 != 0) continue;
      text(labels[i], Offset(x(i), size.height - 8), center: true);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.metric != metric || old.values != values || old.band != band || old.labels != labels;
}
