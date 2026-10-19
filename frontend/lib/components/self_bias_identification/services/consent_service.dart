import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/consent_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';

/// Informed consent for the camera analysis (and, optionally, the research
/// study). Stored on the device, per user, and recorded on the server so a
/// participant's data can be traced to a consent version.
class ConsentService {
  static const currentVersion = 'v1';

  static String get _consentKey =>
      'research_consent_${currentVersion}_${AppState.userId}';
  static String get _syncedKey =>
      'research_consent_synced_${currentVersion}_${AppState.userId}';

  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_consentKey) ?? false) return true;

    // The team's logout clears every stored preference, so local state can
    // vanish while the consent is still valid. The server's record is the
    // source of truth: restore from it instead of asking again.
    if (AppState.userId.isEmpty) return false;
    final remote = await ApiService.getConsent(AppState.userId);
    if (remote == null ||
        remote['agreed'] != true ||
        remote['version'] != currentVersion) {
      return false;
    }
    await prefs.setBool(_consentKey, true);
    await prefs.setBool(_syncedKey, true);
    await prefs.setBool(
      'study_mode_${AppState.userId}',
      remote['study_mode'] == true,
    );
    return true;
  }

  /// Records agreement locally, then tells the server. A failed upload does
  /// not block the user; it is retried the next time consent is checked.
  static Future<void> record({required bool studyMode}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, true);
    await prefs.setBool(_syncedKey, false);
    await _sync(studyMode);
  }

  static Future<void> _sync(bool studyMode) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await ApiService.saveConsent(
      userId: AppState.userId,
      agreed: true,
      version: currentVersion,
      studyMode: studyMode,
    );
    if (ok) await prefs.setBool(_syncedKey, true);
  }

  /// Local state is cleared after the user deletes their data.
  static Future<void> clearLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_consentKey);
    await prefs.remove(_syncedKey);
  }

  /// Makes sure the user has agreed, showing the consent screen if not.
  /// Returns true when the camera may be used.
  static Future<bool> ensure(BuildContext context) async {
    if (await hasConsent()) {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_syncedKey) ?? false)) {
        // Retry an earlier failed upload without making the user wait.
        _sync(await isStudyModeFlag());
      }
      return true;
    }
    if (!context.mounted) return false;
    final agreed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ConsentScreen()),
    );
    return agreed == true;
  }

  static Future<bool> isStudyModeFlag() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('study_mode_${AppState.userId}') ?? false;
  }
}
