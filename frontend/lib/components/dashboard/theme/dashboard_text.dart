import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard_colors.dart';

abstract final class DashboardText {
  static TextStyle screenTitle = GoogleFonts.manrope(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: DashboardColors.text,
  );

  static TextStyle sectionTitle = GoogleFonts.manrope(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: DashboardColors.text,
  );

  static TextStyle cardValue = GoogleFonts.manrope(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: DashboardColors.text,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle cardLabel = GoogleFonts.ibmPlexSans(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: DashboardColors.muted,
  );

  static TextStyle body = GoogleFonts.ibmPlexSans(
    fontSize: 13,
    height: 1.5,
    color: DashboardColors.text,
  );

  static TextStyle caption = GoogleFonts.ibmPlexSans(
    fontSize: 11,
    color: DashboardColors.muted,
  );
}
