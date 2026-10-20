import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/progress_rules.dart';

const _green = Color(0xFF5DCAA5);
const _yellow = Color(0xFFF2B84B);
const _red = Color(0xFFEF6B6B);

Color progressColor(ProgressLevel level) {
  switch (level) {
    case ProgressLevel.low:
      return _red;
    case ProgressLevel.dip:
      return _yellow;
    case ProgressLevel.up:
    case ProgressLevel.steady:
      return _green;
  }
}

/// The word in the chip, or null when no chip is needed.
String? progressChip(ProgressLevel level) {
  switch (level) {
    case ProgressLevel.low:
      return 'Very low';
    case ProgressLevel.dip:
      return 'A quieter week';
    case ProgressLevel.up:
      return 'Improving';
    case ProgressLevel.steady:
      return null;
  }
}

/// "▲ 40 min vs your first week", or null when there is nothing to compare.
String? progressDeltaText(ProgressSummary s) {
  final d = s.studyDelta;
  if (!s.ready || d == null) return null;
  final m = d.abs().round();
  if (m == 0) return 'About the same as your first week';
  return '${d > 0 ? '▲' : '▼'} $m min vs your first week';
}

/// The last card on the dashboard. Tap it to open My productivity progress.
class ProgressCard extends StatelessWidget {
  final ProgressSummary summary;
  final VoidCallback onTap;
  const ProgressCard({super.key, required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = progressColor(summary.level);
    final chip = progressChip(summary.level);
    final delta = progressDeltaText(summary);

    Widget body;
    if (!summary.ready) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Day ${summary.dayCount} of $baselineDays',
            style: GoogleFonts.outfit(
                fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Building your baseline. Keep writing diary entries.',
            style: TextStyle(color: Color(0xFF9AA5B4), fontSize: 13),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: summary.dayCount / baselineDays,
              minHeight: 6,
              backgroundColor: const Color(0xFF1A2330),
              valueColor: const AlwaysStoppedAnimation(_green),
            ),
          ),
        ],
      );
    } else {
      final study = summary.current.studyPerDay;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                study == null ? '-' : formatMinutes(study),
                style: GoogleFonts.outfit(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: summary.level == ProgressLevel.low ? _red : Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text('/ day',
                    style: TextStyle(color: Color(0xFF9AA5B4), fontSize: 13)),
              ),
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(delta,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      );
    }

    return GestureDetector(
      key: const Key('progress-card'),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: summary.level == ProgressLevel.low
              ? const Color(0xFF1A1113)
              : const Color(0xFF0D131D),
          border: Border.all(
            color: summary.ready && summary.level != ProgressLevel.steady
                ? color.withValues(alpha: 0.4)
                : const Color(0x17FFFFFF),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'MY PRODUCTIVITY PROGRESS',
                    style: TextStyle(
                      color: Color(0xFF667284),
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (summary.ready && chip != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    child: Text(chip,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF667284)),
              ],
            ),
            const SizedBox(height: 10),
            body,
          ],
        ),
      ),
    );
  }
}
