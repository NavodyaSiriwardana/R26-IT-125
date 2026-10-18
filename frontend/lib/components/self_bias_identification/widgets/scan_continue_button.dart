import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The full-width "Continue" button under a good face scan.
///
/// It is sized by its text, never by the space around it. In a Scaffold's
/// bottom bar the available height is the whole screen, and a Center or an
/// aligned Container there fills all of it (it once turned into a giant green
/// slab).
class ScanContinueButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  const ScanContinueButton({
    super.key,
    required this.onTap,
    this.color = const Color(0xFF5FCBA6),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('scan-continue'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17),
            child: Text(
              'Continue',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF04342C),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
