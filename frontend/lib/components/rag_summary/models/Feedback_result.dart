class FeedbackResult {
  final String feedbackType;
  final String moodSignal;
  final String productivitySignal;
  final String message;
  final String action;
  final List<String> evidenceIds;
  final bool abstained;
  final String generationMethod;
  final String? fallbackReason;
  final List<String> basedOnEvidenceIds;

  FeedbackResult({
    required this.feedbackType,
    required this.moodSignal,
    required this.productivitySignal,
    required this.message,
    required this.action,
    required this.evidenceIds,
    required this.abstained,
    required this.generationMethod,
    this.fallbackReason,
    required this.basedOnEvidenceIds,
  });

  factory FeedbackResult.fromJson(Map<String, dynamic> json) {
    final evidenceIds = _asStringList(json['evidence_ids']);
    final basedOnEvidenceIds = _asStringList(json['based_on_evidence_ids']);

    return FeedbackResult(
      feedbackType: json['feedback_type'] ?? '',
      moodSignal: json['mood_signal'] ?? '',
      productivitySignal: json['productivity_signal'] ?? '',
      message: json['message'] ?? '',
      action: json['action']?.toString() ?? '',
      evidenceIds: evidenceIds,
      abstained: json['abstained'] == true,
      generationMethod: json['generation_method']?.toString() ?? '',
      fallbackReason: _asNullableString(json['fallback_reason']),
      basedOnEvidenceIds: basedOnEvidenceIds.isNotEmpty
          ? basedOnEvidenceIds
          : evidenceIds,
    );
  }
}

List<String> _asStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String? _asNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
