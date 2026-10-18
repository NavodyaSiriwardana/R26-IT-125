import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../components/temporal_causal_patterns/screens/login_screen.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 108,
                height: 108,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D1B2A), Color(0xFF1B3A4B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2DD9BE).withValues(alpha: 0.35),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                // TODO: swap for the real IDiary mark once the asset file is
                // added to assets/images/ — placeholder book+mind glyph for now.
                child: const Icon(Icons.auto_stories_rounded,
                    color: Color(0xFF2DD9BE), size: 48),
              ),
              const SizedBox(height: 22),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.manrope(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  children: const [
                    TextSpan(
                        text: 'I',
                        style: TextStyle(color: Color(0xFF2DD9BE))),
                    TextSpan(
                        text: 'Diary', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'YOUR INTELLIGENT DIARY',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white38,
                  letterSpacing: 2.2,
                ),
              ),
              const Spacer(flex: 2),
              Text(
                'Time for your\nDiary Reflection',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.2,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Prioritize what\'s ahead,\nunderstand what\'s behind.',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  color: Colors.white54,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(29),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7B61FF).withValues(alpha: 0.4),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(29),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(29),
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      },
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(29),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2DD9BE), Color(0xFF7B61FF)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'START',
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
