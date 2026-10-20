import 'package:flutter/foundation.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/services/progress_rules.dart';

/// Loads what "My productivity progress" needs. A failed load gives null, so
/// the card simply does not show.
class ProgressService {
  /// Tests replace this to supply data without a server.
  static Future<ProgressSummary> Function(String userId) loader = _load;

  static Future<ProgressSummary?> load() async {
    final user = AppState.userId;
    if (user.isEmpty) return null;
    try {
      return await loader(user);
    } catch (e) {
      debugPrint('Progress load failed: $e');
      return null;
    }
  }

  static Future<ProgressSummary> _load(String userId) async {
    final rows = await ApiService.fetchHistory(userId);
    var faces = <Map<String, dynamic>>[];
    try {
      faces = await ApiService.fetchFaceChecks(userId);
    } catch (_) {}
    var resets = <ResetRecord>[];
    try {
      resets = (await ApiService.fetchMoodResets(userId))
          .map((r) => ResetRecord(r))
          .toList();
    } catch (_) {}
    return computeProgress(
      [...rows, ...faces].map(HistoryEntry.fromJson).toList(),
      resets,
    );
  }
}
