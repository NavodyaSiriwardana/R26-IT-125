import 'package:flutter/material.dart';

abstract final class DashboardColors {
  static const background = Color(0xFF0A1113);
  static const surface = Color(0xFF11191C);
  static const surfaceElevated = Color(0xFF1A2529);
  static const primary = Color(0xFF2DD9BE);
  static const primaryDark = Color(0xFF126B5C);
  static const border = Color(0xFF223236);
  static const accent = Color(0xFFF2B84B);
  static const accentText = Color(0xFFFFE1A3);
  static const text = Color(0xFFEDF5F3);
  static const muted = Color(0xFF8FA6A3);
  static const warning = Color(0xFFFFC76A);
  static const negative = Color(0xFFFF8A98);

  static const chartColors = <Color>[
    primary,
    accent,
    Color(0xFF5CB8E6),
    Color(0xFFE789C3),
    Color(0xFFA6D66D),
    negative,
  ];

  static const cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF15201F), Color(0xFF0F1719)],
  );

  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];
}
