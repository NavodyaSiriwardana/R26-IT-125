import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/alert_rules.dart';

const alertRed = Color(0xFFEF6B6B);
const alertYellow = Color(0xFFF2B84B);

Color alertColor(CriticalAlert a) => a.isStress ? alertYellow : alertRed;

/// The "Needs attention" card at the top of Home while an alert is open.
/// Red for a critical bias, yellow for a stress check-in.
class AlertCard extends StatelessWidget {
  final CriticalAlert alert;
  final VoidCallback onOpen;
  const AlertCard({super.key, required this.alert, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final color = alertColor(alert);
    return Container(
      key: const Key('alert-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  alert.isStress ? 'A quick check-in' : 'Needs attention',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: color.withValues(alpha: 0.55)),
                ),
                child: Text(
                  alert.isStress ? 'Check-in' : 'Critical',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert.body,
            style: const TextStyle(
              color: Color(0xFFC5CED9),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            key: const Key('alert-open'),
            onTap: onOpen,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'See what it means',
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0A0E14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown on Home when nothing is open. It is also the lecture-mode note.
class AllClearCard extends StatelessWidget {
  final String? lectureUntil;
  const AllClearCard({super.key, this.lectureUntil});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF5DCAA5);
    final lecture = lectureUntil != null;
    return Container(
      key: Key(lecture ? 'lecture-card' : 'all-clear-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: green.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  lecture ? 'Lecture mode on' : 'All clear',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: green.withValues(alpha: 0.5)),
                ),
                child: Text(
                  lecture ? 'Until $lectureUntil' : 'Nothing open',
                  style: const TextStyle(
                    color: green,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            lecture
                ? 'Alerts are quiet until class ends. You can still scan any time.'
                : 'We will tell you only if something important comes up.',
            style: const TextStyle(color: Color(0xFFA5AFBE), fontSize: 13),
          ),
        ],
      ),
    );
  }
}
