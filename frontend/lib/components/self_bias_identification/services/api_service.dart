import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  static const String baseUrl = 'http://10.14.35.190:8000';

  static Future<Map<String, dynamic>> analyzeBias({
    required Map<String, dynamic> diaryEntry,
    required Map<String, dynamic> sensorData,
  }) async {
    final response = await http.post(
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
    final response = await http.get(
      Uri.parse('$baseUrl/api/bias/history/$userId'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['history'] as List? ?? [];
    }
    throw Exception('Error: ${response.statusCode}');
  }
}
