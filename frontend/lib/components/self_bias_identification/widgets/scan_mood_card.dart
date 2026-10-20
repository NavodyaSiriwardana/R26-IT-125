import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/mood_light_data.dart';

/// A short Mood Support card for the facial scan screen, so a student who
/// scans stress sees the reset straight away, without having to continue
/// first. Amber or red: a full button. Green: a quiet optional link.
class ScanMoodCard extends StatelessWidget {
  final MoodLightLevel level;
  final double stress;
  final VoidCallback onReset;

  const ScanMoodCard({
    super.key,
    required this.level,
    required this.stress,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final info = moodLightInfo(level);
    final needsReset = moodLightNeedsReset(level);

    return Container(
      key: const Key('scan-mood-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: info.color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mood Support',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          Text(
            '${info.label} · ${(stress * 100).round()}%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: info.color,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            moodLightText(level),
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFFC5CED9),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            key: const Key('scan-mood-reset'),
            onTap: onReset,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: needsReset ? 15 : 11),
              decoration: BoxDecoration(
                color: needsReset ? info.color : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: needsReset
                    ? null
                    : Border.all(color: info.color.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: Text(
                  needsReset
                      ? 'Start 2-min Mood Reset'
                      : 'Try a 2-minute breathing reset',
                  style: GoogleFonts.outfit(
                    fontSize: needsReset ? 15 : 13.5,
                    fontWeight: FontWeight.w800,
                    color: needsReset ? const Color(0xFF0A0E14) : info.color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            needsReset
                ? 'This is an estimate from your expression, not a medical result.'
                : 'Optional. A reset is always available.',
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
