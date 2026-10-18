import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:frontend/app_state.dart';

/// The student's profile photo. It stays on this phone, in a file named for the
/// student, and is never sent to the server. It lives in the app's own folder
/// rather than in preferences, so signing out (which clears preferences) does
/// not lose it, and each student on a shared phone keeps their own.
class ProfilePhotoService {
  /// The current student's photo, or null. The dashboard and the profile page
  /// listen to this, so a change shows everywhere at once.
  static final ValueNotifier<Uint8List?> photo = ValueNotifier<Uint8List?>(null);

  /// Where the photos are kept. Replaced in tests.
  static Future<Directory> Function() directoryProvider =
      getApplicationSupportDirectory;

  /// Replaced in tests, so no real picker is opened.
  static Future<Uint8List?> Function(ImageSource source) picker = _pickFromDevice;

  /// The camera cannot be used from a computer, only from a phone.
  static bool get canUseCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const maxBytes = 1024 * 1024;

  static String _fileName(String userId) {
    final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'profile_photo_$safe.jpg';
  }

  static Future<File> _file() async {
    final dir = await directoryProvider();
    return File('${dir.path}${Platform.pathSeparator}${_fileName(AppState.userId)}');
  }

  /// Reads the signed-in student's photo (or clears it when there is none).
  static Future<void> load() async {
    if (kIsWeb || AppState.userId.isEmpty) {
      photo.value = null;
      return;
    }
    try {
      final file = await _file();
      photo.value = await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      photo.value = null;
    }
  }

  /// Lets the student choose a photo. Returns true when one was saved, false
  /// when they cancelled. Throws when the picture cannot be used.
  static Future<bool> choose(ImageSource source) async {
    final bytes = await picker(source);
    if (bytes == null) return false;
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Photo is empty or too large');
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    photo.value = bytes;
    return true;
  }

  static Future<void> remove() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing to remove, or the file is already gone.
    }
    photo.value = null;
  }

  static Future<Uint8List?> _pickFromDevice(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    return picked?.readAsBytes();
  }
}
