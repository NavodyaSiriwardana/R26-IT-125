import 'Feedback_result.dart';
import 'Rag_summary_point.dart';

class CompareSummaryResponse {
  final String query;
  final String summaryType;
  final List<RagSummaryPoint> summaryPoints;
  final double? unsupportedClaimRate;
  final double? groundedClaimRate;
  final double? citationPrecision;
  final double? citationCompleteness;

  /// Deprecated compatibility alias for [unsupportedClaimRate].
  ///
  /// This value is decoded only when the backend sends it. It is never used to
  /// synthesize another research metric.
  @Deprecated('Use unsupportedClaimRate instead.')
  final double? hallucinationScore;
  final FeedbackResult feedback;
  final Map<String, dynamic> additionalData;

  // Weekly summary fields
  final String? userId;
  final String? weekStart;
  final String? weekEnd;
  final String? savedSummaryId;

  CompareSummaryResponse({
    required this.query,
    required this.summaryType,
    required this.summaryPoints,
    this.unsupportedClaimRate,
    this.groundedClaimRate,
    this.citationPrecision,
    this.citationCompleteness,
    this.hallucinationScore,
    required this.feedback,
    required this.additionalData,
    this.userId,
    this.weekStart,
    this.weekEnd,
    this.savedSummaryId,
  });

  factory CompareSummaryResponse.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['summary_points'];
    final points = rawPoints is List
        ? rawPoints
              .whereType<Map>()
              .map(
                (item) =>
                    RagSummaryPoint.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <RagSummaryPoint>[];

    return CompareSummaryResponse(
      query: json['query'] ?? '',
      summaryType: json['summary_type'] ?? '',
      summaryPoints: points,
      unsupportedClaimRate: _asNullableDouble(json['unsupported_claim_rate']),
      groundedClaimRate: _asNullableDouble(json['grounded_claim_rate']),
      citationPrecision: _asNullableDouble(json['citation_precision']),
      citationCompleteness: _asNullableDouble(json['citation_completeness']),
      hallucinationScore: _asNullableDouble(json['hallucination_score']),
      feedback: FeedbackResult.fromJson(_asMap(json['feedback'])),
      additionalData: _asMap(json['additional_data']),
      userId: json['user_id'],
      weekStart: json['week_start'],
      weekEnd: json['week_end'],
      savedSummaryId: json['saved_summary_id'],
    );
  }

  SummaryConditionResult get plainSlm =>
      SummaryConditionResult.fromJson(_asMap(additionalData['plain_slm']));

  SummaryConditionResult get rag =>
      SummaryConditionResult.fromJson(_asMap(additionalData['rag']));

  Map<String, dynamic> get comparison => _asMap(additionalData['comparison']);

  String get displayedCondition =>
      additionalData['displayed_condition']?.toString().trim() ?? '';
}

class SummaryConditionResult {
  final String status;
  final String summaryText;
  final List<RagSummaryPoint> summaryPoints;
  final Map<String, dynamic> generation;
  final Map<String, dynamic> evaluation;
  final Map<String, dynamic> metrics;
  final Map<String, dynamic> retrieval;
  final Map<String, dynamic> rawData;

  const SummaryConditionResult({
    required this.status,
    required this.summaryText,
    required this.summaryPoints,
    required this.generation,
    required this.evaluation,
    required this.metrics,
    required this.retrieval,
    required this.rawData,
  });

  factory SummaryConditionResult.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['summary_points'];
    final points = rawPoints is List
        ? rawPoints
              .whereType<Map>()
              .map(
                (point) =>
                    RagSummaryPoint.fromJson(Map<String, dynamic>.from(point)),
              )
              .toList()
        : <RagSummaryPoint>[];
    final directSummaryText = json['summary_text']?.toString().trim() ?? '';

    return SummaryConditionResult(
      status: json['status']?.toString().trim() ?? '',
      summaryText: directSummaryText.isNotEmpty
          ? directSummaryText
          : points.map((point) => point.text).join(' ').trim(),
      summaryPoints: points,
      generation: _asMap(json['generation']),
      evaluation: _asMap(json['evaluation']),
      metrics: _asMap(json['metrics']),
      retrieval: _asMap(json['retrieval']),
      rawData: json,
    );
  }

  bool get isSuccessful {
    final normalized = status.toLowerCase();
    return const {
      'success',
      'succeeded',
      'completed',
      'ok',
      'available',
    }.contains(normalized);
  }

  bool get abstained {
    return rawData['abstained'] == true ||
        status.toLowerCase().trim() == 'abstained';
  }

  String get displayStatus => status.isEmpty ? 'not reported' : status;

  String get evaluationStatus {
    final value = evaluation['status'] ?? rawData['evaluation_status'];
    return value?.toString().trim() ?? '';
  }

  double? metric(String name) {
    final aliases = <String>{
      name,
      ...(_metricAliases[name] ?? const <String>[]),
    };
    final sources = [
      rawData,
      evaluation,
      _asMap(evaluation['citation_metrics']),
      metrics,
      retrieval,
      generation,
    ];

    for (final source in sources) {
      for (final alias in aliases) {
        final rawValue = source[alias];
        final value = rawValue is Map
            ? _asNullableDouble(_asMap(rawValue)['value'])
            : _asNullableDouble(rawValue);
        if (value != null) return value;
      }
    }

    return null;
  }

  String? generationValue(String name) {
    final value = generation[name] ?? rawData[name];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

const _metricAliases = <String, List<String>>{
  'bertscore': ['bertscore_f1'],
  'rouge_l': ['rouge_l_f1', 'rougeL'],
  'generation_latency_ms': [
    'latency_ms',
    'execution_time_ms',
    'generation_time_ms',
  ],
  'retrieval_coverage': ['coverage'],
};

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

double? _asNullableDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
