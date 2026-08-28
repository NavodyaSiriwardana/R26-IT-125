import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/pattern_model.dart';
import 'local_storage.dart';

class PatternService {
  static const String baseUrl = 'http://192.168.8.154:8000';

  static Future<List<PatternModel>> analysePatterns(
      String userId) async {
    try {
      final token = await LocalStorage.getToken();

      final response = await http.post(
        Uri.parse(
          '$baseUrl/api/v1/temporal-patterns/analyse/$userId',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('[PatternService] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List patterns = data['patterns'] ?? [];
        return patterns
            .map((p) => PatternModel.fromJson(p))
            .toList();
      }
      return [];
    } catch (e) {
      print('[PatternService] Error: $e');
      return [];
    }
  }

  static Future<List<PatternModel>> getSavedPatterns(
      String userId) async {
    try {
      final token = await LocalStorage.getToken();

      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/v1/temporal-patterns/patterns/$userId',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List patterns = data['patterns'] ?? [];
        return patterns
            .map((p) => PatternModel.fromJson(p))
            .toList();
      }
      return [];
    } catch (e) {
      print('[PatternService] Error: $e');
      return [];
    }
  }
}