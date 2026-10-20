import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/screens/mood_reset_screen.dart';
import 'package:frontend/components/self_bias_identification/services/alert_rules.dart';
import 'package:frontend/components/self_bias_identification/services/alert_service.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/services/mood_light_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/alert_card.dart';

/// What the alert means, the entries behind it, and a few things to try.
/// "Got it" closes the alert until a new pattern appears.
class AlertDetailScreen extends StatelessWidget {
  final CriticalAlert alert;
  const AlertDetailScreen({super.key, required this.alert});

  static const _bg = Color(0xFF070B12);
  static const _mut = Color(0xFF9AA5B4);

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _dayOf(HistoryEntry e) =>
      e.time == null ? '' : _days[e.time!.weekday - 1];

  @override
  Widget build(BuildContext context) {
    final color = alertColor(alert);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          alert.isStress ? 'A quick check-in' : 'Needs attention',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title,
                      style: GoogleFonts.outfit(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(alert.body,
                      style: const TextStyle(
                          color: Color(0xFFC5CED9), fontSize: 14, height: 1.45)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _card(
              alert.isStress ? 'YOUR LAST 3 DAYS' : 'THE ENTRIES BEHIND THIS',
              [
                for (final e in alert.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [_dayOf(e), if (e.subtitle.isNotEmpty) e.subtitle]
                                    .where((p) => p.isNotEmpty)
                                    .join(' · '),
                                style: const TextStyle(
                                    fontSize: 13.5, fontWeight: FontWeight.w700),
                              ),
                              if (!e.faceOnly && !alert.isStress)
                                Text(e.title,
                                    style: const TextStyle(
                                        color: _mut, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(
                          alert.isStress
                              ? '${((e.stress ?? 0) * 100).round()}% stress'
                              : 'PAS ${e.pas}',
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _card('WHAT YOU CAN TRY', [
              for (var i = 0; i < alert.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: moodLightGreen.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: moodLightGreen,
                                fontWeight: FontWeight.w800,
                                fontSize: 11)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(alert.steps[i],
                            style: const TextStyle(
                                color: Color(0xFFC5CED9),
                                fontSize: 13.5,
                                height: 1.4)),
                      ),
                    ],
                  ),
                ),
            ]),
            if (alert.isStress) ...[
              const SizedBox(height: 14),
              GestureDetector(
                key: const Key('alert-start-reset'),
                onTap: () {
                  final stress = alert.entries.first.stress ?? 0.5;
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
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.6)),
                  ),
                  child: Center(
                    child: Text('Start 2-min Mood Reset',
                        style: GoogleFonts.outfit(
                            color: color,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            GestureDetector(
              key: const Key('alert-got-it'),
              onTap: () async {
                await AlertService.dismiss(alert.id);
                if (context.mounted) Navigator.pop(context, true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: moodLightGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text('Got it',
                      style: GoogleFonts.outfit(
                          color: const Color(0xFF04342C),
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This is not a medical or emergency service. If you feel unsafe, '
              'contact your university counsellor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String label, List<Widget> children) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white38)),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      );
}
