import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/consent_service.dart';
import 'package:frontend/components/self_bias_identification/services/study_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';

/// Informed consent shown before the camera is used for the first time.
/// Pops `true` when the user agrees, `false` otherwise.
class ConsentScreen extends StatefulWidget {
  /// Pre-selects the optional study checkbox (used from the Profile screen).
  final bool studyPreselected;
  const ConsentScreen({super.key, this.studyPreselected = false});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agreeCamera = false;
  late bool _joinStudy = widget.studyPreselected;
  bool _saving = false;

  Future<void> _agree() async {
    setState(() => _saving = true);
    await ConsentService.record(studyMode: _joinStudy);
    if (_joinStudy) await StudyService.setStudyMode(true);
    if (!mounted) return;
    AppToast.success(
      context,
      _joinStudy
          ? 'Thanks. Camera analysis and study mode are on.'
          : 'Thanks. Camera analysis is on.',
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Before we use your camera',
                          style: GoogleFonts.outfit(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'TruthLens is a SLIIT final-year research project (R26-IT-125). Please read how your data is used.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _section(
                          Icons.camera_alt_outlined,
                          MoodPalette.cyan,
                          'What the camera does',
                          'Your photo is sent to the project server, which reads your facial expression and returns emotion scores and a stress estimate. The photo itself is not saved and no video is recorded.',
                        ),
                        _section(
                          Icons.inventory_2_outlined,
                          MoodPalette.violetSoft,
                          'What is kept',
                          'Emotion scores and the stress estimate, your diary entry details, a summary of app usage and place labels, how you rate your own stress (1 to 5), and your Mood Reset results.',
                        ),
                        _section(
                          Icons.info_outline_rounded,
                          MoodPalette.amber,
                          'What the stress score means',
                          'It is an estimate from facial expression, not a medical or psychological measurement. It can be wrong, for example in poor light.',
                        ),
                        _section(
                          Icons.lock_open_rounded,
                          MoodPalette.mint,
                          'Your choices',
                          'Using the camera is optional: you can skip it on any scan. You can delete everything this app stored about you at any time from Profile > Research & Privacy. Entries in the shared team diary are kept by that component and are not deleted by this app.',
                        ),
                        const SizedBox(height: 8),
                        _check(
                          value: _agreeCamera,
                          onChanged: (v) => setState(() => _agreeCamera = v),
                          title: 'I have read this and agree to the camera analysis described above.',
                          emphasised: true,
                        ),
                        const SizedBox(height: 10),
                        _check(
                          value: _joinStudy,
                          onChanged: (v) => setState(() => _joinStudy = v),
                          title: 'Optional: include my Mood Reset results in the research study.',
                          subtitle:
                              'Your results are used under a coded ID, not your name, and reported only as group statistics. Some resets will be a quiet-rest comparison instead of breathing. You can switch this off in Profile.',
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _agreeCamera && !_saving ? _agree : null,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: _agreeCamera
                                ? const LinearGradient(
                                    colors: [MoodPalette.mint, MoodPalette.cyan],
                                  )
                                : null,
                            color: _agreeCamera
                                ? null
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                          child: Center(
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Color(0xFF0A0E14),
                                    ),
                                  )
                                : Text(
                                    'I agree',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: _agreeCamera
                                          ? const Color(0xFF0A0E14)
                                          : Colors.white38,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(
                          'No thanks, continue without the camera',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(IconData icon, Color color, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _check({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    String? subtitle,
    bool emphasised = false,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? MoodPalette.mint.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: emphasised ? 0.2 : 0.1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              color: value ? MoodPalette.mint : Colors.white54,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
