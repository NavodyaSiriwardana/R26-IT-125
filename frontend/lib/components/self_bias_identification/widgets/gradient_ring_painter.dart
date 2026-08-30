import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Draws a translucent background ring plus a gradient progress arc,
/// starting at 12 o'clock and sweeping clockwise. Shared across screens
/// so every circular gauge in the app (facial scan viewport, stress
/// meter, confidence ring, PAS score ring) uses the same "biometric"
/// visual language instead of duplicating the painter per screen.
class GradientRingPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final double strokeWidth;
  final bool glowDot;

  const GradientRingPainter({
    required this.progress,
    required this.colors,
    this.strokeWidth = 8,
    this.glowDot = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, trackPaint);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;

    const start = -math.pi / 2;
    final sweep = 2 * math.pi * clamped;

    final gradientPaint = Paint()
      ..shader = SweepGradient(
        colors: colors,
        transform: const GradientRotation(start),
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, start, sweep, false, gradientPaint);

    if (glowDot) {
      final endAngle = start + sweep;
      final dotCenter = Offset(
        center.dx + radius * math.cos(endAngle),
        center.dy + radius * math.sin(endAngle),
      );
      canvas.drawCircle(
        dotCenter,
        strokeWidth * 0.9,
        Paint()
          ..color = colors.last
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(dotCenter, strokeWidth * 0.55, Paint()..color = colors.last);
    }
  }

  @override
  bool shouldRepaint(covariant GradientRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.colors != colors;
}

/// Twelve short tick marks evenly spaced around a circle, drawn behind
/// the gradient ring for the "precision sensor" look used on the score
/// and stress gauges.
class RingTicksPainter extends CustomPainter {
  const RingTicksPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.shortestSide / 2;
    final innerRadius = outerRadius - 8;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * math.pi / 180;
      final p1 = Offset(
        center.dx + innerRadius * math.cos(angle),
        center.dy + innerRadius * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RingTicksPainter oldDelegate) => false;
}
