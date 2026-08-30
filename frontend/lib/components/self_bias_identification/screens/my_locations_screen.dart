import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/location_service.dart';
import 'add_location_screen.dart';

/// Shows the student's saved reference locations (Home, Library, etc.)
/// Reached from Settings/Home screen — not part of the daily diary form.
class MyLocationsScreen extends StatefulWidget {
  final String userId;

  const MyLocationsScreen({
    super.key,
    required this.userId,
  });

  @override
  State<MyLocationsScreen> createState() => _MyLocationsScreenState();
}

class _MyLocationsScreenState extends State<MyLocationsScreen> {
  // ============================================================
  // TRUTHLENS DESIGN SYSTEM
  // ============================================================

  static const Color _background = Color(0xFF070B12);

  static const Color _surface2 = Color(0xFF111A27);
  static const Color _surface3 = Color(0xFF16202D);

  static const Color _green = Color(0xFF35E47B);
  static const Color _greenSoft = Color(0xFF153A27);

  static const Color _cyan = Color(0xFF55CFE0);

  static const Color _red = Color(0xFFFF6977);

  static const Color _textPrimary = Color(0xFFF4F7FB);
  static const Color _textSecondary = Color(0xFFA5AFBE);
  static const Color _textMuted = Color(0xFF738093);

  // ============================================================
  // ORIGINAL DATA
  // ============================================================

  Map<String, dynamic> _locations = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  // ============================================================
  // ORIGINAL LOAD FUNCTION
  // ============================================================

  Future<void> _loadLocations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await LocationService.getUserLocations(widget.userId);
      if (!mounted) return;
      setState(() {
        _locations = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not reach the server. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  // ============================================================
  // ORIGINAL DELETE FUNCTION
  // ============================================================

  Future<void> _deleteLocation(String name) async {
    await LocationService.deleteLocation(
      widget.userId,
      name,
    );

    _loadLocations();
  }

  // ============================================================
  // ORIGINAL ADD LOCATION NAVIGATION
  // ============================================================

  Future<void> _goToAddLocation() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddLocationScreen(
          userId: widget.userId,
        ),
      ),
    );

    if (saved == true) {
      _loadLocations();
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,

      // ============================================================
      // APP BAR
      // ============================================================

      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        toolbarHeight: 82,
        titleSpacing: 18,

        title: Row(
          children: [
            _topButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () {
                Navigator.pop(context);
              },
            ),

            const SizedBox(width: 14),

            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Locations',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Manage your trusted reference places',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            _topButton(
              icon: Icons.refresh_rounded,
              iconColor: _green,
              onTap: _loadLocations,
            ),
          ],
        ),
      ),

      // ============================================================
      // BODY
      // ============================================================

      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.6, -1.1),
            radius: 1.3,
            colors: [_green.withOpacity(0.14), Colors.transparent],
            stops: const [0.0, 0.58],
          ),
        ),
      child: _loading
          ? _buildLoadingState()
          : _error != null
          ? _buildErrorState()
          : RefreshIndicator(
              color: _green,
              backgroundColor: _surface2,
              onRefresh: _loadLocations,

              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  18,
                  16,
                  18,
                  125,
                ),
                children: [
                  // ==================================================
                  // OVERVIEW
                  // ==================================================

                  _animatedSection(
                    delay: 0,
                    child: _buildOverviewCard(),
                  ),

                  const SizedBox(height: 30),

                  if (_locations.isEmpty)
                    _animatedSection(
                      delay: 100,
                      child: _EmptyState(
                        onAdd: _goToAddLocation,
                      ),
                    )
                  else ...[
                    // ================================================
                    // SECTION TITLE
                    // ================================================

                    _animatedSection(
                      delay: 90,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Saved locations',
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Places available for GPS verification',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _greenSoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_locations.length}',
                              style: const TextStyle(
                                color: _green,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 15),

                    // ================================================
                    // LOCATION LIST
                    // ================================================

                    ..._locations.entries.toList().asMap().entries.map(
                      (item) {
                        final entry = item.value;

                        final name = entry.key;

                        final value =
                            entry.value as Map<String, dynamic>;

                        return _animatedSection(
                          delay: 130 + (item.key * 60),
                          child: _buildLocationCard(
                            name,
                            value,
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
      ),

      // ============================================================
      // ADD LOCATION FAB
      // ============================================================

      floatingActionButton: GestureDetector(
        onTap: _goToAddLocation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6FE07E), _green, _cyan],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _green.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, size: 20, color: _background),
              const SizedBox(width: 8),
              Text(
                'Add location',
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _background,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SUBTLE ENTRANCE ANIMATION
  // ============================================================

  Widget _animatedSection({
    required Widget child,
    int delay = 0,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: 0,
        end: 1,
      ),
      duration: Duration(
        milliseconds: 420 + delay,
      ),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (
        context,
        value,
        animatedChild,
      ) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(
              0,
              12 * (1 - value),
            ),
            child: animatedChild,
          ),
        );
      },
    );
  }

  // ============================================================
  // TOP BUTTON
  // ============================================================

  Widget _topButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = _textPrimary,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: Colors.white.withOpacity(0.055),
            ),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 19,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // LOADING
  // ============================================================

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: _green,
            strokeWidth: 3,
          ),
          SizedBox(height: 16),
          Text(
            'Loading locations...',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: _red.withOpacity(0.7),
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadLocations,
              style: FilledButton.styleFrom(
                backgroundColor: _greenSoft,
                foregroundColor: _green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // OVERVIEW CARD
  // ============================================================

  Widget _buildOverviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF121C2A),
            Color(0xFF0D151F),
          ],
        ),

        borderRadius: BorderRadius.circular(22),

        border: Border.all(
          color: Colors.white.withOpacity(0.055),
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),

              const Spacer(),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _greenSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_locations.length} saved',
                  style: const TextStyle(
                    color: _green,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          Text(
            'Trusted places',
            style: GoogleFonts.outfit(
              color: _textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'TruthLens uses these locations to compare your claimed place with verified GPS activity.',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 22),

          Row(
            children: [
              Expanded(
                child: _overviewMetric(
                  title: 'Verification',
                  value: 'Enabled',
                  accent: _green,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _overviewMetric(
                  title: 'Saved places',
                  value: '${_locations.length}',
                  accent: _cyan,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // OVERVIEW METRIC
  // ============================================================

  Widget _overviewMetric({
    required String title,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.025),
        borderRadius: BorderRadius.circular(15),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(100),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            title,
            style: const TextStyle(
              color: _textMuted,
              fontSize: 11.5,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            value,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LOCATION CARD
  // ============================================================

  Widget _buildLocationCard(
    String name,
    Map<String, dynamic> value,
  ) {
    final lat = value['lat'] as num;
    final lng = value['lng'] as num;
    final radius = value['radius_m'];

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),

      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),

        child: Container(
          width: double.infinity,

          padding: const EdgeInsets.all(16),

          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.06),
                Colors.white.withOpacity(0.015),
              ],
            ),
            borderRadius: BorderRadius.circular(18),

            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),

          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 47,
                height: 47,
                decoration: BoxDecoration(
                  color: _surface3,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _getLocationIcon(name),
                  color: _cyan,
                  size: 21,
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _greenSoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: _green,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      '$radius m verification radius',
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 9),

              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    _deleteLocation(name);
                  },
                  child: Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      color: _red.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: _red,
                      size: 18,
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

  // ============================================================
  // SMART LOCATION ICON
  // ============================================================

  IconData _getLocationIcon(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('home')) {
      return Icons.home_outlined;
    }

    if (lower.contains('library')) {
      return Icons.local_library_outlined;
    }

    if (lower.contains('lecture') ||
        lower.contains('class') ||
        lower.contains('hall')) {
      return Icons.school_outlined;
    }

    if (lower.contains('office') ||
        lower.contains('work')) {
      return Icons.work_outline_rounded;
    }

    if (lower.contains('gym')) {
      return Icons.fitness_center_rounded;
    }

    if (lower.contains('cafe') ||
        lower.contains('coffee')) {
      return Icons.local_cafe_outlined;
    }

    return Icons.place_outlined;
  }
}

// ================================================================
// EMPTY STATE
// ================================================================

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({
    required this.onAdd,
  });

  static const Color _surface = Color(0xFF0D131D);

  static const Color _green = Color(0xFF35E47B);
  static const Color _greenSoft = Color(0xFF153A27);

  static const Color _textPrimary = Color(0xFFF4F7FB);
  static const Color _textSecondary = Color(0xFFA5AFBE);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.fromLTRB(
        24,
        34,
        24,
        30,
      ),

      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),

      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _greenSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.location_off_outlined,
              color: _green,
              size: 27,
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'No locations yet',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Add Home, Library, Lecture Hall, or another trusted place so TruthLens can verify your claimed location.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor:
                    const Color(0xFF070B12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                'Add your first location',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}