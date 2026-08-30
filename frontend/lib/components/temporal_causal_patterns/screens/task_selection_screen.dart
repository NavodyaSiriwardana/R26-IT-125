import 'package:flutter/material.dart';
import 'new_entry_screen.dart';
import '../../task_prioritization/screens/main_navigation_screen.dart';

class TaskSelectionScreen extends StatelessWidget {
  const TaskSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A16),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -0.9),
            radius: 1.4,
            colors: [Color(0xFF181432), Color(0xFF0A0A16)],
            stops: [0.0, 0.65],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'What would you like to do?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.25,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'CHOOSE HOW YOU WANT TO MANAGE YOUR DAY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF9C9CC0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 52),

                // FUTURE TASK — routes to friend's component
                _ModeCard(
                  gradientColors: const [Color(0xFF1E9E89), Color(0xFF5A46C4)],
                  glowColor: const Color(0xFF7B61FF),
                  icon: Icons.upcoming_rounded,
                  title: 'Future Task',
                  subtitle: 'Plan and prioritize upcoming tasks',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MainNavigationScreen()),
                    );
                  },
                ),

                const SizedBox(height: 18),

                // PAST TASK — routes to YOUR diary entry template
                _ModeCard(
                  gradientColors: const [Color(0xFF1E9E89), Color(0xFF178A41)],
                  glowColor: const Color(0xFF1DB954),
                  icon: Icons.history_edu_rounded,
                  title: 'Past Task',
                  subtitle: 'Log a diary entry & discover patterns',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NewEntryScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final List<Color> gradientColors;
  final Color glowColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.gradientColors,
    required this.glowColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.06),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: 0.45),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.35),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.35,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
