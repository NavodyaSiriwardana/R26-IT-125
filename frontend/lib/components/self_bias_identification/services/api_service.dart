import 'dart:convert';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';

/// The server answered, but with an error status.
class ApiException implements Exception {
  final int status;
  const ApiException(this.status);

  String get message =>
      'The server had a problem (code $status). Please try again.';

  @override
  String toString() => message;
}

class ApiService {
  /// Where the backend is. Defaults to this computer (fine for Windows and
  /// Chrome). On a phone, 127.0.0.1 is the phone itself, so start the app with
  /// `--dart-define=API_BASE_URL=http://<laptop-ip>:8000`. Not const, so tests
  /// can point it at a local server.
  static String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static Future<Map<String, dynamic>> analyzeBias({
    required Map<String, dynamic> diaryEntry,
    required Map<String, dynamic> sensorData,
  }) async {
    final response = await ApiClient.post(
      Uri.parse('$baseUrl/api/bias/analyze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'diary_entry': diaryEntry, 'sensor_data': sensorData}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Error: ${response.statusCode}');
  }

  static Future<List<dynamic>> getHistory(String userId) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/api/bias/history/$userId'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['history'] as List? ?? [];
    }
    throw Exception('Error: ${response.statusCode}');
  }

  /// Runs the same facial-analysis endpoint the Expression Scan uses.
  static Future<Map<String, dynamic>> analyzeFace(String imageBase64) async {
    final response = await ApiClient.post(
      Uri.parse('$baseUrl/api/bias/facial/analyze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'image_base64': imageBase64}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Server error: ${response.statusCode}');
  }

  /// What the latest diary entry means: `new` (it can be analysed), `none`,
  /// `stale` (too old) or `analyzed` (done before). Null when the server cannot
  /// say, so the caller carries on as it always did.
  static Future<String?> diaryState(String userId) async {
    try {
      final response = await ApiClient.get(
        Uri.parse('$baseUrl/api/bias/diary-status/$userId'),
      );
      if (response.statusCode != 200) return null;
      final state = jsonDecode(response.body)['state'];
      return state is String ? state : null;
    } catch (_) {
      return null;
    }
  }

  /// A camera scan with no diary entry to compare against. Returns the
  /// Mood Support for the face reading alone, or null when no usable face was
  /// found (nothing is stored then). Throws on a network or server problem.
  static Future<Map<String, dynamic>?> faceCheck(
    String userId,
    Map<String, dynamic> facialEmotion,
  ) async {
    final response = await ApiClient.post(
      Uri.parse('$baseUrl/api/bias/face-check/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'facial_emotion': facialEmotion}),
    );
    if (response.statusCode != 200) throw ApiException(response.statusCode);
    final body = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    return body['status'] == 'success' ? body : null;
  }

  /// The user's face-only checks, newest first. Throws on failure.
  static Future<List<Map<String, dynamic>>> fetchFaceChecks(
    String userId, {
    int limit = 200,
  }) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/api/bias/face-checks/$userId?limit=$limit'),
    );
    if (response.statusCode != 200) throw ApiException(response.statusCode);
    return (jsonDecode(response.body)['checks'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Stores a finished Mood Reset and returns the before/after comparison
  /// computed by the backend.
  static Future<Map<String, dynamic>> saveMoodReset({
    required String userId,
    required String entryId,
    required double beforeStress,
    required String beforeMood,
    required Map<String, dynamic>? afterFacial,
    required int durationSeconds,
    required int roundsCompleted,
    int? selfBefore,
    int? selfAfter,
    String condition = 'breathing',
    bool studyMode = false,
  }) async {
    final response = await ApiClient.post(
      Uri.parse('$baseUrl/api/bias/mood-reset/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'entry_id': entryId,
        'before_stress': beforeStress,
        'before_mood': beforeMood,
        // The server strips any image data; it is also removed before sending.
        'after_facial': afterFacial == null
            ? null
            : (Map<String, dynamic>.from(afterFacial)
                ..remove('cropped_face_base64')),
        'duration_seconds': durationSeconds,
        'rounds_completed': roundsCompleted,
        'self_before': selfBefore,
        'self_after': selfAfter,
        'condition': condition,
        'study_mode': studyMode,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Server error: ${response.statusCode}');
  }

  /// Records the participant's consent on the server. Returns false when the
  /// server could not be reached, so the caller can retry later.
  static Future<bool> saveConsent({
    required String userId,
    required bool agreed,
    required String version,
    required bool studyMode,
  }) async {
    try {
      final response = await ApiClient.post(
        Uri.parse('$baseUrl/api/bias/consent/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'agreed': agreed,
          'version': version,
          'study_mode': studyMode,
        }),
      );
      return response.statusCode == 200 &&
          jsonDecode(response.body)['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  /// The stored consent record, or null when there is none or the server
  /// cannot be reached.
  static Future<Map<String, dynamic>?> getConsent(String userId) async {
    try {
      final response = await ApiClient.get(
        Uri.parse('$baseUrl/api/bias/consent/$userId'),
      );
      if (response.statusCode != 200) return null;
      final consent = jsonDecode(response.body)['consent'];
      return consent is Map ? Map<String, dynamic>.from(consent) : null;
    } catch (_) {
      return null;
    }
  }

  /// The user's saved analyses, newest first. Throws when the server cannot
  /// be reached or answers with an error, so "no entries yet" and "could not
  /// load" can be told apart.
  static Future<List<Map<String, dynamic>>> fetchHistory(
    String userId, {
    int limit = 200,
  }) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/api/bias/history/$userId?limit=$limit'),
    );
    if (response.statusCode != 200) throw ApiException(response.statusCode);
    return (jsonDecode(response.body)['history'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// The user's saved Mood Resets, newest first. Throws on failure.
  static Future<List<Map<String, dynamic>>> fetchMoodResets(
    String userId, {
    int limit = 200,
  }) async {
    final response = await ApiClient.get(
      Uri.parse('$baseUrl/api/bias/mood-resets/$userId?limit=$limit'),
    );
    if (response.statusCode != 200) throw ApiException(response.statusCode);
    return (jsonDecode(response.body)['resets'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Same, but empty when unreachable, for places where resets are a bonus.
  static Future<List<Map<String, dynamic>>> getMoodResets(String userId) async {
    try {
      return await fetchMoodResets(userId, limit: 20);
    } catch (_) {
      return [];
    }
  }

  /// Withdrawal: deletes everything this component stored about the user.
  /// Throws when the server could not complete the deletion.
  static Future<Map<String, dynamic>> deleteMyData(String userId) async {
    final response = await ApiClient.delete(
      Uri.parse('$baseUrl/api/bias/participant/$userId/data'),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Server error: ${response.statusCode}');
  }
}
