import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/baseline_data.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';

/// "Compared with your usual": how this result sits against the student's own
/// average, so a heavy phone user and a light one are each judged fairly. It
/// adds context only. It never changes the score or the bias type.
///
/// Shown on the result page. Compares with the entries made BEFORE this one,
/// so an old result opened later still shows what was usual at the time.
class ComparedWithUsual extends StatefulWidget {
  final Map<String, dynamic> result;

  /// Loads the student's saved entries. Replaced in tests.
  final Future<List<HistoryEntry>> Function()? loader;

  const ComparedWithUsual({super.key, required this.result, this.loader});

  @override
  State<ComparedWithUsual> createState() => _ComparedWithUsualState();
}

class _ComparedWithUsualState extends State<ComparedWithUsual> {
  PersonalBaseline? _baseline;
  List<UsualComparison> _rows = const [];
  int _pastCount = 0;
  bool _failed = false;

  static const _surface = Color(0xFF0D131D);
  static const _violet = Color(0xFF8B7BFF);
  static const _orange = Color(0xFFF4B653);
  static const _green = Color(0xFF35E47B);
  static const _red = Color(0xFFFF6977);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<HistoryEntry>> _defaultLoader() async =>
      (await ApiService.fetchHistory(AppState.userId))
          .map(HistoryEntry.fromJson)
          .toList();

  Future<void> _load() async {
    try {
      final all = await (widget.loader ?? _defaultLoader)();
      final today = HistoryEntry.fromJson(widget.result);
      final past = entriesBefore(all, today);
      final baseline = computeBaseline(past);
      if (!mounted) return;
      setState(() {
        _baseline = baseline;
        _pastCount = past.length;
        _rows = compareWithUsual(today, baseline);
      });
    } catch (_) {
      // The comparison is a bonus. Without it the page is just as before.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseline = _baseline;
    if (_failed || baseline == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: baseline.ready ? _ready(baseline) : _building(),
    );
  }

  Widget _header(String chip, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'COMPARED WITH YOUR USUAL',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            chip,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }

  Widget _building() {
    final have = _pastCount.clamp(0, PersonalBaseline.minEntries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Not yet', _orange),
        const SizedBox(height: 8),
        Text(
          'We need a few entries to learn what is usual for you. Until then '
          'the result uses the standard checks.',
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.white.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Building your baseline',
          style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
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
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
            Text('${PersonalBaseline.minEntries - have} to go',
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
          ],
        ),
      ],
    );
  }

  Widget _ready(PersonalBaseline baseline) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('Last ${baseline.entries} entries', _violet),
        const SizedBox(height: 6),
        Text(
          'Your own average, so the comparison is fair to you.',
          style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 6),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Nothing from this entry can be compared yet.',
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
        for (var i = 0; i < _rows.length; i++) _row(_rows[i], first: i == 0),
      ],
    );
  }

  static String _format(TrendMetric m, double v) => '${v.round()}${m.unit}';

  Widget _row(UsualComparison r, {required bool first}) {
    final color = switch (r.verdict) {
      Verdict.better => _green,
      Verdict.worse => _red,
      Verdict.usual => Colors.white.withValues(alpha: 0.6),
    };
    final top = (r.metric.ceiling ??
            [r.today, r.usual.high].reduce((a, b) => a > b ? a : b) * 1.15)
        .clamp(1.0, double.infinity)
        .toDouble();
    final fill = (r.today / top).clamp(0.0, 1.0);
    final mark = (r.usual.average / top).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      margin: EdgeInsets.only(top: first ? 4 : 8),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(r.metric.label,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              Flexible(
                child: Text(
                  r.headline,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) => SizedBox(
              height: 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 3,
                    height: 10,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 3,
                    height: 10,
                    width: c.maxWidth * fill,
                    child: Container(
                      decoration: BoxDecoration(
                        color: r.verdict == Verdict.usual
                            ? Colors.white.withValues(alpha: 0.45)
                            : color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  Positioned(
                    key: const Key('usual-mark'),
                    left: (c.maxWidth * mark - 1.5).clamp(0.0, c.maxWidth - 3),
                    top: 0,
                    height: 16,
                    width: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(TextSpan(
                text: 'Today ',
                style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5)),
                children: [
                  TextSpan(
                    text: _format(r.metric, r.today),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              )),
              Text.rich(TextSpan(
                text: 'Usual ',
                style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5)),
                children: [
                  TextSpan(
                    text: _format(r.metric, r.usual.average),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ],
              )),
            ],
          ),
        ],
      ),
    );
  }
}
