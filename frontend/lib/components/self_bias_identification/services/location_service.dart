import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Handles saving/reading a user's known locations and matching
/// a live GPS reading against them using the Haversine formula.
///
/// Storage lives in Firestore, but only the backend talks to Firestore
/// directly (via firebase_admin); the app goes through the REST API,
/// same as [ApiService].
class LocationService {
  static const String _baseUrl = ApiService.baseUrl;

  /// Fetch all saved locations for a user.
  /// Returns e.g. { "Library": {"lat": 6.91, "lng": 79.97, "radius_m": 80} }
  static Future<Map<String, dynamic>> getUserLocations(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/bias/locations/$userId'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['locations'] as Map<String, dynamic>?) ?? {};
    }
    throw Exception('Error: ${response.statusCode}');
  }

  /// Save (or overwrite) one named location.
  static Future<void> saveLocation({
    required String userId,
    required String name,
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/bias/locations/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius_m': radiusMeters,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Error: ${response.statusCode}');
    }
  }

  /// Delete a named location.
  static Future<void> deleteLocation(String userId, String name) async {
    final response = await http.delete(
      Uri.parse(
          '$_baseUrl/api/bias/locations/$userId/${Uri.encodeComponent(name)}'),
    );
    if (response.statusCode != 200) {
      throw Exception('Error: ${response.statusCode}');
    }
  }

  /// Haversine distance between two coordinates, in meters.
  static double distanceMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRad(double deg) => deg * (pi / 180);

  /// Compares a live GPS reading against all saved locations for the
  /// user and returns the closest matching name, or "Unknown" if the
  /// reading falls outside every saved location's radius.
  ///
  /// Also returns the raw coordinates so they can still be stored
  /// alongside the matched name if needed.
  static Future<LocationMatchResult> matchLocation({
    required String userId,
    required double currentLat,
    required double currentLng,
  }) async {
    final saved = await getUserLocations(userId);

    String bestMatch = 'Unknown';
    double bestDistance = double.infinity;

    saved.forEach((name, value) {
      final lat = (value['lat'] as num).toDouble();
      final lng = (value['lng'] as num).toDouble();
      final radius = (value['radius_m'] as num).toDouble();

      final dist = distanceMeters(currentLat, currentLng, lat, lng);

      // Only consider it a candidate if within its own radius,
      // then keep the closest one among candidates.
      if (dist <= radius && dist < bestDistance) {
        bestDistance = dist;
        bestMatch = name;
      }
    });

    return LocationMatchResult(
      matchedName: bestMatch,
      lat: currentLat,
      lng: currentLng,
      distanceMeters: bestDistance == double.infinity ? null : bestDistance,
    );
  }
}

class LocationMatchResult {
  final String matchedName; // e.g. "Library" or "Unknown"
  final double lat;
  final double lng;
  final double? distanceMeters;

  LocationMatchResult({
    required this.matchedName,
    required this.lat,
    required this.lng,
    this.distanceMeters,
  });
}
