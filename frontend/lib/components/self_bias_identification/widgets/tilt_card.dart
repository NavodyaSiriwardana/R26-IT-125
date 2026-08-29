import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Wraps [child] in an interactive 3D tilt — dragging a finger across the
/// card rotates it in perspective and slides a light "sheen" highlight
/// across the surface, then springs back flat on release. Gives glass
/// cards a tactile, premium feel (similar to Apple Wallet cards).
///
/// Uses a [Listener] rather than a [GestureDetector] so it only observes
/// pointer position and never claims the gesture — a card can sit inside
/// a scrolling list without fighting the scroll gesture for the arena.
class TiltCard extends StatefulWidget {
  final Widget child;
  final double maxTiltDegrees;
  final BorderRadius borderRadius;

  const TiltCard({
    super.key,
    required this.child,
    this.maxTiltDegrees = 9,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;
  Animation<Offset>? _springAnim;
  Offset _tilt = Offset.zero; // normalized -1..1 (dx, dy)

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() {
        final anim = _springAnim;
        if (anim != null) setState(() => _tilt = anim.value);
      });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _handlePointer(PointerEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(event.position);
    final dx = ((local.dx / box.size.width) * 2 - 1).clamp(-1.0, 1.0);
    final dy = ((local.dy / box.size.height) * 2 - 1).clamp(-1.0, 1.0);
    _spring.stop();
    setState(() => _tilt = Offset(dx, dy));
  }

  void _reset() {
    _springAnim = Tween<Offset>(begin: _tilt, end: Offset.zero).animate(
      CurvedAnimation(parent: _spring, curve: Curves.elasticOut),
    );
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final rotY = _tilt.dx * widget.maxTiltDegrees * math.pi / 180;
    final rotX = -_tilt.dy * widget.maxTiltDegrees * math.pi / 180;
    final sheenStrength = _tilt.distance.clamp(0.0, 1.0);

    return Listener(
      onPointerDown: _handlePointer,
      onPointerMove: _handlePointer,
      onPointerUp: (_) => _reset(),
      onPointerCancel: (_) => _reset(),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateX(rotX)
          ..rotateY(rotY),
        child: ClipRRect(
          borderRadius: widget.borderRadius,
          child: Stack(
            children: [
              widget.child,
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1 + _tilt.dx, -1 + _tilt.dy),
                      end: Alignment(1 + _tilt.dx, 1 + _tilt.dy),
                      colors: [
                        Colors.white.withValues(alpha: 0.10 * sheenStrength),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
