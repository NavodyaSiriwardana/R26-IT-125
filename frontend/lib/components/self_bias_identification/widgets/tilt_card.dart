import 'package:flutter/material.dart';

/// Clips [child] to rounded corners. It used to tilt in 3D under a finger;
/// that motion was removed to keep the cards still and professional. The
/// name and parameters are kept so existing call sites do not change.
class TiltCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}
