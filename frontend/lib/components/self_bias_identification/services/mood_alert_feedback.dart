import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/components/self_bias_identification/services/mood_light_data.dart';

/// The sound and vibration that go with the bulb pop-up. Uses only what
/// Flutter already has (no extra package). Stressed: a soft system sound and a
/// firm tap. Uneasy: a gentle tap only. Calm: nothing. The sound follows the
/// phone's own volume and silent mode, and the student can switch it off in
/// Profile; the vibration stays.
class MoodAlertFeedback {
  static const _soundKey = 'mood_alert_sound_enabled';

  /// Tests replace these so nothing touches the platform.
  static Future<void> Function() playSound =
      () => SystemSound.play(SystemSoundType.alert);
  static Future<void> Function() tapStrong = HapticFeedback.heavyImpact;
  static Future<void> Function() tapGentle = HapticFeedback.lightImpact;

  static Future<bool> soundEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_soundKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setSoundEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, value);
  }

  /// Plays the feedback for a scan that just showed [level].
  static Future<void> play(MoodLightLevel level) async {
    try {
      switch (level) {
        case MoodLightLevel.calm:
          return;
        case MoodLightLevel.uneasy:
          await tapGentle();
          return;
        case MoodLightLevel.stressed:
          await tapStrong();
          if (await soundEnabled()) await playSound();
          return;
      }
    } catch (_) {
      // Sound and vibration are extras. They never break the scan.
    }
  }
}
