import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/temporal_causal_patterns/services/local_storage.dart';

/// The name shown for the signed-in student.
///
/// The team's sign-up already stores it twice: in Firestore (`users/{uid}`,
/// field `name`) and on the phone (LocalStorage). Changing it here updates
/// both, so the shared record stays in step. Only the `name` field is
/// written, nothing else in that document.
class ProfileNameService {
  /// The current name, or empty when none is known. The dashboard and the
  /// profile page listen to this, so a change shows everywhere at once.
  static final ValueNotifier<String> name = ValueNotifier<String>('');

  /// Writes the name to Firestore. Replaced in tests.
  static Future<void> Function(String uid, String name) remoteSave =
      _saveToFirebase;

  /// Reads the name from Firestore. Replaced in tests.
  static Future<String> Function(String uid) remoteLoad = _loadFromFirebase;

  static const minLength = 2;
  static const maxLength = 40;

  /// What to show: the name, or the account id until a name is known.
  static String get displayName =>
      name.value.isNotEmpty ? name.value : AppState.userId;

  /// Trims and collapses runs of spaces.
  static String clean(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// A message to show the student, or null when the name is acceptable.
  static String? validate(String raw) {
    final value = clean(raw);
    if (value.length < minLength) return 'Enter at least $minLength characters.';
    if (value.length > maxLength) return 'Keep it to $maxLength characters or fewer.';
    if (RegExp(r'[\u0000-\u001F\u007F<>]').hasMatch(value)) {
      return 'Please use letters, numbers and normal punctuation.';
    }
    return null;
  }

  /// Reads the saved name; falls back to Firestore when this phone has none.
  static Future<void> load() async {
    var value = await LocalStorage.getName();
    if (value.isEmpty && AppState.userId.isNotEmpty) {
      try {
        value = await remoteLoad(AppState.userId);
        if (value.isNotEmpty) await LocalStorage.saveName(value);
      } catch (_) {
        value = '';
      }
    }
    name.value = value;
  }

  /// Saves a new name to Firestore first, then to the phone, so the two never
  /// disagree. Throws [FormatException] for a name that is not acceptable, and
  /// the original error when Firestore cannot be reached (nothing changes).
  static Future<void> save(String raw) async {
    final problem = validate(raw);
    if (problem != null) throw FormatException(problem);
    if (AppState.userId.isEmpty) throw StateError('Not signed in');
    final value = clean(raw);
    await remoteSave(AppState.userId, value);
    await LocalStorage.saveName(value);
    name.value = value;
  }

  static Future<void> _saveToFirebase(String uid, String value) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'name': value}, SetOptions(merge: true))
        .timeout(const Duration(seconds: 12));
  }

  static Future<String> _loadFromFirebase(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get()
        .timeout(const Duration(seconds: 12));
    return (doc.data()?['name'] ?? '').toString();
  }
}
