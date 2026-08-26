class PatternModel {
  final String insightText;
  final String trigger;
  final String outcome;
  final int matchedCount;
  final int totalTriggerCount;
  final double confidencePercentage;
  final String patternLevel;
  final List<String> evidenceDates;
  final double dfsScore;
  final double louvainScore;
  final double fftScore;
  final double htgpsScore;
  final String dfsExplanation;
  final String louvainExplanation;
  final String fftExplanation;
  final String analysisVersion;

  PatternModel({
    required this.insightText,
    required this.trigger,
    required this.outcome,
    required this.matchedCount,
    required this.totalTriggerCount,
    required this.confidencePercentage,
    required this.patternLevel,
    required this.evidenceDates,
    required this.dfsScore,
    required this.louvainScore,
    required this.fftScore,
    required this.htgpsScore,
    required this.dfsExplanation,
    required this.louvainExplanation,
    required this.fftExplanation,
    required this.analysisVersion,
  });

  factory PatternModel.fromJson(Map<String, dynamic> json) {
    return PatternModel(
      insightText: json['insightText'] ?? '',
      trigger: json['trigger'] ?? '',
      outcome: json['outcome'] ?? '',
      matchedCount: json['matchedCount'] ?? 0,
      totalTriggerCount: json['totalTriggerCount'] ?? 0,
      confidencePercentage:
          (json['confidencePercentage'] ?? 0).toDouble(),
      patternLevel: json['patternLevel'] ?? '',
      evidenceDates: List<String>.from(
          json['evidenceDates'] ?? []),
      dfsScore: (json['dfsScore'] ?? 0).toDouble(),
      louvainScore: (json['louvainScore'] ?? 0).toDouble(),
      fftScore: (json['fftScore'] ?? 0).toDouble(),
      htgpsScore: (json['htgpsScore'] ?? 0).toDouble(),
      dfsExplanation: json['dfsExplanation'] ?? '',
      louvainExplanation: json['louvainExplanation'] ?? '',
      fftExplanation: json['fftExplanation'] ?? '',
      analysisVersion: json['analysisVersion'] ?? '',
    );
  }
}