import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Full-screen map with a fixed center pin. The student pans/zooms the
/// map to position the pin over the desired location, then confirms —
/// the center coordinates (and, if a nearby named place is found, a
/// suggested name) are returned to the caller (AddLocationScreen).
class MapPickerScreen extends StatefulWidget {
  /// Optional starting point (e.g. student's current GPS position).
  final LatLng? initialPosition;

  const MapPickerScreen({super.key, this.initialPosition});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

/// Result returned from the map picker: coordinates plus an optional
/// suggested place name (from Places API nearby search).
class MapPickResult {
  final LatLng position;
  final String? suggestedName;
  MapPickResult({required this.position, this.suggestedName});
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const Color _background = Color(0xFF070B12);
  static const Color _surface = Color(0xFF0D131D);
  static const Color _green = Color(0xFF35E47B);
  static const Color _textPrimary = Color(0xFFF4F7FB);
  static const Color _textSecondary = Color(0xFFA5AFBE);

  // The native Maps SDK key (app-signature restricted) lives in
  // AndroidManifest.xml as a Gradle manifest placeholder, sourced from
  // android/local.properties (gitignored) — not needed here in Dart.

  // Unrestricted (Application restrictions: None), scoped only to
  // Places API via API restrictions. Used for the plain HTTP REST call
  // to Nearby Search, since that call can't carry Android app signature
  // verification the way the native Maps SDK can. Passed at build time
  // via --dart-define=PLACES_API_KEY=... so it never lives in source.
  static const String _placesApiKey =
      String.fromEnvironment('PLACES_API_KEY');

  // Default center if no initial position is given (SLIIT, Malabe).
  static const LatLng _defaultCenter = LatLng(6.9147, 79.9724);

  GoogleMapController? _controller;
  late LatLng _centerPosition;
  bool _confirming = false;
  bool _searching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _centerPosition = widget.initialPosition ?? _defaultCenter;
  }

  void _onCameraMove(CameraPosition position) {
    // Track the map's center as the user pans/zooms — no setState here
    // (would rebuild on every frame); the pin itself is a fixed overlay,
    // so we only need the latest value when the user confirms.
    _centerPosition = position.target;
  }

  /// Looks up the nearest named place (POI) to the given coordinates
  /// using the Places API Nearby Search endpoint. Returns null if
  /// nothing is found or the request fails — the caller falls back to
  /// asking the student to type a name.
  Future<String?> _lookupNearbyPlaceName(LatLng position) async {
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${position.latitude},${position.longitude}'
        '&radius=150'
        '&key=$_placesApiKey',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status != 'OK') {
        // Log for debugging — e.g. ZERO_RESULTS, REQUEST_DENIED, INVALID_REQUEST
        // ignore: avoid_print
        print('Places API status: $status, error: ${data['error_message']}');
        return null;
      }

      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final name = results.first['name'] as String?;
      return name;
    } catch (e) {
      // ignore: avoid_print
      print('Places API lookup failed: $e');
      return null;
    }
  }

  /// Forward-geocodes the typed text (e.g. "SLIIT Malabe") to
  /// coordinates and moves the map camera there. Silently does nothing
  /// on failure (student can still position the pin manually).
  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _searching = true);
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(query)}'
        '&key=$_placesApiKey',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String?;
        if (status == 'OK') {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            final loc = results.first['geometry']['location'];
            final target = LatLng(loc['lat'], loc['lng']);
            _centerPosition = target;
            await _controller?.animateCamera(
              CameraUpdate.newLatLngZoom(target, 16),
            );
          }
        } else {
          // Log for debugging — e.g. REQUEST_DENIED means the key's API
          // restrictions don't include the Geocoding API, ZERO_RESULTS
          // means the query didn't match a place.
          // ignore: avoid_print
          print('Geocoding API status: $status, error: ${data['error_message']}');
        }
      } else {
        // ignore: avoid_print
        print('Geocoding API HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Geocoding API lookup failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _confirmLocation() async {
    setState(() => _confirming = true);
    final name = await _lookupNearbyPlaceName(_centerPosition);
    if (!mounted) return;
    Navigator.pop(
      context,
      MapPickResult(position: _centerPosition, suggestedName: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _centerPosition,
              zoom: 16,
            ),
            onMapCreated: (controller) => _controller = controller,
            onCameraMove: _onCameraMove,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Fixed center pin overlay
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36), // pin tip aligns to center
                child: Icon(
                  Icons.location_pin,
                  size: 44,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Material(
                    color: _surface.withValues(alpha: 0.94),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.arrow_back, color: _textPrimary, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onSubmitted: (_) => _searchLocation(),
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(color: _textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search a place, e.g. SLIIT Malabe',
                          hintStyle: const TextStyle(color: _textSecondary, fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.search, color: _textSecondary, size: 20),
                                  onPressed: _searchLocation,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom confirm bar
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF141A24).withValues(alpha: 0.96),
                      _surface.withValues(alpha: 0.96),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_centerPosition.latitude.toStringAsFixed(5)}, '
                      '${_centerPosition.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF6FE07E), _green, Color(0xFF55CFE0)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: _green.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: _confirming ? null : _confirmLocation,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: _background,
                          disabledBackgroundColor: Colors.transparent,
                          disabledForegroundColor: _background.withValues(alpha: 0.6),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _confirming
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _background,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 19),
                        label: Text(
                          _confirming ? 'Looking up place name...' : 'Confirm this location',
                          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}