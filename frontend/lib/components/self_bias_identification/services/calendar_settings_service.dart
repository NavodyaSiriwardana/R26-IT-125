import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';

/// User-controlled opt-in for calendar-based verification.
/// Disabled by default so the app never requests calendar permission
/// unless the student explicitly enables it from the Profile screen.
///
/// Kept per student, so on a shared phone one student's choice never switches
/// calendar access on for the next student.
class CalendarSettingsService {
  static String get _prefKey =>
      'calendar_verification_enabled_${AppState.userId}';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }
}
