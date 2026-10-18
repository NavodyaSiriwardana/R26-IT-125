import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';
import 'package:frontend/components/self_bias_identification/widgets/history_widgets.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_support_card.dart';
import 'package:frontend/components/temporal_causal_patterns/screens/new_entry_screen.dart';

/// Result of a camera scan taken with no diary entry to compare against.
/// Shows the face reading and Mood Support only: there is no bias type and no
/// PAS score, because those need a diary entry to compare with.
class FaceCheckScreen extends StatefulWidget {
  final Map<String, dynamic> facial;
  final Map<String, dynamic> moodSupport;
  final String entryId;

  /// Opened from Facial History rather than straight after a scan.
  final bool fromHistory;

  /// Why there was no bias analysis: `none` (no diary entry yet), `stale` (the
  /// latest entry is too old) or `analyzed` (it was already analysed).
  final String reason;

  const FaceCheckScreen({
    super.key,
    required this.facial,
    required this.moodSupport,
    required this.entryId,
    this.fromHistory = false,
    this.reason = 'none',
  });

  /// What to tell the student about adding a diary entry.
  static String messageFor(String reason) {
    switch (reason) {
      case 'stale':
        return 'Your last diary entry is too old to compare with your phone '
            'data. Add a new one to get your bias result.';
      case 'analyzed':
        return 'Your latest diary entry was already analyzed. Add a new one '
            'to get a new bias result.';
      default:
        return 'You have no diary entry yet. Add one to compare what you wrote '
            'with what your phone recorded and get your bias result.';
    }
  }

  @override
  State<FaceCheckScreen> createState() => _FaceCheckScreenState();
}

class _FaceCheckScreenState extends State<FaceCheckScreen> {
  Map<String, dynamic> get facial => widget.facial;
  Map<String, dynamic> get moodSupport => widget.moodSupport;
  String get entryId => widget.entryId;
  bool get fromHistory => widget.fromHistory;

  @override
  void initState() {
    super.initState();
    // Straight after a scan, say plainly what is missing, like a reminder.
    if (!widget.fromHistory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AppToast.info(context, 'Add a diary entry to see your full bias result.');
        }
      });
    }
  }

  static const _bg = Color(0xFF0A0E14);
  static const _surface = Color(0xFF0D131D);
  static const _amber = Color(0xFFF4B653);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                child: Column(
                  children: [
                    _notice(),
                    const SizedBox(height: 12),
                    _faceCard(),
                    const SizedBox(height: 12),
                    MoodSupportCard(
                      moodSupport: moodSupport,
                      facialEmotion: facial,
                      entryId: entryId,
                    ),
                    const SizedBox(height: 16),
                    _diaryButton(context),
                    if (!fromHistory) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Saved to Facial History as "Face only"',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: Colors.white,
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Face check',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Face only, no diary entry',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _amber, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This is a face check only',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _amber,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  FaceCheckScreen.messageFor(widget.reason),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _faceCard() {
    final stress = (facial['stress_indicator'] as num?)?.toDouble() ?? 0;
    final dominant = (facial['dominant_emotion'] ?? '').toString();
    final emotion = dominant.isEmpty
        ? 'Face'
        : dominant[0].toUpperCase() + dominant.substring(1);
    final color = stressColor(stress);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FACIAL CHECK',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  faceEmoji(stress, dominant),
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$emotion detected',
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${(stress * 100).round()}% stress signal',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              HistoryPill(label: stressLabel(stress), color: color),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: stress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'An estimate from facial expression, not a medical measurement. '
            'Your photo was not saved.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diaryButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: MoodPalette.mint,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            // Same destination as "Open Diary Entry" on the no-entry screen:
            // the team's diary template, with one screen left underneath.
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const NewEntryScreen()),
              (route) => route.isFirst,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Center(
              child: Text(
                'Open Diary Entry',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF04231A),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
