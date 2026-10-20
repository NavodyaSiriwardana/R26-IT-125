import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frontend/components/self_bias_identification/services/mood_light_data.dart';

/// A small light bulb that glows green, amber or red for the mood a scan
/// showed. It pulses slowly (never blinks). The word under it says the same
/// thing as the colour, so colour is not the only signal.
class MoodLight extends StatefulWidget {
  final MoodLightLevel level;
  final double size;
  final bool showLabel;

  /// Tests set this to switch the pulse off (a repeating animation never
  /// settles). Null means: pulse everywhere except inside `flutter test`.
  static bool? forceAnimate;

  const MoodLight({
    super.key,
    required this.level,
    this.size = 46,
    this.showLabel = false,
  });

  @override
  State<MoodLight> createState() => _MoodLightState();
}

class _MoodLightState extends State<MoodLight>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  static bool get _inFlutterTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  bool get _animate => MoodLight.forceAnimate ?? !_inFlutterTest;

  @override
  void initState() {
    super.initState();
    if (_animate) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2800),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  Widget _bulb(MoodLightInfo info, double t) {
    final size = widget.size;
    return Container(
      key: Key('mood-light-${info.level.name}'),
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
            color: info.color.withValues(alpha: 0.16 + 0.14 * t),
            blurRadius: size * 0.25 + size * 0.5 * t,
            spreadRadius: size * 0.05 + size * 0.1 * t,
          ),
        ],
      ),
      child: Icon(
        Icons.lightbulb_rounded,
        size: size * 0.52,
        color: const Color(0xFF0A0E14).withValues(alpha: 0.78),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = moodLightInfo(widget.level);
    final pulse = _pulse;
    final bulb = pulse == null
        ? _bulb(info, 0.5)
        : AnimatedBuilder(
            animation: pulse,
            builder: (context, _) =>
                _bulb(info, Curves.easeInOut.transform(pulse.value)),
          );
    if (!widget.showLabel) return bulb;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        bulb,
        const SizedBox(height: 6),
        Text(
          info.word,
          style: TextStyle(
            color: info.color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}
