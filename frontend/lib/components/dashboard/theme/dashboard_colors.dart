import 'package:flutter/material.dart';

abstract final class DashboardColors {
  static const background = Color(0xFF0B0B14);
  static const surface = Color(0xFF181728);
  static const surfaceElevated = Color(0xFF24213B);
  static const primary = Color(0xFF7F77DD);
  static const primaryDark = Color(0xFF3C3489);
  static const border = Color(0xFF403A78);
  static const accent = Color(0xFF1D9E75);
  static const accentText = Color(0xFF87F5D0);
  static const text = Color(0xFFEDEBFF);
  static const muted = Color(0xFFB8B4D8);
  static const warning = Color(0xFFFFC76A);
  static const negative = Color(0xFFFF8A98);

  static const chartColors = <Color>[
    primary,
    accent,
    warning,
    Color(0xFF5CB8E6),
    Color(0xFFE789C3),
    Color(0xFFA6D66D),
  ];
}
