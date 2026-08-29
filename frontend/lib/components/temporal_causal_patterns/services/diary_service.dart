import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/diary_entry_model.dart';
import 'local_storage.dart';

class DiaryService {
  static const String baseUrl = 'http://10.14.35.139:8000';
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<bool> submitEntry(DiaryEntryModel entry) async {
    bool firebaseSuccess = false;
    bool backendSuccess = false;

    // ── Call 1 — Firebase Firestore ──────────
    try {
      await _db.collection('diaryEntries').add({
        ...entry.toJson(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      firebaseSuccess = true;
      print('[DiaryService] Firebase saved successfully');
    } catch (e) {
      print('[DiaryService] Firebase error: $e');
    }

    // ── Call 2 — FastAPI backend ─────────────
    try {
      final token = await LocalStorage.getToken();

      final response = await http
          .post(
            Uri.parse(
              '$baseUrl/api/v1/temporal-patterns/diary/entry',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(entry.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      print('[DiaryService] Backend status: ${response.statusCode}');
      print('[DiaryService] Backend body: ${response.body}');

      backendSuccess = response.statusCode == 200;
    } catch (e) {
      print('[DiaryService] Backend error: $e');
    }

    print('[DiaryService] Firebase: $firebaseSuccess, '
        'Backend: $backendSuccess');

    // Success if at least Firebase worked
    // (backend can retry later)
    return firebaseSuccess || backendSuccess;
  }
}