import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:frontend/components/self_bias_identification/services/api_service.dart';

/// Captures where the phone is right after the student wrote a diary entry, so
/// the place they claimed can be checked without saving any places by hand.
///
/// It runs when Bias Insights opens (nothing in the team's diary form is
/// changed) and only while the entry is fresh: the server says so through
/// `location_capture_open`. A late capture would say nothing about where the
/// activity was.
class EntryLocationCapture {
  // Not const: tests replace these.
  static Future<Position?> Function() positionProvider = _currentPosition;
  static Future<PlaceInfo> Function(double lat, double lng) placesLookup =
      _lookupPlaces;

  static const _placesKey = String.fromEnvironment('PLACES_API_KEY');

  /// Entry ids captured in this run, so a screen rebuild never asks twice.
  static final Set<String> _done = {};

  static Future<Position?> _currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 12),
    );
  }

  /// Names and kinds of the places within 100 m of the position. Empty when
  /// there is no API key, no network or nothing nearby.
  static Future<PlaceInfo> _lookupPlaces(double lat, double lng) async {
    if (_placesKey.isEmpty) return const PlaceInfo.empty();
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=$lat,$lng&radius=100&key=$_placesKey',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const PlaceInfo.empty();
      return parsePlaces(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return const PlaceInfo.empty();
    }
  }

  /// Turns a Places Nearby Search answer into one name and a list of kinds.
  /// The name is the first place that has a useful kind (a campus, library or
  /// cafe) so the card reads "SLIIT Malabe" rather than a shop next door.
  @visibleForTesting
  static PlaceInfo parsePlaces(Map<String, dynamic> body) {
    if (body['status'] != 'OK') return const PlaceInfo.empty();
    final results = (body['results'] as List? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    if (results.isEmpty) return const PlaceInfo.empty();

    const generic = {'point_of_interest', 'establishment', 'political', 'premise'};
    const useful = {
      'university', 'school', 'secondary_school', 'primary_school',
      'library', 'cafe', 'restaurant', 'bakery', 'meal_takeaway', 'food',
    };
    final types = <String>{};
    String name = '';
    for (final r in results) {
      final t = [for (final x in (r['types'] as List? ?? [])) x.toString()]
          .where((x) => !generic.contains(x))
          .toList();
      types.addAll(t);
      if (name.isEmpty && t.any(useful.contains)) {
        name = (r['name'] ?? '').toString();
      }
    }
    if (name.isEmpty) name = (results.first['name'] ?? '').toString();
    return PlaceInfo(name: name, types: types.take(8).toList());
  }

  /// The request body for the server.
  @visibleForTesting
  static Map<String, dynamic> payload({
    required String docId,
    required double lat,
    required double lng,
    required double? accuracy,
    required PlaceInfo place,
    required double? ageHours,
    required DateTime now,
  }) =>
      {
        'source_doc_id': docId,
        'lat': lat,
        'lng': lng,
        'accuracy_m': accuracy,
        'place_name': place.name,
        'place_types': place.types,
        'age_at_capture_hours': ageHours,
        'captured_at': now.toUtc().toIso8601String(),
      };

  /// Captures once for the latest diary entry when the server says it is fresh.
  /// Returns true when a capture was sent. Never throws: a missing capture just
  /// means the place is "not checked".
  static Future<bool> maybeCapture(String userId, {DateTime? now}) async {
    if (userId.isEmpty) return false;
    try {
      final status = await ApiService.diaryStatus(userId);
      if (status == null || status['location_capture_open'] != true) return false;
      final docId = (status['source_doc_id'] ?? '').toString();
      if (docId.isEmpty || _done.contains(docId)) return false;

      final position = await positionProvider();
      if (position == null) return false;
      final place = await placesLookup(position.latitude, position.longitude);

      final sent = await ApiService.saveEntryLocation(
        userId,
        payload(
          docId: docId,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          place: place,
          ageHours: (status['entry_age_hours'] as num?)?.toDouble(),
          now: now ?? DateTime.now(),
        ),
      );
      if (sent) _done.add(docId);
      return sent;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void resetForTests() => _done.clear();
}

class PlaceInfo {
  final String name;
  final List<String> types;
  const PlaceInfo({required this.name, required this.types});
  const PlaceInfo.empty()
      : name = '',
        types = const [];
}
