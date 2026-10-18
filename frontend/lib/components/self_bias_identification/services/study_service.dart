import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/consent_service.dart';

/// Research study mode. When on, every Mood Reset is assigned to either the
/// guided-breathing condition or a quiet-rest control of the same length, so
/// the effect of breathing can be separated from the effect of simply waiting.
class StudyService {
  static const breathing = 'breathing';
  static const control = 'control';

  static String get _modeKey => 'study_mode_${AppState.userId}';
  static String _countKey(String condition) =>
      'study_count_${condition}_${AppState.userId}';

  static Future<bool> isStudyMode() async {
    // Restores consent and study mode from the server if a logout wiped them.
    await ConsentService.hasConsent();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_modeKey) ?? false;
  }

  /// Turning study mode on requires consent; the caller must have checked.
  /// The choice is also recorded on the server, because only participants who
  /// opted in are included when the study data is exported.
  static Future<void> setStudyMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_modeKey, enabled);
    if (await ConsentService.hasConsent()) {
      await ApiService.saveConsent(
        userId: AppState.userId,
        agreed: true,
        version: ConsentService.currentVersion,
        studyMode: enabled,
      );
    }
  }

  /// Balanced assignment: whichever condition this participant has completed
  /// fewer times comes next; a tie is broken at random. Over a few resets each
  /// participant therefore experiences both conditions in a random order.
  static Future<String> nextCondition() async {
    final prefs = await SharedPreferences.getInstance();
    var b = prefs.getInt(_countKey(breathing)) ?? 0;
    var c = prefs.getInt(_countKey(control)) ?? 0;

    // A logout wipes the local counts; rebuild them from the saved resets so
    // the balanced order carries on instead of starting over.
    if (b == 0 && c == 0 && AppState.userId.isNotEmpty) {
      List<Map<String, dynamic>> resets;
      try {
        resets = await ApiService.fetchMoodResets(AppState.userId);
      } catch (_) {
        resets = [];
      }
      for (final reset in resets) {
        if (reset['study_mode'] != true) continue;
        if (reset['condition'] == control) {
          c++;
        } else {
          b++;
        }
      }
      if (b + c > 0) {
        await prefs.setInt(_countKey(breathing), b);
        await prefs.setInt(_countKey(control), c);
      }
    }
    if (b < c) return breathing;
    if (c < b) return control;
    return math.Random().nextBool() ? breathing : control;
  }

  static Future<void> recordCompleted(String condition) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _countKey(condition);
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  static Future<void> clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modeKey);
    await prefs.remove(_countKey(breathing));
    await prefs.remove(_countKey(control));
  }
}
