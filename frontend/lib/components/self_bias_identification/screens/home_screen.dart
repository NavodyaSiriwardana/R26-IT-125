import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/widgets/gradient_ring_painter.dart';
import 'package:frontend/components/self_bias_identification/widgets/tilt_card.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_result_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/weekly_trends_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/recommendations_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/userformScreen.dart';
import 'package:frontend/components/self_bias_identification/screens/profile_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/all_entries_screen.dart'
    as all_entries;
import 'package:frontend/components/self_bias_identification/screens/facial_capture_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/my_locations_screen.dart';
import 'package:frontend/components/self_bias_identification/services/location_service.dart';
import 'package:frontend/components/self_bias_identification/services/sensor_data_service.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ============================================================
  // TRUTHLENS DESIGN SYSTEM
  // ============================================================

  static const Color _background = Color(0xFF070B12);

  static const Color _surface = Color(0xFF0D131D);
  static const Color _surface2 = Color(0xFF111A27);

  static const Color _green = Color(0xFF35E47B);

  static const Color _cyan = Color(0xFF55CFE0);

  static const Color _orange = Color(0xFFF4B653);
  static const Color _red = Color(0xFFFF6977);

  static const Color _textPrimary = Color(0xFFF4F7FB);
  static const Color _textSecondary = Color(0xFFA5AFBE);
  static const Color _textMuted = Color(0xFF738093);

  // Glass-card decoration shared by every panel on this screen.
  BoxDecoration _glassDecoration({
    double radius = 20,
    Color borderColor = const Color(0x17FFFFFF),
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.015)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  // ============================================================
  // ORIGINAL DATA (untouched)
  // ============================================================

  int _latestPas = 0;
  String _pasLevel = '';
  String _biasType = '';
  int _claimedDuration = 0;
  int _verifiedEdu = 0;
  int _appSwitches = 0;
  int _socialMedia = 0;
  String _claimedLocation = '';
  String _actualLocation = '';
  String _moodBefore = '';
  String _moodAfter = '';
  String _reflectionText = '';
  double _weeklyAvg = 0;
  List<Map<String, dynamic>> _recentEntries = [];
  bool _isLoading = true;
  Map<String, dynamic>? _latestEntry;

  @override
  void initState() {
    super.initState();
    SensorDataService.requestPermissions();
    _loadData();
    // Sequenced (not parallel) so none of these setup dialogs ever stack
    // on top of each other on a first launch.
    _checkUsageAccessSetup()
        .then((_) => _checkAccessibilitySetup())
        .then((_) => _checkLocationsSetup());
  }

  // ============================================================
  // USAGE ACCESS ALERT (without this, social media/educational minutes
  // silently report as 0 with no visible error)
  // ============================================================

  Future<void> _checkUsageAccessSetup() async {
    bool granted;
    try {
      granted = await SensorDataService.hasUsageAccess();
    } catch (e) {
      return;
    }
    if (granted || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Row(
          children: [
            Icon(Icons.query_stats_rounded, color: _orange),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enable Usage Access',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'TruthLens needs Usage Access to verify your social media and '
          'study time against what you claim in your diary. Without it, '
          'app usage will always show as 0 in your reports.',
          style: TextStyle(color: _textSecondary, height: 1.4, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later', style: TextStyle(color: _textMuted)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              SensorDataService.openUsageAccessSettings();
            },
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: _background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACCESSIBILITY SERVICE ALERT (without this, YouTube always defaults
  // to "entertainment" regardless of content — the video title can't be
  // read to check for educational keywords)
  // ============================================================

  Future<void> _checkAccessibilitySetup() async {
    bool granted;
    try {
      granted = await SensorDataService.hasAccessibilityAccess();
    } catch (e) {
      return;
    }
    if (granted || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Row(
          children: [
            Icon(Icons.smart_display_rounded, color: _green),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enable YouTube Classification',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'TruthLens reads YouTube video titles to tell educational '
          'content from entertainment. Without this, YouTube time always '
          'counts as entertainment, even lectures.',
          style: TextStyle(color: _textSecondary, height: 1.4, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later', style: TextStyle(color: _textMuted)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              SensorDataService.openAccessibilitySettings();
            },
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: _background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Open Settings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LOCATION SETUP ALERT (untouched logic, restyled dialog)
  // ============================================================

  Future<void> _checkLocationsSetup() async {
    Map<String, dynamic> locations;
    try {
      locations = await LocationService.getUserLocations(AppState.userId);
    } catch (e) {
      // Can't reach the server to check — skip the prompt rather than
      // crash with an unhandled exception; _loadData()'s own error
      // handling covers the main screen state.
      return;
    }
    if (locations.isEmpty && mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.location_off_outlined, color: _orange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Set up your locations',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'You haven\'t saved any reference locations yet (Home, Library, etc.). '
            'Without them, TruthLens can\'t verify your claimed location — '
            'it will always show as "Unknown".',
            style: TextStyle(color: _textSecondary, height: 1.4, fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later', style: TextStyle(color: _textMuted)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyLocationsScreen(userId: AppState.userId),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: _background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Set Up Now',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ============================================================
  // ORIGINAL DATA LOADING (untouched)
  // ============================================================

  Future<void> _loadData() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/bias/history/${AppState.userId}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['history'] as List? ?? [];

        history.sort((a, b) {
          final aId = a['entry_id']?.toString() ?? '';
          final bId = b['entry_id']?.toString() ?? '';

          final aTime = int.tryParse(aId.replaceAll('ENT_', '')) ?? 0;
          final bTime = int.tryParse(bId.replaceAll('ENT_', '')) ?? 0;

          return bTime.compareTo(aTime);
        });

        if (history.isNotEmpty) {
          final latest = history[0] as Map<String, dynamic>;
          final comparison = latest['comparison'] as Map? ?? {};
          final primaryBias = latest['primary_bias'] as Map? ?? {};

          double total = 0;
          for (var e in history) {
            total += (e['pas_score'] ?? 0);
          }

          if (!mounted) return;

          setState(() {
            _latestEntry = latest;
            _latestPas = latest['pas_score'] ?? 0;
            _pasLevel = latest['pas_level'] ?? '';
            _biasType = primaryBias['bias_type'] ?? '';
            _claimedDuration = comparison['claimed_duration'] ?? 0;
            _verifiedEdu = comparison['verified_educational'] ?? 0;
            _appSwitches = comparison['app_switches'] ?? 0;
            _socialMedia = comparison['social_media_minutes'] ?? 0;
            _claimedLocation = comparison['claimed_location'] ?? '';
            _actualLocation = comparison['actual_location'] ?? '';
            _moodBefore = comparison['mood_before'] ?? '';
            _moodAfter = comparison['mood_after'] ?? '';
            _reflectionText = latest['reflection_text'] ?? '';
            _weeklyAvg = total / history.length;
            _recentEntries = history
                .take(5)
                .map((e) => e as Map<String, dynamic>)
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool isAccurate =
        _biasType == 'accurate_perception' || _latestPas >= 70;

    final Color pasColor = isAccurate
        ? _green
        : _latestPas >= 50
        ? _orange
        : _red;

    return Scaffold(
      backgroundColor: _background,
      extendBody: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -1.1),
            radius: 1.4,
            colors: [Color(0x3335E47B), Colors.transparent],
            stops: [0.0, 0.58],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.1, -0.9),
              radius: 1.3,
              colors: [Color(0x2455CFE0), Colors.transparent],
              stops: [0.0, 0.55],
            ),
          ),
          child: _isLoading
          ? _buildSkeletonLoading()
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _green,
              backgroundColor: _surface2,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ==========================================================
                  // MODERN HEADER
                  // ==========================================================

                  SliverAppBar(
                    pinned: true,
                    elevation: 0,
                    toolbarHeight: 82,
                    automaticallyImplyLeading: false,
                    backgroundColor: _background.withOpacity(0.97),
                    surfaceTintColor: Colors.transparent,
                    titleSpacing: 18,
                    title: Row(
                      children: [
                        Container(
                          width: 43,
                          height: 43,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _green.withValues(alpha: 0.28),
                                _green.withValues(alpha: 0.08),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: _green.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(
                            Icons.visibility_rounded,
                            color: _green,
                            size: 21,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Good morning',
                                style: TextStyle(
                                  color: _textSecondary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppState.userId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: _textPrimary,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // My Locations
                        _topButton(
                          icon: Icons.location_on_rounded,
                          accent: _cyan,
                          glyph: _locationGlyph(_cyan),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MyLocationsScreen(userId: AppState.userId),
                              ),
                            );
                          },
                        ),

                        const SizedBox(width: 9),

                        // Notification
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _topButton(
                              icon: Icons.notifications_active_rounded,
                              accent: _orange,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RecommendationsScreen(),
                                  ),
                                );
                              },
                            ),
                            if (_recentEntries.isNotEmpty)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _background,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _green.withValues(alpha: 0.6),
                                        blurRadius: 6,
                                        spreadRadius: 0.5,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(width: 9),

                        // Profile
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProfileScreen(),
                              ),
                            );
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _green.withValues(alpha: 0.30),
                                  _cyan.withValues(alpha: 0.16),
                                ],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _green.withValues(alpha: 0.4),
                                width: 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _green.withValues(alpha: 0.22),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              AppState.userId.isNotEmpty
                                  ? AppState.userId[0].toUpperCase()
                                  : 'U',
                              style: GoogleFonts.outfit(
                                color: _green,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ==========================================================
                  // MAIN CONTENT
                  // ==========================================================

                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 135),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // SCORE
                        _animatedSection(
                          delay: 0,
                          child: _recentEntries.isEmpty
                              ? _emptyStateCard()
                              : _buildPasScoreCard(pasColor),
                        ),

                        if (_recentEntries.isNotEmpty) ...[
                          const SizedBox(height: 32),

                          // ACTIVITY
                          _animatedSection(
                            delay: 80,
                            child: _sectionHeader(
                              title: 'Today\'s activity',
                              subtitle:
                                  'A quick snapshot of your verified behavior',
                            ),
                          ),
                          const SizedBox(height: 15),
                          _animatedSection(
                            delay: 120,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    label: 'Duration gap',
                                    value:
                                        '${_claimedDuration - _verifiedEdu} min',
                                    accent: _red,
                                    band: _durationGapBand(),
                                    trend: _durationGapTrend(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    label: 'App switches',
                                    value: '$_appSwitches',
                                    accent: _orange,
                                    band: _appSwitchesBand(),
                                    trend: _appSwitchesTrend(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _animatedSection(
                            delay: 160,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    label: 'Social media',
                                    value: '$_socialMedia min',
                                    accent: _cyan,
                                    band: _socialMediaBand(),
                                    trend: _socialMediaTrend(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    label: 'Weekly SAS',
                                    value: _weeklyAvg.toStringAsFixed(0),
                                    accent: _green,
                                    band: _weeklySasBand(),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // CLAIMED VS REALITY
                          _animatedSection(
                            delay: 200,
                            child: _sectionHeader(
                              title: 'Claimed vs reality',
                              subtitle:
                                  'Compare what you remembered with verified data',
                            ),
                          ),
                          const SizedBox(height: 15),
                          _animatedSection(
                            delay: 240,
                            child: _buildRealityCard(),
                          ),

                          const SizedBox(height: 18),

                          // LATEST BIAS
                          _animatedSection(
                            delay: 280,
                            child: _buildBiasSummary(pasColor, isAccurate),
                          ),

                          if (_reflectionText.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _animatedSection(
                              delay: 320,
                              child: _buildReflectionCard(),
                            ),
                          ],
                        ],

                        const SizedBox(height: 34),

                        // RECENT ENTRIES
                        _animatedSection(
                          delay: 360,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Recent entries',
                                      style: GoogleFonts.outfit(
                                        color: _textPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Your latest TruthLens sessions',
                                      style: TextStyle(
                                        color: _textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const all_entries
                                          .AllEntriesScreen(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'See all',
                                  style: TextStyle(
                                    color: _green,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        _recentEntries.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Text(
                                    'No entries yet',
                                    style: TextStyle(
                                      color: _textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              )
                            : Column(
                                children: _recentEntries
                                    .asMap()
                                    .entries
                                    .map(
                                      (item) => _animatedSection(
                                        delay: 380 + (item.key * 50),
                                        child: _buildEntryCard(item.value),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
        ),
      ),

      // ============================================================
      // FLOATING PREMIUM NAVIGATION (same destinations/actions as before,
      // merged with the "New entry" action into one glass pill)
      // ============================================================

      bottomNavigationBar: _buildFloatingNav(context),
    );
  }

  Widget _buildFloatingNav(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _surface2.withValues(alpha: 0.94),
              _surface.withValues(alpha: 0.94),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navItem(
              icon: Icons.home_rounded,
              label: 'Home',
              selected: true,
              onTap: () {},
            ),
            _navItem(
              icon: Icons.menu_book_outlined,
              label: 'Diary',
              selected: false,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BiasFormScreen()),
                ).then((_) => _loadData());
              },
            ),
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FacialCaptureScreen()),
                ).then((_) => _loadData());
              },
              child: Container(
                width: 52,
                height: 52,
                margin: const EdgeInsets.only(top: 0),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6FE07E), _green, _cyan],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _green.withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Color(0xFF04231A),
                  size: 24,
                ),
              ),
            ),
            _navItem(
              icon: Icons.insights_outlined,
              label: 'Trends',
              selected: false,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WeeklyTrendsScreen(),
                  ),
                );
              },
            ),
            _navItem(
              icon: Icons.person_outline_rounded,
              label: 'Profile',
              selected: false,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected ? _green : _textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? _green.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // SUBTLE ENTRANCE ANIMATION
  // ================================================================

  Widget _animatedSection({required Widget child, int delay = 0}) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, animatedChild) {
        final opacity = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }

  // ================================================================
  // TOP BUTTON
  // ================================================================

  Widget _topButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? accent,
    Widget? glyph,
  }) {
    final tint = accent ?? Colors.white.withValues(alpha: 0.7);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: accent == null ? 0.08 : 0.18),
                tint.withValues(alpha: accent == null ? 0.02 : 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tint.withValues(alpha: accent == null ? 0.09 : 0.28)),
          ),
          child: glyph ?? Icon(icon, color: accent ?? _textPrimary, size: 19),
        ),
      ),
    );
  }

  /// The standard pin glyph plus a hand-drawn ground-shadow ellipse
  /// beneath it, so it reads as a "location marker on a map" rather than
  /// a bare teardrop — matches the reference icon's pin-with-base look
  /// without needing an external icon asset.
  Widget _locationGlyph(Color color) {
    return SizedBox(
      width: 24,
      height: 22,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: SizedBox(
              width: 16,
              height: 5,
              child: CustomPaint(
                painter: _GroundRingPainter(color.withValues(alpha: 0.85)),
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: Icon(Icons.location_on_rounded, size: 19, color: color),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // SECTION HEADER
  // ================================================================

  Widget _sectionHeader({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            color: _textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ================================================================
  // SCORE CARD
  // ================================================================

  Widget _buildPasScoreCard(Color pasColor) {
    final double progress = (_latestPas / 100).clamp(0.0, 1.0).toDouble();

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        final animatedScore = (animatedValue * 100).round();

        return TiltCard(
          borderRadius: BorderRadius.circular(26),
          child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: _glassDecoration(radius: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SELF-AWARENESS SCORE',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _overviewLabel,
                            maxLines: 1,
                            style: GoogleFonts.outfit(
                              color: _textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Builder(builder: (context) {
                    final levelColor = _levelColor(_pasLevel, pasColor);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            levelColor.withValues(alpha: 0.22),
                            levelColor.withValues(alpha: 0.10),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: levelColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _pasLevel.isEmpty ? 'Analyzed' : _pasLevel,
                        style: GoogleFonts.outfit(
                          color: levelColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const SizedBox(
                          width: 140,
                          height: 140,
                          child: CustomPaint(painter: RingTicksPainter()),
                        ),
                        SizedBox(
                          width: 104,
                          height: 104,
                          child: CustomPaint(
                            painter: GradientRingPainter(
                              progress: animatedValue,
                              colors: [pasColor.withValues(alpha: 0.75), pasColor],
                              strokeWidth: 8.5,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$animatedScore',
                              style: GoogleFonts.outfit(
                                color: pasColor,
                                fontSize: 38,
                                height: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'out of 100',
                              style: TextStyle(
                                color: _textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 21),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.035),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Perception',
                            style: TextStyle(color: _textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _formatBiasType(_biasType),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 12.5,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            'Weekly average',
                            style: TextStyle(color: _textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${_weeklyAvg.toStringAsFixed(0)} / 100',
                            style: const TextStyle(
                              color: _green,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.025),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _latestPas >= 70
                      ? 'Your perception closely matches verified activity today.'
                      : 'TruthLens detected differences between your perception and verified activity.',
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  // ================================================================
  // STAT CARD
  // ================================================================

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color accent,
    required ({String label, Color color}) band,
    ({String text, bool increased, bool favorable})? trend,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 29,
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: _textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: band.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                band.label,
                style: TextStyle(
                  color: band.color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          if (trend != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  trend.increased
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 10,
                  color: trend.favorable ? _green : _red,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    trend.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: trend.favorable ? _green : _red,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ================================================================
  // STAT CARD — semantic bands
  //
  // Each band reuses a formula/threshold already computed elsewhere in
  // the pipeline (comparator.py's duration_match_ratio, focus_quality_score
  // and activity_match, or this screen's own 70/50 PAS cutoffs) rather
  // than inventing new ones just for display.
  // ================================================================

  ({String label, Color color}) _durationGapBand() {
    final ratio = _claimedDuration > 0 ? (_verifiedEdu / _claimedDuration) : 1.0;
    if (ratio >= 0.8) return (label: 'GOOD', color: _green);
    if (ratio >= 0.5) return (label: 'MODERATE', color: _orange);
    return (label: 'HIGH', color: _red);
  }

  ({String label, Color color}) _appSwitchesBand() {
    final focus = (1 - (_appSwitches / 80)).clamp(0.0, 1.0);
    if (focus >= 0.8) return (label: 'GOOD', color: _green);
    if (focus >= 0.5) return (label: 'MODERATE', color: _orange);
    return (label: 'HIGH', color: _red);
  }

  ({String label, Color color}) _socialMediaBand() {
    return _verifiedEdu > _socialMedia
        ? (label: 'GOOD', color: _green)
        : (label: 'ABOVE STUDY', color: _red);
  }

  ({String label, Color color}) _weeklySasBand() {
    if (_weeklyAvg >= 70) return (label: 'GOOD', color: _green);
    if (_weeklyAvg >= 50) return (label: 'MODERATE', color: _orange);
    return (label: 'HIGH', color: _red);
  }

  /// The entry right before the latest one, if there is one — used to
  /// compute trend deltas without any extra API call.
  Map<String, dynamic>? get _previousComparison {
    if (_recentEntries.length < 2) return null;
    final comparison = _recentEntries[1]['comparison'];
    return comparison is Map ? Map<String, dynamic>.from(comparison) : null;
  }

  ({String text, bool increased, bool favorable})? _durationGapTrend() {
    final prev = _previousComparison;
    if (prev == null) return null;
    final prevGap = ((prev['claimed_duration'] as num?)?.toInt() ?? 0) -
        ((prev['verified_educational'] as num?)?.toInt() ?? 0);
    final currentGap = _claimedDuration - _verifiedEdu;
    final delta = currentGap - prevGap;
    if (delta == 0) return null;
    return (
      text: '${delta.abs()} min vs last entry',
      increased: delta > 0,
      favorable: delta < 0, // a smaller gap is the improvement
    );
  }

  ({String text, bool increased, bool favorable})? _appSwitchesTrend() {
    final prev = _previousComparison;
    if (prev == null) return null;
    final prevSwitches = (prev['app_switches'] as num?)?.toInt() ?? 0;
    final delta = _appSwitches - prevSwitches;
    if (delta == 0) return null;
    return (
      text: '${delta.abs()} vs last entry',
      increased: delta > 0,
      favorable: delta < 0,
    );
  }

  ({String text, bool increased, bool favorable})? _socialMediaTrend() {
    final prev = _previousComparison;
    if (prev == null) return null;
    final prevSocial = (prev['social_media_minutes'] as num?)?.toInt() ?? 0;
    final delta = _socialMedia - prevSocial;
    if (delta == 0) return null;
    return (
      text: '${delta.abs()} min vs last entry',
      increased: delta > 0,
      favorable: delta < 0,
    );
  }

  // ================================================================
  // REALITY CHECK
  // ================================================================

  Widget _buildRealityCard() {
    return TiltCard(
      borderRadius: BorderRadius.circular(23),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(23),
        child: InkWell(
          borderRadius: BorderRadius.circular(23),
          onTap: _latestEntry == null ? null : () => _openLatestAnalysis(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: _glassDecoration(radius: 23),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reality check',
                  style: GoogleFonts.outfit(
                    color: _textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                _buildCompareRow(
                  label: 'Location',
                  claimed: _claimedLocation,
                  actual: _actualLocation,
                ),
                _cardDivider(),
                _buildCompareRow(
                  label: 'Study duration',
                  claimed: '$_claimedDuration min',
                  actual: '$_verifiedEdu min',
                ),
                _cardDivider(),
                _buildCompareRow(
                  label: 'Mood shift',
                  claimed: _moodBefore,
                  actual: _moodAfter,
                ),
                _tapHintRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Navigates to the full breakdown for the latest entry — the same
  /// destination the Reflection card's "View full analysis" link already
  /// opens, so tappable summary cards never duplicate that screen's detail.
  void _openLatestAnalysis() {
    if (_latestEntry == null) return;
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BiasResultScreen(result: _latestEntry!)),
    );
  }

  /// A quiet tap affordance for cards that navigate to Bias Result —
  /// just a chevron, no "View full analysis" text. That phrase already
  /// appears once on this screen (the Reflection card's own button);
  /// repeating it on every tappable card read as clutter.
  Widget _tapHintRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildCompareRow({
    required String label,
    required String claimed,
    required String actual,
  }) {
    final bool isGood = claimed.toLowerCase() == actual.toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textSecondary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _compareValue(
                title: 'CLAIMED',
                value: claimed,
                color: _cyan,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 9),
              child: Text(
                '→',
                style: TextStyle(color: _textMuted, fontSize: 20),
              ),
            ),
            Expanded(
              child: _compareValue(
                title: 'VERIFIED',
                value: actual,
                color: isGood ? _green : _red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _compareValue({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color.withValues(alpha: 0.82),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value.isEmpty ? 'Unknown' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withOpacity(0.045),
      ),
    );
  }

  // ================================================================
  // BIAS CARD
  // ================================================================

  Widget _buildBiasSummary(Color pasColor, bool isAccurate) {
    return TiltCard(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _latestEntry == null ? null : () => _openLatestAnalysis(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 17),
            decoration: _glassDecoration(radius: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Latest bias',
                            style: TextStyle(color: _textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _formatBiasType(_biasType),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: _textPrimary,
                              fontSize: 16.5,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            pasColor.withValues(alpha: 0.2),
                            pasColor.withValues(alpha: 0.09),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: pasColor.withValues(alpha: 0.28)),
                      ),
                      child: Text(
                        isAccurate ? 'Accurate' : 'Detected',
                        style: TextStyle(
                          color: pasColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                _tapHintRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // REFLECTION CARD
  // ================================================================

  Widget _buildReflectionCard() {
    return TiltCard(
      borderRadius: BorderRadius.circular(23),
      child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_green.withValues(alpha: 0.09), Colors.white.withValues(alpha: 0.02)],
        ),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: _green.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TruthLens reflection',
            style: GoogleFonts.outfit(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Personalized analysis',
            style: TextStyle(color: _textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 15),
          Text(
            _reflectionText.length > 170
                ? '${_reflectionText.substring(0, 170)}...'
                : _reflectionText,
            style: const TextStyle(
              color: _textSecondary,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 13),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: _green,
            ),
            onPressed: () {
              if (_latestEntry != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BiasResultScreen(result: _latestEntry!),
                  ),
                );
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View full analysis',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 5),
                const Icon(Icons.arrow_forward_rounded, size: 15),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ================================================================
  // ENTRY CARD
  // ================================================================

  Widget _buildEntryCard(Map<String, dynamic> entry) {
    final pas = entry['pas_score'] ?? 0;
    final bias = entry['primary_bias']?['bias_type'] ?? '';
    final bool isAccurate = bias == 'accurate_perception' || pas >= 70;
    final Color color = isAccurate
        ? _green
        : pas >= 50
        ? _orange
        : _red;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BiasResultScreen(result: entry)),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: _glassDecoration(radius: 18),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatBiasType(bias),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: _textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'TruthLens analysis',
                        style: TextStyle(
                          color: _textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    '$pas',
                    style: GoogleFonts.outfit(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // EMPTY STATE
  // ================================================================

  Widget _emptyStateCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 30, 22, 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111A27), Color(0xFF0D151F)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PulsingGlowIcon(color: _green),
          const SizedBox(height: 18),
          const Text(
            'Start your first entry',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Track your perception and compare it with verified activity.',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BiasFormScreen()),
              ).then((_) => _loadData());
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6FE07E), _green, _cyan],
                ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'Start now',
                  style: GoogleFonts.outfit(
                    color: _background,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // SKELETON LOADING
  // ================================================================

  Widget _buildSkeletonLoading() {
    Widget box({double height = 20, double? width, double radius = 14}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return _ShimmerSweep(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          18,
          MediaQuery.of(context).padding.top + 100,
          18,
          40,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            box(height: 230, width: double.infinity, radius: 26),
            const SizedBox(height: 32),
            box(height: 22, width: 160),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: box(height: 118, radius: 19)),
                const SizedBox(width: 12),
                Expanded(child: box(height: 118, radius: 19)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: box(height: 118, radius: 19)),
                const SizedBox(width: 12),
                Expanded(child: box(height: 118, radius: 19)),
              ],
            ),
            const SizedBox(height: 32),
            box(height: 22, width: 180),
            const SizedBox(height: 15),
            box(height: 220, width: double.infinity, radius: 23),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // FORMAT BIAS TYPE
  // ================================================================

  /// Colors the PAS-level badge from the *same* level text it's showing,
  /// instead of a separately-computed numeric threshold — so a badge that
  /// says "Moderate Bias" never renders in the same red used for "Severe
  /// Bias" elsewhere. Falls back to [fallback] for an empty/unknown level.
  Color _levelColor(String level, Color fallback) {
    switch (level) {
      case 'Excellent Alignment':
      case 'Good Alignment':
        return _green;
      case 'Mild Bias':
        return _orange;
      case 'Moderate Bias':
        return const Color(0xFFFF8A50);
      case 'Severe Bias':
        return _red;
      default:
        return fallback;
    }
  }

  /// "Today's overview" only when the latest entry is actually from
  /// today — otherwise says which day it's really from, so the score
  /// card never implies fresher data than it's showing.
  String get _overviewLabel {
    if (_latestEntry == null) return "Today's overview";
    final entryId = _latestEntry!['entry_id']?.toString() ?? '';
    final ts = int.tryParse(entryId.replaceAll('ENT_', ''));
    if (ts == null) return "Today's overview";

    final entryDate = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entryDay = DateTime(entryDate.year, entryDate.month, entryDate.day);
    final diffDays = today.difference(entryDay).inDays;

    if (diffDays == 0) return "Today's overview";
    if (diffDays == 1) return "Yesterday's overview";

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[entryDate.month - 1]} ${entryDate.day} overview';
  }

  String _formatBiasType(String type) {
    if (type.isEmpty || type == 'accurate_perception') {
      return 'Accurate Perception';
    }
    return type
        .split('_')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
        .join(' ');
  }
}

/// A small icon badge with a slow, continuous breathing glow — used on the
/// empty state so the very first thing a new student sees still feels
/// alive rather than static.
class _PulsingGlowIcon extends StatefulWidget {
  final Color color;
  const _PulsingGlowIcon({required this.color});

  @override
  State<_PulsingGlowIcon> createState() => _PulsingGlowIconState();
}

class _PulsingGlowIconState extends State<_PulsingGlowIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.18 + 0.20 * t),
                blurRadius: 18 + 14 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Icon(Icons.visibility_rounded, color: widget.color, size: 26),
    );
  }
}

/// A thin elliptical ring — the "ground shadow" drawn beneath the
/// location-pin glyph in the top bar.
class _GroundRingPainter extends CustomPainter {
  final Color color;
  _GroundRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawOval(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _GroundRingPainter old) => old.color != color;
}

/// Sweeps a soft diagonal highlight across [child] on a loop — used to
/// turn flat skeleton placeholder boxes into a recognizable "loading"
/// shimmer instead of a plain static grey block.
class _ShimmerSweep extends StatefulWidget {
  final Widget child;
  const _ShimmerSweep({required this.child});

  @override
  State<_ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<_ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dx = -1.5 + 3.0 * _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(dx - 0.6, -0.3),
              end: Alignment(dx + 0.6, 0.3),
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}