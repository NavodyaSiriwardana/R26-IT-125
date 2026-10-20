import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/screens/mood_reset_screen.dart';
import 'package:frontend/components/self_bias_identification/services/mood_light_data.dart';
import 'package:frontend/components/self_bias_identification/services/progress_rules.dart';
import 'package:frontend/components/self_bias_identification/widgets/progress_card.dart';

const _bg = Color(0xFF070B12);
const _card = Color(0xFF0D131D);
const _line = Color(0x17FFFFFF);
const _mut = Color(0xFF9AA5B4);
const _dim = Color(0xFF667284);
const _green = Color(0xFF5DCAA5);
const _yellow = Color(0xFFF2B84B);

/// My productivity progress: the student against their own first week, on one
/// scrollable screen. Study time is what the phone verified.
class ProgressScreen extends StatelessWidget {
  final ProgressSummary summary;
  const ProgressScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text('My productivity progress',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: summary.ready ? _ready(context) : _building(),
        ),
      ),
    );
  }

  // ---------------- not enough data yet ----------------

  List<Widget> _building() {
    final study = summary.current.studyPerDay ?? summary.baseline.studyPerDay;
    return [
      _panel(
        key: const Key('progress-building'),
        children: [
          _label('BUILDING YOUR BASELINE'),
          const SizedBox(height: 10),
          Text('Day ${summary.dayCount} of $baselineDays',
              style: GoogleFonts.outfit(
                  fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: summary.dayCount / baselineDays,
              minHeight: 6,
              backgroundColor: const Color(0xFF1A2330),
              valueColor: const AlwaysStoppedAnimation(_green),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'We compare you with your own first week. Keep writing diary '
            'entries and your progress will show from day 8.',
            style: TextStyle(color: Color(0xFFC3CCD8), fontSize: 14, height: 1.5),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _panel(children: [
        _label('SO FAR'),
        _kv('Diary entries', '${summary.entryCount}'),
        _kv('Mood scans', '${summary.scanCount}'),
        if (study != null) _kv('Verified study time', '${formatMinutes(study)} / day'),
      ]),
    ];
  }

  // ---------------- the full screen ----------------

  List<Widget> _ready(BuildContext context) {
    final color = progressColor(summary.level);
    final chip = progressChip(summary.level);
    final delta = progressDeltaText(summary);
    final study = summary.current.studyPerDay;
    final low = summary.level == ProgressLevel.low;
    final points = summary.weeklyStudy.whereType<double>().toList();

    return [
      Container(
        key: const Key('progress-hero'),
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: low ? const Color(0xFF1A1113) : const Color(0xFF0F1B1A),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: _label('VERIFIED STUDY TIME · PER DAY')),
              if (chip != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(chip,
                      style: TextStyle(
                          color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(study == null ? '-' : formatMinutes(study),
                  style: GoogleFonts.outfit(
                      fontSize: 42,
                      fontWeight: FontWeight.w700,
                      color: low ? color : Colors.white)),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('/ day', style: TextStyle(color: _mut, fontSize: 14)),
              ),
            ]),
            if (delta != null) ...[
              const SizedBox(height: 8),
              _pill(delta, color),
            ],
            if (points.length >= 2) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 70,
                width: double.infinity,
                child: CustomPaint(painter: _TrendPainter(points, color)),
              ),
            ],
            const SizedBox(height: 10),
            Text(_heroLine(),
                style: const TextStyle(
                    color: Color(0xFFC3CCD8), fontSize: 13.5, height: 1.5)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _metric('PERCEPTION (PAS)', summary.current.pas,
            summary.baseline.pas, '/100', higherIsBetter: true)),
        const SizedBox(width: 10),
        Expanded(child: _metric('FOCUS', summary.current.switchesPerDay,
            summary.baseline.switchesPerDay, 'switches', higherIsBetter: false)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _metric('SOCIAL MEDIA', summary.current.socialPerDay,
            summary.baseline.socialPerDay, 'min', higherIsBetter: false)),
        const SizedBox(width: 10),
        Expanded(child: _metric(
            'STRESS (SCANS)',
            summary.current.stress == null ? null : summary.current.stress! * 100,
            summary.baseline.stress == null ? null : summary.baseline.stress! * 100,
            '%', higherIsBetter: false)),
      ]),
      const SizedBox(height: 12),
      _panel(key: const Key('progress-weeks'), children: [
        _label('AVERAGE STUDY TIME PER DAY, BY WEEK'),
        const SizedBox(height: 12),
        _weekBars(),
      ]),
      const SizedBox(height: 12),
      _panel(children: [
        _label('WHAT WENT WITH THE CHANGE'),
        _kv('Mood Resets done this week', '${summary.resetsDone}'),
        if (summary.resetDrop != null)
          _kv('Stress change after a reset',
              '${summary.resetDrop! >= 0 ? '−' : '+'}${summary.resetDrop!.abs().round()} pts',
              valueColor: summary.resetDrop! >= 0 ? _green : _yellow),
        if (summary.matchPercent != null)
          _kv('Entries matching your phone', '${summary.matchPercent}%'),
      ]),
      const SizedBox(height: 12),
      _panel(children: [
        _label('ONE THING TO TRY THIS WEEK'),
        const SizedBox(height: 4),
        for (var i = 0; i < _tips().length; i++) _tip(i + 1, _tips()[i]),
      ]),
      const SizedBox(height: 12),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'These changes go together, but exams and a busy week also change how '
          'you study. This is a guide, not proof.',
          style: TextStyle(color: _dim, fontSize: 12, height: 1.5),
        ),
      ),
      const SizedBox(height: 14),
      GestureDetector(
        key: const Key('progress-reset'),
        onTap: () {
          final stress = summary.current.stress ?? 0.5;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MoodResetScreen(
                entryId: '',
                beforeStress: stress,
                beforeMoodLabel:
                    moodLightInfo(moodLightLevel(stress: stress)).label,
                breathing: Map<String, dynamic>.from(defaultBreathing),
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: low ? progressColor(ProgressLevel.low) : _green,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text('Start a 2-min Mood Reset',
                style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF06231A))),
          ),
        ),
      ),
    ];
  }

  String _heroLine() {
    switch (summary.level) {
      case ProgressLevel.up:
        return 'Your verified study time is up since your first week.';
      case ProgressLevel.steady:
        return 'You are close to where you started. A steady week is fine.';
      case ProgressLevel.dip:
        return 'A quieter week happens. You are still close to where you '
            'started.';
      case ProgressLevel.low:
        return 'Your study time fell a lot this week. That can happen with '
            'illness, exams or a hard time. It is worth a look.';
    }
  }

  List<String> _tips() {
    switch (summary.level) {
      case ProgressLevel.low:
        return const [
          'Start with one 20-minute block today. Small and finished is enough.',
          'Try a 2-minute Mood Reset before you begin.',
          'If this has lasted more than 2 weeks, talk to someone you trust or '
              'your university counsellor.',
        ];
      case ProgressLevel.dip:
        return const [
          'Pick one 45-minute block a day and finish it before checking your '
              'phone.',
          'Try a Mood Reset before you start studying.',
        ];
      case ProgressLevel.steady:
      case ProgressLevel.up:
        return const [
          'Keep your best study time of day. Protect it from your phone.',
          'Write the diary entry right after you finish, so it is accurate.',
        ];
    }
  }

  // ---------------- small pieces ----------------

  Widget _metric(String label, double? now, double? before, String unit,
      {required bool higherIsBetter}) {
    final d = (now != null && before != null) ? now - before : null;
    final better = d == null ? null : (higherIsBetter ? d > 0 : d < 0);
    final color = d == null || d.abs() < 0.5
        ? _dim
        : (better == true ? _green : _yellow);
    final arrow = d == null || d.abs() < 0.5 ? '' : (d > 0 ? '▲ ' : '▼ ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(now == null ? '-' : '${now.round()}',
                style: GoogleFonts.outfit(
                    fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(unit, style: const TextStyle(color: _mut, fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 6),
          if (d != null)
            Text('$arrow${d.abs().round()}  ·  was ${before!.round()}',
                style: TextStyle(
                    color: color, fontSize: 11.5, fontWeight: FontWeight.w600))
          else
            const Text('Not enough data',
                style: TextStyle(color: _dim, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _weekBars() {
    final values = summary.weeklyStudy;
    final max = values.whereType<double>().fold<double>(60, (m, v) => v > m ? v : m);
    return Column(children: [
      SizedBox(
        height: 100,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2330),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: values[i] == null
                        ? null
                        : FractionallySizedBox(
                            heightFactor: (values[i]! / max).clamp(0.04, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: i == values.length - 1
                                    ? _green
                                    : const Color(0xFF3B6E60),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Column(children: [
              Text(values[i] == null ? '-' : formatMinutes(values[i]!),
                  style: TextStyle(
                      color: i == values.length - 1 ? _green : _mut,
                      fontSize: 11,
                      fontWeight: i == values.length - 1
                          ? FontWeight.w700
                          : FontWeight.w500)),
              Text('W${i + 1}', style: const TextStyle(color: _dim, fontSize: 10)),
            ]),
          ),
      ]),
    ]);
  }

  Widget _panel({Key? key, required List<Widget> children}) => Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          color: _dim, fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w700));

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(t,
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _kv(String k, String v, {Color? valueColor}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _line))),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(color: Color(0xFFC3CCD8), fontSize: 13.5))),
          Text(v,
              style: TextStyle(
                  color: valueColor ?? Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ]),
      );

  Widget _tip(int n, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: Text('$n',
                style: const TextStyle(
                    color: _green, fontWeight: FontWeight.w800, fontSize: 11)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(t,
                  style: const TextStyle(
                      color: Color(0xFFC3CCD8), fontSize: 13.5, height: 1.4))),
        ]),
      );
}

class _TrendPainter extends CustomPainter {
  final List<double> points;
  final Color color;
  _TrendPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final lo = points.reduce((a, b) => a < b ? a : b);
    final hi = points.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo).abs() < 1 ? 1.0 : hi - lo;
    Offset at(int i) => Offset(
          size.width * i / (points.length - 1),
          size.height - 8 - (points[i] - lo) / span * (size.height - 16),
        );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final a = at(i - 1), b = at(i);
      final mid = (a.dx + b.dx) / 2;
      path.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(points.length - 1), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.color != color;
}
