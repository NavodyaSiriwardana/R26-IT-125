import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import 'map_picker_screen.dart';

/// Student stands at the actual place (Library, Home, etc.) and taps
/// "Capture Current Location" to save it as a reference point — or,
/// for places they aren't currently at (like a shop while at home),
/// switches to "Enter manually" and types coordinates copied from a
/// maps app.
class AddLocationScreen extends StatefulWidget {
  final String userId;

  const AddLocationScreen({
    super.key,
    required this.userId,
  });

  @override
  State<AddLocationScreen> createState() => _AddLocationScreenState();
}

class _AddLocationScreenState extends State<AddLocationScreen> {
  // ============================================================
  // TRUTHLENS DESIGN SYSTEM
  // ============================================================

  static const Color _background = Color(0xFF070B12);

  static const Color _surface = Color(0xFF0D131D);
  static const Color _surface2 = Color(0xFF111A27);
  static const Color _surface3 = Color(0xFF16202D);

  static const Color _green = Color(0xFF35E47B);
  static const Color _greenSoft = Color(0xFF153A27);

  static const Color _cyan = Color(0xFF55CFE0);
  static const Color _cyanSoft = Color(0xFF102A31);

  static const Color _orange = Color(0xFFF4B653);
  static const Color _red = Color(0xFFFF6977);

  static const Color _textPrimary = Color(0xFFF4F7FB);
  static const Color _textSecondary = Color(0xFFA5AFBE);
  static const Color _textMuted = Color(0xFF738093);

  // ============================================================
  // ORIGINAL VARIABLES
  // ============================================================

  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  double _radius = 60;

  bool _manualMode = false; // false = GPS capture, true = type coordinates

  Position? _capturedPosition;

  bool _capturing = false;
  bool _saving = false;

  String? _error;

  // ============================================================
  // ORIGINAL CAPTURE FUNCTION
  // ============================================================

  Future<void> _captureLocation() async {
    setState(() {
      _capturing = true;
      _error = null;
    });

    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final requested = await Geolocator.requestPermission();

        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          if (!mounted) return;

          setState(() {
            _error =
                'Location permission is required to capture a point.';
            _capturing = false;
          });

          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      setState(() {
        _capturedPosition = position;
        _capturing = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Could not get GPS location: $e';
        _capturing = false;
      });
    }
  }

  // ============================================================
  // NEW: MAP PICKER LAUNCH
  // ============================================================

  Future<void> _pickOnMap() async {
    LatLng? initial;
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    if (lat != null && lng != null) {
      initial = LatLng(lat, lng);
    }

    final result = await Navigator.push<MapPickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(initialPosition: initial),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _latController.text = result.position.latitude.toStringAsFixed(6);
        _lngController.text = result.position.longitude.toStringAsFixed(6);
        // Only auto-fill the name if the student hasn't typed one already,
        // so we never overwrite something they've deliberately entered.
        if (result.suggestedName != null &&
            _nameController.text.trim().isEmpty) {
          _nameController.text = result.suggestedName!;
        }
        _error = null;
      });
    }
  }

  // ============================================================
  // ORIGINAL SAVE FUNCTION (extended with manual-entry branch)
  // ============================================================

  Future<void> _save() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _error = 'Please enter a location name.';
      });
      return;
    }

    double? lat;
    double? lng;

    if (_manualMode) {
      lat = double.tryParse(_latController.text.trim());
      lng = double.tryParse(_lngController.text.trim());

      if (lat == null || lng == null) {
        setState(() {
          _error =
              'Enter valid latitude and longitude numbers (e.g. 6.9147, 79.9724).';
        });
        return;
      }

      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        setState(() {
          _error = 'Latitude must be -90 to 90, longitude -180 to 180.';
        });
        return;
      }
    } else {
      if (_capturedPosition == null) {
        setState(() {
          _error =
              'Please capture the current location first.';
        });
        return;
      }
      lat = _capturedPosition!.latitude;
      lng = _capturedPosition!.longitude;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await LocationService.saveLocation(
        userId: widget.userId,
        name: name,
        lat: lat,
        lng: lng,
        radiusMeters: _radius,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save location. Check your connection and try again.';
      });
    }
  }

  /// Whether a usable coordinate pair currently exists, regardless of
  /// which mode is active — used by the header card so it doesn't only
  /// track the GPS-capture path and ignore manual/map-picked entry.
  bool get _hasValidCoordinates {
    if (_manualMode) {
      final lat = double.tryParse(_latController.text.trim());
      final lng = double.tryParse(_lngController.text.trim());
      return lat != null && lng != null;
    }
    return _capturedPosition != null;
  }

  @override
  void initState() {
    super.initState();
    _latController.addListener(_onManualCoordsChanged);
    _lngController.addListener(_onManualCoordsChanged);
  }

  void _onManualCoordsChanged() {
    if (_manualMode) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
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
                    'Add Location',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Create a trusted GPS reference',
                    style: TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
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
      child: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            18,
            16,
            18,
            135,
          ),
          children: [
            _animatedSection(
              delay: 0,
              child: _buildHeaderCard(),
            ),

            const SizedBox(height: 32),

            _animatedSection(
              delay: 80,
              child: _buildSectionTitle(
                number: '1',
                title: 'Name this location',
                subtitle:
                    'Choose a clear name you will recognize later',
              ),
            ),

            const SizedBox(height: 14),

            _animatedSection(
              delay: 120,
              child: _buildNameInput(),
            ),

            const SizedBox(height: 32),

            _animatedSection(
              delay: 160,
              child: _buildSectionTitle(
                number: '2',
                title: 'Set the GPS reference',
                subtitle:
                    'Capture it while you\'re there, or enter it manually',
              ),
            ),

            const SizedBox(height: 14),

            // ==========================================================
            // NEW: mode toggle — Use current location / Enter manually
            // ==========================================================

            _animatedSection(
              delay: 190,
              child: _buildModeToggle(),
            ),

            const SizedBox(height: 14),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: _manualMode
                  ? Container(
                      key: const ValueKey('manual'),
                      child: _buildManualEntryCard(),
                    )
                  : Container(
                      key: const ValueKey('gps'),
                      child: _buildCaptureCard(),
                    ),
            ),

            AnimatedSwitcher(
              duration: const Duration(
                milliseconds: 350,
              ),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (
                child,
                animation,
              ) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                );
              },
              child: (!_manualMode && _capturedPosition != null)
                  ? Padding(
                      key: const ValueKey(
                        'captured',
                      ),
                      padding:
                          const EdgeInsets.only(
                        top: 12,
                      ),
                      child:
                          _buildCapturedCard(),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey(
                        'notCaptured',
                      ),
                    ),
            ),

            const SizedBox(height: 32),

            _animatedSection(
              delay: 240,
              child: _buildSectionTitle(
                number: '3',
                title: 'Set verification radius',
                subtitle:
                    'Choose how close GPS must be to count as this location',
              ),
            ),

            const SizedBox(height: 14),

            _animatedSection(
              delay: 280,
              child: _buildRadiusCard(),
            ),

            const SizedBox(height: 12),

            _animatedSection(
              delay: 320,
              child:
                  _buildRecommendationCard(),
            ),

            AnimatedSwitcher(
              duration: const Duration(
                milliseconds: 250,
              ),
              child: _error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey(_error),
                      padding:
                          const EdgeInsets.only(
                        top: 18,
                      ),
                      child: _buildErrorCard(),
                    ),
            ),
          ],
        ),
      ),
      ),

      // ============================================================
      // FIXED SAVE AREA
      // ============================================================

      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          12 +
              MediaQuery.of(context)
                  .padding
                  .bottom,
        ),
        decoration: BoxDecoration(
          color: _surface,
          border: Border(
            top: BorderSide(
              color: Colors.white
                  .withOpacity(0.055),
            ),
          ),
        ),
        child: Container(
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6FE07E), _green, _cyan],
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: _green.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),

          child: FilledButton(
            onPressed:
                _saving ? null : _save,

            style:
                FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor:
                  _background,

              disabledBackgroundColor:
                  Colors.transparent,

              disabledForegroundColor:
                  _background.withOpacity(
                0.6,
              ),

              elevation: 0,

              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(
                  15,
                ),
              ),
            ),

            child: AnimatedSwitcher(
              duration: const Duration(
                milliseconds: 200,
              ),
              child: _saving
                  ? const Row(
                      key: ValueKey(
                        'saving',
                      ),
                      mainAxisAlignment:
                          MainAxisAlignment
                              .center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color:
                                _background,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Saving location...',
                          style:
                              TextStyle(
                            fontSize:
                                13.5,
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
                      ],
                    )
                  : const Row(
                      key: ValueKey(
                        'save',
                      ),
                      mainAxisAlignment:
                          MainAxisAlignment
                              .center,
                      children: [
                        Icon(
                          Icons
                              .add_location_alt_rounded,
                          size: 19,
                        ),
                        SizedBox(width: 9),
                        Text(
                          'Save Location',
                          style:
                              TextStyle(
                            fontSize: 14,
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // NEW: MODE TOGGLE
  // ============================================================

  Widget _buildModeToggle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeTab(
              title: 'Use current location',
              selected: !_manualMode,
              onTap: () => setState(() => _manualMode = false),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _modeTab(
              title: 'Enter manually',
              selected: _manualMode,
              onTap: () => setState(() => _manualMode = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab({
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? _greenSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? _green : _textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // NEW: MANUAL ENTRY CARD
  // ============================================================

  Widget _buildManualEntryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Set coordinates',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Pick the spot on the map, or type coordinates copied from '
            'Google Maps.',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _pickOnMap,
              style: OutlinedButton.styleFrom(
                foregroundColor: _cyan,
                side: BorderSide(color: _cyan.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text(
                'Pick on map',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _coordField(_latController, 'Latitude', '6.9147')),
              const SizedBox(width: 10),
              Expanded(child: _coordField(_lngController, 'Longitude', '79.9724')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _coordField(TextEditingController controller, String label, String hint) {
    return Container(
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: TextField(
        controller: controller,
        cursorColor: _cyan,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: const TextStyle(
          color: _textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          labelText: label,
          labelStyle: const TextStyle(color: _textSecondary, fontSize: 12.5),
          floatingLabelStyle: const TextStyle(color: _cyan, fontSize: 12.5),
          hintText: hint,
          hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          opacity:
              value.clamp(0.0, 1.0),
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
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius:
            BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius:
                BorderRadius.circular(
              13,
            ),
            border: Border.all(
              color: Colors.white
                  .withOpacity(0.055),
            ),
          ),
          child: Icon(
            icon,
            color: _textPrimary,
            size: 19,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER CARD
  // ============================================================

  Widget _buildHeaderCard() {
    final bool captured = _hasValidCoordinates;

    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,

      width: double.infinity,
      padding:
          const EdgeInsets.all(20),

      decoration: BoxDecoration(
        gradient:
            const LinearGradient(
          begin: Alignment.topLeft,
          end:
              Alignment.bottomRight,
          colors: [
            Color(0xFF121C2A),
            Color(0xFF0D151F),
          ],
        ),

        borderRadius:
            BorderRadius.circular(22),

        border: Border.all(
          color: captured
              ? _green.withOpacity(
                  0.12,
                )
              : Colors.white
                  .withOpacity(
                  0.055,
                ),
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withOpacity(0.22),
            blurRadius: 26,
            offset:
                const Offset(0, 12),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 4,
                decoration:
                    BoxDecoration(
                  color: captured
                      ? _green
                      : _orange,
                  borderRadius:
                      BorderRadius
                          .circular(
                    100,
                  ),
                ),
              ),

              const Spacer(),

              AnimatedContainer(
                duration:
                    const Duration(
                  milliseconds: 300,
                ),

                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),

                decoration:
                    BoxDecoration(
                  color: captured
                      ? _greenSoft
                      : _orange
                          .withOpacity(
                          0.08,
                        ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    20,
                  ),
                ),

                child: Text(
                  captured
                      ? (_manualMode ? 'Location set' : 'GPS ready')
                      : (_manualMode ? 'Awaiting coordinates' : 'Waiting for GPS'),
                  style: TextStyle(
                    color: captured
                        ? _green
                        : _orange,
                    fontSize: 11.5,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          const Text(
            'Add a trusted place',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 24,
              fontWeight:
                  FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'TruthLens will use this GPS reference to verify locations in your future diary entries.',
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
                child: _headerMetric(
                  title: _manualMode ? 'Location status' : 'GPS status',
                  value: captured
                      ? (_manualMode ? 'Set' : 'Captured')
                      : (_manualMode ? 'Not set' : 'Not captured'),
                  accent: captured
                      ? _green
                      : _orange,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _headerMetric(
                  title:
                      'Match radius',
                  value:
                      '${_radius.toStringAsFixed(0)} m',
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
  // HEADER METRIC
  // ============================================================

  Widget _headerMetric({
    required String title,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding:
          const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color:
            Colors.white.withOpacity(
          0.025,
        ),
        borderRadius:
            BorderRadius.circular(15),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 3,
            decoration:
                BoxDecoration(
              color: accent,
              borderRadius:
                  BorderRadius.circular(
                100,
              ),
            ),
          ),

          const SizedBox(height: 11),

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
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 14.5,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _buildSectionTitle({
    required String number,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment:
              Alignment.center,

          decoration:
              BoxDecoration(
            color: _greenSoft,
            borderRadius:
                BorderRadius.circular(
              9,
            ),
          ),

          child: Text(
            number,
            style: const TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(
                  color: _textPrimary,
                  fontSize: 18,
                  fontWeight:
                      FontWeight.w700,
                  letterSpacing:
                      -0.2,
                ),
              ),

              const SizedBox(
                height: 4,
              ),

              Text(
                subtitle,
                style:
                    const TextStyle(
                  color:
                      _textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // NAME INPUT
  // ============================================================

  Widget _buildNameInput() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius:
            BorderRadius.circular(17),

        border: Border.all(
          color:
              Colors.white.withOpacity(
            0.055,
          ),
        ),
      ),

      child: TextField(
        controller:
            _nameController,

        cursorColor: _cyan,

        textInputAction:
            TextInputAction.done,

        style: const TextStyle(
          color: _textPrimary,
          fontSize: 15,
          fontWeight:
              FontWeight.w600,
        ),

        decoration:
            const InputDecoration(
          border: InputBorder.none,

          labelText:
              'Location name',

          labelStyle: TextStyle(
            color: _textSecondary,
            fontSize: 13,
          ),

          floatingLabelStyle:
              TextStyle(
            color: _cyan,
            fontSize: 13,
          ),

          hintText:
              'Library, Home, Shop, Lecture Hall A...',

          hintStyle: TextStyle(
            color: _textMuted,
            fontSize: 13,
          ),

          contentPadding:
              EdgeInsets.symmetric(
            horizontal: 17,
            vertical: 19,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CAPTURE CARD
  // ============================================================

  Widget _buildCaptureCard() {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(17),

      decoration: BoxDecoration(
        color: _surface,

        borderRadius:
            BorderRadius.circular(19),

        border: Border.all(
          color:
              Colors.white.withOpacity(
            0.055,
          ),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Current GPS position',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 16,
              fontWeight:
                  FontWeight.w700,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            'Location accuracy may vary when you are indoors.',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 17),

          SizedBox(
            width: double.infinity,
            height: 50,

            child:
                FilledButton.icon(
              onPressed: _capturing
                  ? null
                  : _captureLocation,

              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    _cyanSoft,
                foregroundColor:
                    _cyan,

                disabledBackgroundColor:
                    _surface3,

                disabledForegroundColor:
                    _textMuted,

                elevation: 0,

                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius
                          .circular(
                    14,
                  ),
                ),
              ),

              icon: _capturing
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child:
                          CircularProgressIndicator(
                        strokeWidth:
                            2.1,
                        color: _cyan,
                      ),
                    )
                  : Icon(
                      _capturedPosition ==
                              null
                          ? Icons
                              .my_location_rounded
                          : Icons
                              .refresh_rounded,
                      size: 18,
                    ),

              label: Text(
                _capturing
                    ? 'Capturing location...'
                    : _capturedPosition ==
                              null
                          ? 'Capture current location'
                          : 'Capture again',
                style:
                    const TextStyle(
                  fontSize: 13.5,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CAPTURED CARD
  // ============================================================

  Widget _buildCapturedCard() {
    final position =
        _capturedPosition!;

    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(17),

      decoration: BoxDecoration(
        color: _surface2,

        borderRadius:
            BorderRadius.circular(19),

        border: Border.all(
          color:
              _green.withOpacity(
            0.10,
          ),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      'Location captured',
                      style: TextStyle(
                        color:
                            _textPrimary,
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w700,
                      ),
                    ),

                    SizedBox(height: 3),

                    Text(
                      'GPS reference is ready to save',
                      style: TextStyle(
                        color:
                            _textSecondary,
                        fontSize:
                            12,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 9,
                  vertical: 6,
                ),

                decoration:
                    BoxDecoration(
                  color: _greenSoft,
                  borderRadius:
                      BorderRadius
                          .circular(
                    20,
                  ),
                ),

                child:
                    const Text(
                  'READY',
                  style: TextStyle(
                    color: _green,
                    fontSize: 10,
                    fontWeight:
                        FontWeight
                            .w800,
                    letterSpacing:
                        0.4,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child:
                    _coordinateItem(
                  title: 'Latitude',
                  value: position
                      .latitude
                      .toStringAsFixed(
                    5,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child:
                    _coordinateItem(
                  title:
                      'Longitude',
                  value: position
                      .longitude
                      .toStringAsFixed(
                    5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Container(
            width: double.infinity,

            padding:
                const EdgeInsets
                    .symmetric(
              horizontal: 13,
              vertical: 11,
            ),

            decoration:
                BoxDecoration(
              color: Colors.white
                  .withOpacity(
                0.025,
              ),
              borderRadius:
                  BorderRadius
                      .circular(
                12,
              ),
            ),

            child: Row(
              children: [
                const Text(
                  'GPS accuracy',
                  style: TextStyle(
                    color:
                        _textSecondary,
                    fontSize: 12,
                  ),
                ),

                const Spacer(),

                Text(
                  '±${position.accuracy.toStringAsFixed(0)} m',
                  style: TextStyle(
                    color:
                        _accuracyColor(
                      position
                          .accuracy,
                    ),
                    fontSize: 13,
                    fontWeight:
                        FontWeight
                            .w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // COORDINATE
  // ============================================================

  Widget _coordinateItem({
    required String title,
    required String value,
  }) {
    return Container(
      padding:
          const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: _surface,

        borderRadius:
            BorderRadius.circular(12),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                const TextStyle(
              color: _textMuted,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            value,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                const TextStyle(
              color: _cyan,
              fontSize: 13.5,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACCURACY COLOR
  // ============================================================

  Color _accuracyColor(
    double accuracy,
  ) {
    if (accuracy <= 20) {
      return _green;
    }

    if (accuracy <= 50) {
      return _orange;
    }

    return _red;
  }

  // ============================================================
  // RADIUS CARD
  // ============================================================

  Widget _buildRadiusCard() {
    return Container(
      padding:
          const EdgeInsets.all(17),

      decoration: BoxDecoration(
        color: _surface,

        borderRadius:
            BorderRadius.circular(19),

        border: Border.all(
          color:
              Colors.white.withOpacity(
            0.055,
          ),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      'Match radius',
                      style: TextStyle(
                        color:
                            _textPrimary,
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w700,
                      ),
                    ),

                    SizedBox(height: 4),

                    Text(
                      'Adjust the GPS verification tolerance',
                      style: TextStyle(
                        color:
                            _textSecondary,
                        fontSize:
                            12.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),

                decoration:
                    BoxDecoration(
                  color: _surface3,

                  borderRadius:
                      BorderRadius
                          .circular(
                    11,
                  ),
                ),

                child: Text(
                  '${_radius.toStringAsFixed(0)} m',
                  style:
                      const TextStyle(
                    color:
                        _textPrimary,
                    fontSize: 15,
                    fontWeight:
                        FontWeight
                            .w800,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 19),

          SliderTheme(
            data:
                SliderTheme.of(
              context,
            ).copyWith(
              activeTrackColor:
                  _green,

              inactiveTrackColor:
                  _surface3,

              thumbColor: _green,

              overlayColor:
                  _green.withOpacity(
                0.12,
              ),

              valueIndicatorColor:
                  _green,

              valueIndicatorTextStyle:
                  const TextStyle(
                color: _background,
                fontWeight:
                    FontWeight.w800,
              ),

              trackHeight: 4,

              thumbShape:
                  const RoundSliderThumbShape(
                enabledThumbRadius:
                    8,
              ),

              overlayShape:
                  const RoundSliderOverlayShape(
                overlayRadius:
                    17,
              ),
            ),

            child: Slider(
              value: _radius,
              min: 20,
              max: 150,
              divisions: 13,

              label:
                  '${_radius.toStringAsFixed(0)}m',

              onChanged: (v) {
                setState(() {
                  _radius = v;
                });
              },
            ),
          ),

          const Padding(
            padding:
                EdgeInsets.symmetric(
              horizontal: 5,
            ),

            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment
                      .spaceBetween,
              children: [
                Text(
                  '20 m',
                  style: TextStyle(
                    color:
                        _textMuted,
                    fontSize: 11,
                  ),
                ),

                Text(
                  '150 m',
                  style: TextStyle(
                    color:
                        _textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          AnimatedContainer(
            duration:
                const Duration(
              milliseconds: 250,
            ),

            width: double.infinity,

            padding:
                const EdgeInsets.all(
              13,
            ),

            decoration:
                BoxDecoration(
              color: _cyanSoft
                  .withOpacity(
                0.48,
              ),

              borderRadius:
                  BorderRadius
                      .circular(
                13,
              ),
            ),

            child: Text(
              _radiusDescription(),
              style:
                  const TextStyle(
                color:
                    _textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RADIUS DESCRIPTION
  // ============================================================

  String _radiusDescription() {
    if (_radius <= 50) {
      return 'Precise range — good for homes and outdoor locations.';
    }

    if (_radius <= 100) {
      return 'Balanced range — recommended for libraries and lecture halls.';
    }

    return 'Wide range — useful for large buildings or areas with weaker GPS accuracy.';
  }

  // ============================================================
  // RECOMMENDATION CARD
  // ============================================================

  Widget _buildRecommendationCard() {
    return Container(
      padding:
          const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color:
            _cyanSoft.withOpacity(
          0.52,
        ),

        borderRadius:
            BorderRadius.circular(16),

        border: Border(
          left: BorderSide(
            color: _cyan
                .withOpacity(0.65),
            width: 3,
          ),
        ),
      ),

      child: const Text(
        'Indoor places such as libraries, shops, and lecture halls work better around 80–100 m. '
        'For homes or outdoor locations, 30–50 m is usually enough.',
        style: TextStyle(
          color: _textSecondary,
          fontSize: 12.5,
          height: 1.5,
        ),
      ),
    );
  }

  // ============================================================
  // ERROR CARD
  // ============================================================

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,

      padding:
          const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color:
            _red.withOpacity(0.07),

        borderRadius:
            BorderRadius.circular(15),

        border: Border(
          left: BorderSide(
            color: _red.withOpacity(
              0.8,
            ),
            width: 3,
          ),
        ),
      ),

      child: Text(
        _error!,
        style: const TextStyle(
          color: Color(0xFFFFA5AD),
          fontSize: 12.5,
          height: 1.45,
        ),
      ),
    );
  }
}