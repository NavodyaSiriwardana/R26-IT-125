import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';

/// Remembers which result's recommendations the student has already opened,
/// so the bell on the dashboard shows a red dot only for something new.
/// Kept per student, on this phone.
class RecommendationsSeen {
  static String get _key => 'recommendations_seen_${AppState.userId}';

  /// True when [entryId] is a result the student has not opened the
  /// recommendations for yet.
  static Future<bool> isNew(String entryId) async {
    if (entryId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) != entryId;
  }

  static Future<void> markSeen(String entryId) async {
    if (entryId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, entryId);
  }
}
