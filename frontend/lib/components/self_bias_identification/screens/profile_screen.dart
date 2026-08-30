import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/temporal_causal_patterns/screens/login_screen.dart';
import 'package:frontend/components/temporal_causal_patterns/services/local_storage.dart';
import 'package:frontend/components/self_bias_identification/screens/weekly_trends_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_details_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/recommendations_screen.dart';
import 'package:frontend/components/self_bias_identification/services/calendar_settings_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _calendarVerificationEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadCalendarSetting();
  }

  Future<void> _loadCalendarSetting() async {
    final enabled = await CalendarSettingsService.isEnabled();
    if (mounted) setState(() => _calendarVerificationEnabled = enabled);
  }

  Future<void> _onCalendarToggle(bool value) async {
    setState(() => _calendarVerificationEnabled = value);
    await CalendarSettingsService.setEnabled(value);
    if (value && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You'll be asked for calendar access next time you submit a diary entry.",
          ),
          backgroundColor: Color(0xFF534AB7),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile',
          style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.5, -1.1),
            radius: 1.3,
            colors: [const Color(0xFF7B6EFF).withOpacity(0.16), Colors.transparent],
            stops: const [0.0, 0.58],
          ),
        ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(0.07), Colors.white.withOpacity(0.02)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.09)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 40, offset: const Offset(0, 16)),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF9D93FF), Color(0xFF7B6EFF)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF7B6EFF).withOpacity(0.35), blurRadius: 26, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        AppState.userId.isNotEmpty
                            ? AppState.userId[0].toUpperCase()
                            : 'U',
                        style: GoogleFonts.outfit(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppState.userId,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'SLIIT Student • FYP Research',
                    style: TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B6EFF).withOpacity(0.16),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFF7B6EFF).withOpacity(0.3)),
                    ),
                    child: Text(
                      'TruthLens User',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: const Color(0xFF7B6EFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Main Menu
            _modernMenuCard(
              title: "Analysis & Insights",
              children: [
                _modernMenuItem(
                  icon: Icons.lightbulb_outline,
                  title: 'AI Recommendations',
                  subtitle: 'Personalized improvement plan',
                  color: const Color(0xFFFFB74D),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecommendationsScreen()),
                  ),
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.menu_book_outlined,
                  title: 'Bias Types Explained',
                  subtitle: 'Learn about each bias',
                  color: const Color(0xFF60A5FA),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BiasDetailsScreen()),
                  ),
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.bar_chart_outlined,
                  title: 'Weekly Trends',
                  subtitle: 'Charts & analysis',
                  color: const Color(0xFF4ADE80),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WeeklyTrendsScreen()),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Privacy & Permissions
            _modernMenuCard(
              title: "Privacy & Permissions",
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF60A5FA).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.event_available_outlined,
                            color: Color(0xFF60A5FA), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Calendar verification',
                              style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Optional: checks if a diary entry matches '
                              'a planned calendar event, for a more '
                              'accurate score.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.white.withOpacity(0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _calendarVerificationEnabled,
                        onChanged: _onCalendarToggle,
                        activeThumbColor: const Color(0xFF7B6EFF),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Info & Logout
            _modernMenuCard(
              title: "More",
              children: [
                _modernMenuItem(
                  icon: Icons.info_outline,
                  title: 'About TruthLens',
                  subtitle: 'SLIIT FYP Research 2026',
                  color: Colors.white70,
                  onTap: () => _showAbout(context),
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'Sign out of TruthLens',
                  color: const Color(0xFFFF6B6B),
                  onTap: () => _logout(context),
                ),
              ],
            ),

            const SizedBox(height: 32),
            Text(
              'TruthLens v1.0 • Intelligent Diary',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.2),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _modernMenuCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.015)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.5),
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _modernMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withOpacity(0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        color: Colors.white.withOpacity(0.06),
        height: 1,
        indent: 70,
      );

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('About TruthLens', style: TextStyle(color: Colors.white)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TruthLens Engine v1.0',
              style: TextStyle(color: Color(0xFF7B6EFF), fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Self-perception bias detection system for university students.\nPowered by XGBoost classifier with 91% accuracy.',
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
            ),
            SizedBox(height: 12),
            Text(
              'SLIIT FYP Research 2026\nComponent 1: Intelligent Diary',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF7B6EFF))),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () async {
              await LocalStorage.clearAll();
              AppState.userId = '';
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Logout', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
  }
}