import '../../rag_summary/models/Diary_entry.dart';

class DashboardData {
  final String userId;
  final String weekStart;
  final String weekEnd;
  final int evidenceEntryCount;
  final DashboardOverview overview;
  final List<DailyActivityData> dailyActivity;
  final List<CategoryBreakdownItem> categoryBreakdown;
  final List<BreakdownItem> productivityBreakdown;
  final MoodBreakdown moodBreakdown;
  final List<BreakdownItem> outcomeBreakdown;
  final List<DashboardInsight> insights;
  final List<DiaryEntry> recentEntries;
  final DashboardLatestSummary? latestSummary;

  const DashboardData({
    required this.userId,
    required this.weekStart,
    required this.weekEnd,
    required this.evidenceEntryCount,
    required this.overview,
    required this.dailyActivity,
    required this.categoryBreakdown,
    required this.productivityBreakdown,
    required this.moodBreakdown,
    required this.outcomeBreakdown,
    required this.insights,
    required this.recentEntries,
    required this.latestSummary,
  });

  bool get isEmpty => evidenceEntryCount == 0;

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      userId: _asString(json['user_id']),
      weekStart: _asString(json['week_start']),
      weekEnd: _asString(json['week_end']),
      evidenceEntryCount: _asInt(json['evidence_entry_count']),
      overview: DashboardOverview.fromJson(_asMap(json['overview'])),
      dailyActivity: _mapList(
        json['daily_activity'],
        DailyActivityData.fromJson,
      ),
      categoryBreakdown: _mapList(
        json['category_breakdown'],
        CategoryBreakdownItem.fromJson,
      ),
      productivityBreakdown: _mapList(
        json['productivity_breakdown'],
        BreakdownItem.fromJson,
      ),
      moodBreakdown: MoodBreakdown.fromJson(_asMap(json['mood_breakdown'])),
      outcomeBreakdown: _mapList(
        json['outcome_breakdown'],
        BreakdownItem.fromJson,
      ),
      insights: _mapList(json['insights'], DashboardInsight.fromJson),
      recentEntries: _mapList(json['recent_entries'], DiaryEntry.fromJson),
      latestSummary: json['latest_summary'] == null
          ? null
          : DashboardLatestSummary.fromJson(_asMap(json['latest_summary'])),
    );
  }
}

class DashboardOverview {
  final int activityCount;
  final int loggedMinutes;
  final double completionRate;
  final double moodImprovedRate;

  const DashboardOverview({
    required this.activityCount,
    required this.loggedMinutes,
    required this.completionRate,
    required this.moodImprovedRate,
  });

  factory DashboardOverview.fromJson(Map<String, dynamic> json) {
    return DashboardOverview(
      activityCount: _asInt(json['activity_count']),
      loggedMinutes: _asInt(json['logged_minutes']),
      completionRate: _asDouble(json['completion_rate']),
      moodImprovedRate: _asDouble(json['mood_improved_rate']),
    );
  }
}

class DailyActivityData {
  final String date;
  final String dayLabel;
  final int totalMinutes;
  final int entryCount;

  const DailyActivityData({
    required this.date,
    required this.dayLabel,
    required this.totalMinutes,
    required this.entryCount,
  });

  factory DailyActivityData.fromJson(Map<String, dynamic> json) {
    return DailyActivityData(
      date: _asString(json['date']),
      dayLabel: _asString(json['day_label']),
      totalMinutes: _asInt(json['total_minutes']),
      entryCount: _asInt(json['entry_count']),
    );
  }
}

class CategoryBreakdownItem {
  final String category;
  final int totalMinutes;
  final int entryCount;
  final double percentage;

  const CategoryBreakdownItem({
    required this.category,
    required this.totalMinutes,
    required this.entryCount,
    required this.percentage,
  });

  factory CategoryBreakdownItem.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdownItem(
      category: _asString(json['category']),
      totalMinutes: _asInt(json['total_minutes']),
      entryCount: _asInt(json['entry_count']),
      percentage: _asDouble(json['percentage']),
    );
  }
}

class BreakdownItem {
  final String label;
  final int count;
  final double percentage;

  const BreakdownItem({
    required this.label,
    required this.count,
    required this.percentage,
  });

  factory BreakdownItem.fromJson(Map<String, dynamic> json) {
    return BreakdownItem(
      label: _asString(json['label'] ?? json['outcome']),
      count: _asInt(json['count']),
      percentage: _asDouble(json['percentage']),
    );
  }
}

class MoodBreakdown {
  final int improvedCount;
  final int stableCount;
  final int declinedCount;
  final double improvedPercentage;

  const MoodBreakdown({
    required this.improvedCount,
    required this.stableCount,
    required this.declinedCount,
    required this.improvedPercentage,
  });

  int get totalCount => improvedCount + stableCount + declinedCount;

  factory MoodBreakdown.fromJson(Map<String, dynamic> json) {
    return MoodBreakdown(
      improvedCount: _asInt(json['improved_count']),
      stableCount: _asInt(json['stable_count']),
      declinedCount: _asInt(json['declined_count']),
      improvedPercentage: _asDouble(json['improved_percentage']),
    );
  }
}

class DashboardInsight {
  final String title;
  final String message;
  final List<String> evidenceIds;
  final int sampleSize;

  const DashboardInsight({
    required this.title,
    required this.message,
    required this.evidenceIds,
    required this.sampleSize,
  });

  factory DashboardInsight.fromJson(Map<String, dynamic> json) {
    final rawEvidenceIds = json['evidence_ids'];

    return DashboardInsight(
      title: _asString(json['title']),
      message: _asString(json['message']),
      evidenceIds: rawEvidenceIds is List
          ? rawEvidenceIds.map(_asString).where((id) => id.isNotEmpty).toList()
          : const [],
      sampleSize: _asInt(json['sample_size']),
    );
  }
}

class DashboardLatestSummary {
  final String summaryId;
  final String generatedAt;
  final String summaryText;
  final String feedbackMessage;
  final double? groundedClaimRate;
  final double? unsupportedClaimRate;
  final double? citationPrecision;
  final double? citationCompleteness;
  final double? retrievalCoverage;
  final double? bertscore;
  final double? rougeL;
  final double? generationLatencyMs;
  final String? evaluationStatus;

  /// Deprecated compatibility field. It is decoded only and never displayed
  /// or used to derive a research metric.
  @Deprecated('Use the separate groundedness and citation metrics instead.')
  final double? evidenceAccuracy;

  const DashboardLatestSummary({
    required this.summaryId,
    required this.generatedAt,
    required this.summaryText,
    required this.feedbackMessage,
    this.groundedClaimRate,
    this.unsupportedClaimRate,
    this.citationPrecision,
    this.citationCompleteness,
    this.retrievalCoverage,
    this.bertscore,
    this.rougeL,
    this.generationLatencyMs,
    this.evaluationStatus,
    this.evidenceAccuracy,
  });

  factory DashboardLatestSummary.fromJson(Map<String, dynamic> json) {
    return DashboardLatestSummary(
      summaryId: _asString(json['summary_id']),
      generatedAt: _asString(json['generated_at']),
      summaryText: _asString(json['summary_text']),
      feedbackMessage: _asString(json['feedback_message']),
      groundedClaimRate: _asNullableDouble(json['grounded_claim_rate']),
      unsupportedClaimRate: _asNullableDouble(json['unsupported_claim_rate']),
      citationPrecision: _asNullableDouble(json['citation_precision']),
      citationCompleteness: _asNullableDouble(json['citation_completeness']),
      retrievalCoverage: _asNullableDouble(json['retrieval_coverage']),
      bertscore: _asNullableDouble(json['bertscore']),
      rougeL: _asNullableDouble(json['rouge_l']),
      generationLatencyMs: _asNullableDouble(json['generation_latency_ms']),
      evaluationStatus: _asNullableString(json['evaluation_status']),
      evidenceAccuracy: _asNullableDouble(json['evidence_accuracy']),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  if (value is! List) return <T>[];

  return value
      .whereType<Map>()
      .map((item) => fromJson(Map<String, dynamic>.from(item)))
      .toList();
}

String _asString(dynamic value) => value?.toString() ?? '';

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _asNullableDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _asNullableString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
