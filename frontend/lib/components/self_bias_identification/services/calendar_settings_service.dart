import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled opt-in for calendar-based verification.
/// Disabled by default so the app never requests calendar permission
/// unless the student explicitly enables it from the Profile screen.
class CalendarSettingsService {
  static const _prefKey = 'calendar_verification_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);
  }
}
