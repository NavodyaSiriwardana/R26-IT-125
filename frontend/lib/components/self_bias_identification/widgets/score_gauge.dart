import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The score shown like a bike meter: a 240 degree dial with a scale, three
/// colour zones, a needle, and the app logo faintly behind the hub. Flat
/// colours only, and nothing moves: the needle is drawn at the score.
///
/// Zones: red 0-49 (needs work), orange 50-69 (okay), green 70-100 (aligned).
class ScoreGauge extends StatefulWidget {
  final int score;
  final double width;

  /// Sweeps the needle from 0 to the score once when it first appears.
  /// Off in tests that only check the final reading.
  final bool sweep;

  const ScoreGauge({
    super.key,
    required this.score,
    this.width = 280,
    this.sweep = true,
  });

  static const red = Color(0xFFFF6977);
  static const orange = Color(0xFFF4B653);
  static const green = Color(0xFF35E47B);
  static const target = 70;
  static const sweepDuration = Duration(milliseconds: 1000);

  static const coral = Color(0xFFFF8A4C);
  static const teal = Color(0xFF55CFE0);

  /// A pure colour for a score, finer than the three zones so neighbouring
  /// results in a list can be told apart. Every shade stays inside its zone's
  /// family: 0-34 red, 35-49 coral, 50-69 amber, 70-84 green, 85+ teal.
  static Color toneFor(num score) {
    if (score >= 85) return teal;
    if (score >= target) return green;
    if (score >= 50) return orange;
    if (score >= 35) return coral;
    return red;
  }

  /// The colour of the zone a score falls in.
  static Color colorFor(int score) =>
      score >= target ? green : (score >= 50 ? orange : red);

  // The drawing is laid out on a 300 x 230 board and scaled to [width].
  static const _boardW = 300.0;
  static const _boardH = 230.0;

  @override
  State<ScoreGauge> createState() => _ScoreGaugeState();
}

class _ScoreGaugeState extends State<ScoreGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ScoreGauge.sweepDuration,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  double _from = 0;
  bool _started = false;

  int get _score => widget.score.clamp(0, 100).toInt();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Once, when it first appears. Skipped when the phone asks for no motion.
    if (widget.sweep && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant ScoreGauge old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      if (widget.sweep && !MediaQuery.disableAnimationsOf(context)) {
        // A new score: move from where the needle was, again just once.
        _from = _shown(old.score.clamp(0, 100).toDouble());
        _controller.forward(from: 0);
      } else {
        _from = 0;
        _controller.value = 1;
      }
    }
  }

  /// Where the needle is now: from [_from] to the score as the sweep runs.
  double _shown([double? target]) {
    final to = target ?? _score.toDouble();
    return _from + (to - _from) * _curve.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final scale = width / ScoreGauge._boardW;
    final color = ScoreGauge.colorFor(_score);
    return SizedBox(
      width: width,
      height: ScoreGauge._boardH * scale,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // The app logo, very faint, behind the dial and needle.
          Positioned(
            left: 0,
            right: 0,
            top: (_ScoreGaugePainter.cy - 64) * scale,
            child: Opacity(
              opacity: 0.10,
              child: Image.asset(
                'assets/images/truthlens_logo.png',
                width: 96 * scale,
                height: 96 * scale,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _curve,
            builder: (context, _) => CustomPaint(
              size: Size(width, ScoreGauge._boardH * scale),
              painter: _ScoreGaugePainter(
                value: _shown(),
                color: color,
                scale: scale,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: (_ScoreGaugePainter.cy + 24) * scale,
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _curve,
                  builder: (context, _) => Text(
                    '${_shown().round()}',
                    style: GoogleFonts.outfit(
                      fontSize: 50 * scale,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                SizedBox(height: 4 * scale),
                Text(
                  'out of 100',
                  style: TextStyle(
                    fontSize: 13 * scale.clamp(0.85, 1.2),
                    color: const Color(0xFF738093),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreGaugePainter extends CustomPainter {
  final double value;
  final Color color;
  final double scale;

  const _ScoreGaugePainter({
    required this.value,
    required this.color,
    required this.scale,
  });

  static const cx = 150.0;
  static const cy = 140.0;
  static const radius = 104.0;
  static const _startDeg = 150.0;
  static const _sweepDeg = 240.0;

  static double _angle(num v) =>
      (_startDeg + _sweepDeg * v / 100) * math.pi / 180;

  static Offset _point(num v, double r) =>
      Offset(cx + r * math.cos(_angle(v)), cy + r * math.sin(_angle(v)));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    // Zone arcs: the whole zone dim, then the part up to the score lit.
    const zones = [
      (0.0, 50.0, ScoreGauge.red),
      (50.0, 70.0, ScoreGauge.orange),
      (70.0, 100.0, ScoreGauge.green),
    ];
    final rect = Rect.fromCircle(center: const Offset(cx, cy), radius: radius);
    Paint stroke(Color c, double alpha) => Paint()
      ..color = c.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.butt;
    for (final (a, b, c) in zones) {
      canvas.drawArc(rect, _angle(a + 0.6), (b - a - 1.2) * _sweepDeg / 100 * math.pi / 180,
          false, stroke(c, 0.28));
      final litEnd = math.min(b, value) - (value < b ? 0 : 0.6);
      if (value > a && litEnd > a + 0.6) {
        canvas.drawArc(rect, _angle(a + 0.6),
            (litEnd - a - 0.6) * _sweepDeg / 100 * math.pi / 180, false, stroke(c, 1));
      }
    }

    // Scale: a tick every 5, longer every 25, with the numbers inside.
    for (var v = 0; v <= 100; v += 5) {
      final major = v % 25 == 0;
      canvas.drawLine(
        _point(v, radius - 14),
        _point(v, radius - (major ? 26 : 21)),
        Paint()
          ..color = Colors.white.withValues(alpha: major ? 0.55 : 0.25)
          ..strokeWidth = major ? 2 : 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final v in const [0, 25, 50, 75, 100]) {
      _label(canvas, '$v', _point(v, radius - 40), 11, const Color(0xFF738093), FontWeight.w600);
    }

    // The 70 target.
    canvas.drawLine(
      _point(ScoreGauge.target, radius + 11),
      _point(ScoreGauge.target, radius + 21),
      Paint()
        ..color = const Color(0xFFF4F7FB)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    _label(canvas, '${ScoreGauge.target}', _point(ScoreGauge.target, radius + 33), 11,
        const Color(0xFFA5AFBE), FontWeight.w700);

    // Needle: a slim tapered pointer with a hub.
    final a = _angle(value);
    final tip = Offset(cx + (radius - 22) * math.cos(a), cy + (radius - 22) * math.sin(a));
    final side = Offset(math.cos(a + math.pi / 2) * 5, math.sin(a + math.pi / 2) * 5);
    final tail = Offset(cx - 16 * math.cos(a), cy - 16 * math.sin(a));
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(cx + side.dx, cy + side.dy)
        ..lineTo(tail.dx, tail.dy)
        ..lineTo(cx - side.dx, cy - side.dy)
        ..close(),
      Paint()..color = color,
    );
    canvas.drawCircle(const Offset(cx, cy), 11, Paint()..color = const Color(0xFF0D131D));
    canvas.drawCircle(
      const Offset(cx, cy),
      11,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(const Offset(cx, cy), 3.5, Paint()..color = color);

    canvas.restore();
  }

  void _label(Canvas canvas, String text, Offset center, double size, Color color,
      FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ScoreGaugePainter old) =>
      old.value != value || old.color != color || old.scale != scale;
}
