class Citation {
  final String citationId;
  final String evidenceId;
  final String label;
  final String sourcePreview;
  final String sourceType;
  final bool? isValid;
  final String? validationError;

  Citation({
    required this.citationId,
    required this.evidenceId,
    required this.label,
    required this.sourcePreview,
    required this.sourceType,
    this.isValid,
    this.validationError,
  });

  bool get canOpenEvidence => isValid != false && evidenceId.isNotEmpty;

  factory Citation.fromJson(Map<String, dynamic> json) {
    return Citation(
      citationId: json['citation_id'] ?? '',
      evidenceId: json['evidence_id'] ?? '',
      label: json['label'] ?? '',
      sourcePreview: json['source_preview'] ?? '',
      sourceType: json['source_type'] ?? '',
      isValid: _asNullableBool(json['is_valid']),
      validationError: _asNullableString(json['validation_error']),
    );
  }
}

bool? _asNullableBool(dynamic value) {
  if (value is bool) return value;
  if (value == null) return null;

  final normalized = value.toString().trim().toLowerCase();
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return null;
}

String? _asNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
