import 'package:frontend/app_state.dart';
import 'package:frontend/components/temporal_causal_patterns/services/local_storage.dart';

/// Makes sure the app knows which student is signed in before any request is
/// made on their behalf. Without an id every request would go to an empty
/// account, so the screens stop and ask the student to sign in instead.
class SignInCheck {
  /// True when a student id is known. The id is normally set when Bias
  /// Insights is opened from the diary; when it is missing, this tries the id
  /// saved at sign-in before giving up.
  static Future<bool> ensure() async {
    if (AppState.userId.isNotEmpty) return true;
    try {
      final saved = await LocalStorage.getUserId();
      if (saved.isNotEmpty) {
        AppState.userId = saved;
        return true;
      }
    } catch (_) {
      // Fall through: not signed in.
    }
    return false;
  }
}
