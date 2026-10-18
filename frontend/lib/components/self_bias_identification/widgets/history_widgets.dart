import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/gradient_ring_painter.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';

/// Building blocks shared by the Bias History and Facial History pages.

Color pasColor(int pas) {
  if (pas >= 70) return const Color(0xFF4ADE80);
  if (pas >= 50) return const Color(0xFFFFB74D);
  return const Color(0xFFFF6B6B);
}

Color stressColor(double stress) {
  switch (stressBand(stress)) {
    case StressBand.high:
      return const Color(0xFFFF6B6B);
    case StressBand.moderate:
      return MoodPalette.orange;
    case StressBand.low:
      return const Color(0xFF4ADE80);
  }
}

/// A PAS score inside a coloured ring.
class PasRing extends StatelessWidget {
  final int score;
  final double size;
  const PasRing({super.key, required this.score, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final color = pasColor(score);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: GradientRingPainter(
              progress: score / 100,
              colors: [color.withValues(alpha: 0.7), color],
              strokeWidth: 5,
            ),
          ),
          Text(
            '$score',
            style: GoogleFonts.outfit(
              fontSize: size * 0.3,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A flat dark card, the same surface the rest of the history pages use.
class HistoryCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const HistoryCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class HistoryPill extends StatelessWidget {
  final String label;
  final Color color;
  const HistoryPill({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Section label such as TODAY / YESTERDAY with a small count on the right.
class HistoryGroupHeader extends StatelessWidget {
  final String label;
  final String trailing;
  const HistoryGroupHeader({
    super.key,
    required this.label,
    this.trailing = '',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
        ],
      ),
    );
  }
}

/// Centred explanation for an empty or failed page.
class HistoryMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  const HistoryMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Icon(icon, size: 36, color: Colors.white38),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 22),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [MoodPalette.mint, MoodPalette.cyan],
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0A0E14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Pull down to refresh", shown above the failed state.
class PullHint extends StatelessWidget {
  const PullHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          Icon(Icons.arrow_downward_rounded,
              size: 16, color: Colors.white.withValues(alpha: 0.35)),
          Text(
            'Pull down to refresh',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card-shaped placeholders that shimmer while a page loads.
class HistorySkeleton extends StatefulWidget {
  final int cards;
  const HistorySkeleton({super.key, this.cards = 5});

  @override
  State<HistorySkeleton> createState() => _HistorySkeletonState();
}

class _HistorySkeletonState extends State<HistorySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _block(double height, {double? width}) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = MediaQuery.disableAnimationsOf(context) ? 0.5 : _c.value;
        return Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2, 0),
              end: Alignment(t * 2, 0),
              colors: [
                Colors.white.withValues(alpha: 0.04),
                Colors.white.withValues(alpha: 0.09),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _block(44),
        const SizedBox(height: 12),
        _block(30, width: 220),
        const SizedBox(height: 14),
        for (var i = 0; i < widget.cards; i++) ...[
          _block(72),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Horizontally scrolling filter chips.
class HistoryChips<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final Color activeColor;
  const HistoryChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.activeColor = MoodPalette.violet,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final (value, label) = items[i];
          final on = value == selected;
          return GestureDetector(
            onTap: () => onChanged(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: on ? activeColor : Colors.white.withValues(alpha: 0.05),
                border: Border.all(
                  color: on ? activeColor : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: on
                      ? (activeColor == MoodPalette.mint
                          ? const Color(0xFF0A0E14)
                          : Colors.white)
                      : Colors.white70,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Two- or three-way segmented control.
class HistorySegments extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool mint;
  const HistorySegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.mint = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: i == selected
                        ? LinearGradient(
                            colors: mint
                                ? const [MoodPalette.mint, MoodPalette.cyan]
                                : const [MoodPalette.violet, MoodPalette.violet],
                          )
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: i == selected
                          ? (mint ? const Color(0xFF0A0E14) : Colors.white)
                          : Colors.white60,
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

/// Facial stress over time, with a line at the 50% threshold and a marker
/// wherever a Mood Reset happened.
class StressTimeline extends StatelessWidget {
  final List<HistoryEntry> scans;
  final List<ResetRecord> resets;
  const StressTimeline({super.key, required this.scans, required this.resets});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: CustomPaint(
        size: const Size(double.infinity, 170),
        painter: _TimelinePainter(scans, resets),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<HistoryEntry> scans;
  final List<ResetRecord> resets;
  _TimelinePainter(this.scans, this.resets);

  static const _left = 28.0;
  static const _right = 10.0;
  static const _top = 18.0;
  static const _bottom = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final points = scans
        .where((e) => e.time != null && e.stress != null)
        .toList()
      ..sort((a, b) => a.time!.compareTo(b.time!));
    if (points.isEmpty) return;

    final plotW = size.width - _left - _right;
    final plotH = size.height - _top - _bottom;
    final minT = points.first.time!.millisecondsSinceEpoch.toDouble();
    var maxT = points.last.time!.millisecondsSinceEpoch.toDouble();
    if (maxT - minT < 1) maxT = minT + 1;

    double xOf(DateTime t) =>
        _left +
        plotW *
            ((t.millisecondsSinceEpoch - minT) / (maxT - minT)).clamp(0.0, 1.0);
    double yOf(double stress) => _top + plotH * (1 - stress.clamp(0.0, 1.0));

    final faint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (final v in [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(_left, yOf(v)), Offset(size.width - _right, yOf(v)), faint);
      _text(canvas, '${(v * 100).round()}%', Offset(0, yOf(v) - 6), 9,
          Colors.white.withValues(alpha: 0.35));
    }

    // 50% threshold, dashed
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.2;
    for (var x = _left; x < size.width - _right; x += 8) {
      canvas.drawLine(Offset(x, yOf(0.5)), Offset(x + 4, yOf(0.5)), dash);
    }

    // Reset markers, drawn under the line
    for (final r in resets) {
      final t = r.time;
      if (t == null) continue;
      final ms = t.millisecondsSinceEpoch.toDouble();
      if (ms < minT || ms > maxT) continue;
      final x = xOf(t);
      final marker = Paint()
        ..color = MoodPalette.mint.withValues(alpha: 0.7)
        ..strokeWidth = 1.2;
      for (var y = _top; y < size.height - _bottom; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 3), marker);
      }
      final label = r.deltaPoints == null
          ? 'Reset'
          : (r.deltaPoints! >= 0 ? 'Reset −${r.deltaPoints}' : 'Reset +${r.deltaPoints!.abs()}');
      _pill(canvas, label, Offset(x, 6), MoodPalette.mint);
    }

    // The stress line
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = Offset(xOf(points[i].time!), yOf(points[i].stress!));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = MoodPalette.violetSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    for (final p in points) {
      canvas.drawCircle(
        Offset(xOf(p.time!), yOf(p.stress!)),
        3.6,
        Paint()..color = stressColor(p.stress!),
      );
    }

    // Dates under the line: first, middle, last
    final now = DateTime.now();
    final indexes = <int>{0, points.length ~/ 2, points.length - 1}.toList()..sort();
    for (final i in indexes) {
      final t = points[i].time!;
      _text(canvas, shortTime(t, now), Offset(xOf(t) - 14, size.height - 14), 9,
          Colors.white.withValues(alpha: 0.4));
    }
  }

  void _text(Canvas canvas, String text, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _pill(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0A0E14),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: tp.width + 14, height: 15),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.scans != scans || old.resets != resets;
}
