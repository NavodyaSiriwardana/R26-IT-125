import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/screens/mood_reset_screen.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';
import 'package:frontend/components/self_bias_identification/services/mood_light_data.dart';

/// "Mood Support" card shown on the result screen and on the
/// Recommendations screen. Renders the backend's `mood_support` block:
/// detected mood, emotion bars, why this plan, a short action list, the
/// stress trend, and the entry point into the 2-minute Mood Reset.
class MoodSupportCard extends StatelessWidget {
  final Map<String, dynamic> moodSupport;
  final Map<String, dynamic>? facialEmotion;
  final String entryId;
  final String title;

  const MoodSupportCard({
    super.key,
    required this.moodSupport,
    required this.facialEmotion,
    required this.entryId,
    this.title = 'Mood Support',
  });

  bool get _hasCamera =>
      facialEmotion != null && facialEmotion!['status'] == 'success';

  @override
  Widget build(BuildContext context) {
    final mood = Map<String, dynamic>.from(moodSupport['mood'] as Map? ?? {});
    final state = (mood['state'] ?? 'calm').toString();
    final label = (mood['label'] ?? 'Calm').toString();
    final stress = (mood['stress'] as num?)?.toDouble();
    final color = MoodPalette.forState(state);
    final gradient = MoodPalette.gradientForState(state);
    final needsReset = moodSupport['needs_reset'] == true;
    final escalate = moodSupport['escalate'] == true;
    final reason = (moodSupport['reason'] ?? '').toString();
    final actions = (moodSupport['actions'] as List? ?? [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
    final trend = Map<String, dynamic>.from(moodSupport['trend'] as Map? ?? {});
    final trendValues = (trend['values'] as List? ?? [])
        .map((v) => (v as num).toDouble())
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(colors: gradient),
                ),
                child: const Icon(
                  Icons.spa_rounded,
                  size: 18,
                  color: Color(0xFF0A0E14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              _pill(
                label: stress != null
                    ? '$label · ${(stress * 100).round()}%'
                    : label,
                color: color,
                filled: true,
              ),
            ],
          ),
          if (mood['mismatch'] == true) ...[
            const SizedBox(height: 10),
            _pill(
              label: 'You reported: ${mood['reported']}',
              color: MoodPalette.violetSoft,
            ),
          ],
          if (_hasCamera && needsReset) ...[
            const SizedBox(height: 16),
            _emotionBars(),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              reason,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ],
          if (trendValues.length >= 2) ...[
            const SizedBox(height: 18),
            _trend(trendValues, (trend['direction'] ?? 'steady').toString()),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            ...actions.map(_actionTile),
          ],
          if (escalate) ...[
            const SizedBox(height: 4),
            _escalationNote(),
          ],
          if (needsReset && _hasCamera) ...[
            const SizedBox(height: 16),
            _resetButton(context, gradient, color, label, stress ?? 0),
          ] else if (_hasCamera) ...[
            const SizedBox(height: 16),
            _calmResetLink(context, color, label, stress ?? 0),
          ] else if (needsReset) ...[
            const SizedBox(height: 4),
            Text(
              'Take a camera scan on your next entry to unlock the guided Mood Reset.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required Color color,
    bool filled = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: filled ? 0.6 : 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _emotionBars() {
    final scores = Map<String, dynamic>.from(
      facialEmotion!['emotion_scores'] as Map? ?? {},
    );
    final top = scores.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    const emotionColors = {
      'sad': MoodPalette.blue,
      'angry': MoodPalette.coral,
      'fear': MoodPalette.amber,
      'disgust': MoodPalette.pink,
      'neutral': MoodPalette.violetSoft,
      'happy': MoodPalette.mint,
      'surprise': MoodPalette.cyan,
    };
    return Column(
      children: top.take(4).map((e) {
        final v = (e.value as num).toDouble().clamp(0.0, 1.0);
        final c = emotionColors[e.key] ?? MoodPalette.violet;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 58,
                child: Text(
                  e.key[0].toUpperCase() + e.key.substring(1),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(
                        height: 7,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      FractionallySizedBox(
                        widthFactor: v,
                        child: Container(
                          height: 7,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [c.withValues(alpha: 0.7), c],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${(v * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _trend(List<double> values, String direction) {
    final rising = direction == 'rising';
    final falling = direction == 'falling';
    final dirColor = rising
        ? MoodPalette.coral
        : falling
        ? MoodPalette.mint
        : MoodPalette.violetSoft;
    final dirLabel = rising
        ? 'Rising'
        : falling
        ? 'Falling'
        : 'Steady';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'STRESS TREND · LAST ${values.length}',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            _pill(label: dirLabel, color: dirColor),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < values.length; i++) ...[
                Expanded(
                  child: Container(
                    height: 8 + 44 * values[i].clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: i == values.length - 1
                            ? const [MoodPalette.coral, MoodPalette.orange]
                            : [
                                MoodPalette.violet.withValues(alpha: 0.35),
                                MoodPalette.violet.withValues(alpha: 0.7),
                              ],
                      ),
                    ),
                  ),
                ),
                if (i != values.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final v in values)
              Text(
                '${(v * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _actionTile(Map<String, dynamic> a) {
    final kind = (a['kind'] ?? '').toString();
    final c = MoodPalette.forKind(kind);
    final minutes = (a['minutes'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: c.withValues(alpha: 0.18),
            ),
            child: Icon(MoodPalette.iconForKind(kind), size: 20, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (a['title'] ?? '').toString(),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  (a['detail'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          if (minutes > 0) ...[
            const SizedBox(width: 8),
            _pill(label: '$minutes min', color: c),
          ],
        ],
      ),
    );
  }

  Widget _escalationNote() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MoodPalette.coral.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MoodPalette.coral.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.favorite_rounded,
            size: 18,
            color: MoodPalette.coral,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your stress has been high for several entries in a row. Please consider reaching out to someone you trust.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A quiet, optional reset for a calm mood: the reset is always available.
  Widget _calmResetLink(
    BuildContext context,
    Color color,
    String moodLabel,
    double stress,
  ) {
    return GestureDetector(
      key: const Key('calm-reset-link'),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MoodResetScreen(
            entryId: entryId,
            beforeStress: stress,
            beforeMoodLabel: moodLabel,
            breathing: Map<String, dynamic>.from(
              moodSupport['breathing'] as Map? ?? defaultBreathing,
            ),
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: moodLightGreen.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Text(
            'Try a 2-minute breathing reset',
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: moodLightGreen,
            ),
          ),
        ),
      ),
    );
  }

  Widget _resetButton(
    BuildContext context,
    List<Color> gradient,
    Color color,
    String moodLabel,
    double stress,
  ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MoodResetScreen(
            entryId: entryId,
            beforeStress: stress,
            beforeMoodLabel: moodLabel,
            breathing: Map<String, dynamic>.from(
              moodSupport['breathing'] as Map? ?? {},
            ),
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: gradient),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.air_rounded,
              size: 20,
              color: Color(0xFF0A0E14),
            ),
            const SizedBox(width: 8),
            Text(
              'Start 2-min Mood Reset',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0A0E14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
