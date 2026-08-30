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

  String get shortInsight {
    final triggerParts = trigger
        .split(' + ')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final outcomeText = _cleanOutcome(outcome);

    String? personName;
    for (var part in triggerParts) {
      if (part.startsWith('with ') && !_isGenericSocial(part)) {
        personName = part.replaceFirst('with ', '').trim();
        break;
      }
    }
    if (personName != null) {
      return 'After meeting $personName → $outcomeText';
    }

    final category = triggerParts.isNotEmpty ? triggerParts[0] : null;

    String? timePeriod;
    for (var part in triggerParts) {
      if (['Morning', 'Afternoon', 'Evening', 'Night']
          .contains(part)) {
        timePeriod = part;
        break;
      }
    }

    String? socialContext;
    for (var part in triggerParts) {
      if (['Group', 'Friends', 'Alone', 'Partner', 'Lecturer']
          .contains(part)) {
        socialContext = part;
        break;
      }
    }

    final buffer = StringBuffer('After ');
    buffer.write(category != null && category.isNotEmpty
        ? _naturalizeCategory(category)
        : 'this activity');

    if (socialContext != null) buffer.write(' with $socialContext');
    if (timePeriod != null) {
      buffer.write(' on ${timePeriod.toLowerCase()}');
    }
    buffer.write(' → $outcomeText');

    return buffer.toString();
  }

  bool get isCrossDay {
    final text = dfsExplanation.toLowerCase();
    return text.contains('next entry') ||
        text.contains('next morning') ||
        text.contains('next day') ||
        text.contains('following entry') ||
        text.contains('hours later');
  }

  String _cleanOutcome(String raw) {
    return raw
        .replaceAll('moodAfter = ', 'mood becomes ')
        .replaceAll('healthStatus = ', 'health becomes ')
        .replaceAll('productivityLevel = ', 'productivity becomes ')
        .replaceAll('taskOutcome = ', 'task becomes ')
        .toLowerCase()
        .trim();
  }

  String _naturalizeCategory(String category) {
    if (category == category.toUpperCase() && category.length <= 6) {
      return category;
    }
    return category.toLowerCase();
  }

  bool _isGenericSocial(String part) {
    const generic = [
      'with Alone', 'with Group', 'with Friends',
      'with Partner', 'with Lecturer',
    ];
    return generic.contains(part);
  }
}