import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frontend/components/self_bias_identification/services/mood_alert_feedback.dart';
import 'package:frontend/components/self_bias_identification/services/mood_light_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_light.dart';

/// Sits on top of the scan stage. When a scan shows uneasy or stressed, a
/// bulb pops up in the middle with a small bounce and a short message, then
/// shrinks to a small bulb in the corner. Calm shows nothing. The sound and
/// vibration play once, as the bulb pops up.
class MoodBulbPopup extends StatefulWidget {
  final MoodLightLevel level;
  const MoodBulbPopup({super.key, required this.level});

  @override
  State<MoodBulbPopup> createState() => _MoodBulbPopupState();
}

class _MoodBulbPopupState extends State<MoodBulbPopup>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  bool get _animate => MoodLight.forceAnimate ?? !_inTest;
  static bool get _inTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (widget.level == MoodLightLevel.calm) return;
    MoodAlertFeedback.play(widget.level);
    if (_animate) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 3200),
      )..forward();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  String get _title => widget.level == MoodLightLevel.stressed
      ? 'Stress detected'
      : 'Feeling uneasy';

  String get _message => widget.level == MoodLightLevel.stressed
      ? 'Your expression showed strong stress signals'
      : 'Some stress signals showed in your expression';

  Widget _bulb(double size, double glow) {
    final info = moodLightInfo(widget.level);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(info.color, Colors.white, 0.55)!, info.color],
        ),
        boxShadow: [
          BoxShadow(
            color: info.color.withValues(alpha: 0.3 * glow),
            blurRadius: size * 0.5,
            spreadRadius: size * 0.12,
          ),
        ],
      ),
      child: Icon(
        Icons.lightbulb_rounded,
        size: size * 0.52,
        color: const Color(0xFF0A0E14).withValues(alpha: 0.8),
      ),
    );
  }

  Widget _card(MoodLightInfo info) => Container(
        width: 210,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E14).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: info.color.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bulb(54, 1),
            const SizedBox(height: 8),
            Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFC5CED9), fontSize: 11),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.level == MoodLightLevel.calm) return const SizedBox.shrink();
    final info = moodLightInfo(widget.level);
    final corner = Positioned(
      top: 12,
      right: 40,
      child: KeyedSubtree(
        key: Key('mood-bulb-${widget.level.name}'),
        child: _bulb(32, 0.5),
      ),
    );
    final c = _c;
    if (c == null) return Stack(children: [corner]);

    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final t = c.value;
        // 0-0.2 pops in, 0.2-0.7 holds, 0.7-0.85 shrinks away, then the
        // corner bulb stays.
        double scale;
        double opacity;
        if (t < 0.2) {
          scale = Curves.easeOutBack.transform(t / 0.2) * 1.0;
          opacity = (t / 0.12).clamp(0.0, 1.0);
        } else if (t < 0.7) {
          scale = 1;
          opacity = 1;
        } else {
          final k = ((t - 0.7) / 0.15).clamp(0.0, 1.0);
          scale = 1 - 0.85 * k;
          opacity = 1 - k;
        }
        final k = ((t - 0.7) / 0.15).clamp(0.0, 1.0);
        return Stack(
          children: [
            if (t < 0.85)
              Positioned.fill(
                child: Center(
                  child: Transform.translate(
                    offset: Offset(20 * k, -80 * k),
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.scale(scale: scale, child: _card(info)),
                    ),
                  ),
                ),
              ),
            if (t >= 0.7)
              Opacity(
                opacity: ((t - 0.7) / 0.1).clamp(0.0, 1.0),
                child: Stack(children: [corner]),
              ),
          ],
        );
      },
    );
  }
}
