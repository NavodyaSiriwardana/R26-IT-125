/// A copy of a facial-analysis result with the face photo removed.
///
/// The server returns `cropped_face_base64` so the app can show the user
/// their own face while scanning. That image must stay on the device: it is
/// never sent back with the analysis request, and the backend also strips it.
Map<String, dynamic>? withoutFaceImage(Map<String, dynamic>? facial) {
  if (facial == null) return null;
  return Map<String, dynamic>.from(facial)..remove('cropped_face_base64');
}
