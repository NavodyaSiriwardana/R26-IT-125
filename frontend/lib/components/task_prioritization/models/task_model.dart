class TaskModel {
  final String id;
  final String title;
  final String priority;
  final List<dynamic> reasonTags;
  final String status;
  final int snoozeCount;
  final int postponeCount;
  final String deadline;
  final double predScore;
  final double normalizedScore;
  final String
  category; // ← CHANGED: String not int ("academic", "health" etc.)
  final bool isSnoozed;
  final String snoozedUntil;
  final int conflictFlag;
  final int estimatedDurationMinutes;
  final String availableFrom;
  final String scheduledStart;
  final String scheduledEnd;
  final String scheduleDate;
  final String scheduleStatus;
  final bool isFixed;
  final bool isSplittable;
  final List<Map<String, dynamic>> scheduledParts;
  final int scheduledPartCount;

  TaskModel({
    required this.id,
    required this.title,
    required this.priority,
    required this.reasonTags,
    required this.status,
    required this.snoozeCount,
    required this.postponeCount,
    required this.deadline,
    required this.predScore,
    required this.normalizedScore,
    required this.category,
    required this.isSnoozed,
    required this.snoozedUntil,
    required this.conflictFlag,
    required this.estimatedDurationMinutes,
    required this.availableFrom,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.scheduleDate,
    required this.scheduleStatus,
    required this.isFixed,
    required this.isSplittable,
    required this.scheduledParts,
    required this.scheduledPartCount,
  });

  factory TaskModel.fromFirestore(Map<String, dynamic> data, String docId) {
    return TaskModel(
      id: docId,
      title: data['title'] ?? '',
      priority: data['priority'] ?? 'Medium',
      deadline: data['deadline'] ?? '',
      reasonTags: data['reason_tags'] ?? [],
      status: data['status'] ?? 'pending',
      snoozeCount: (data['snooze_count'] ?? 0).toInt(),
      postponeCount: (data['postpone_count'] ?? 0).toInt(),
      predScore: (data['pred_score'] ?? 0).toDouble(),
      normalizedScore: (data['normalized_score'] as num).toDouble(),
      category: (data['category'] ?? 'general').toString(), // ← safe toString()
      isSnoozed: data['is_snoozed'] ?? false,
      snoozedUntil: data['snoozed_until'] ?? '',
      conflictFlag: (data['conflict_flag'] ?? 0).toInt(),
      estimatedDurationMinutes: (data['estimated_duration_minutes'] ?? 60)
          .toInt(),
      availableFrom: data['available_from'] ?? '',
      scheduledStart: data['scheduled_start'] ?? '',
      scheduledEnd: data['scheduled_end'] ?? '',
      scheduleDate: data['schedule_date'] ?? '',
      scheduleStatus: data['schedule_status'] ?? 'unscheduled',
      isFixed: data['is_fixed'] ?? false,
      isSplittable: data['is_splittable'] ?? false,

      scheduledParts: ((data['scheduled_parts'] as List<dynamic>?) ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),

      scheduledPartCount: (data['scheduled_part_count'] ?? 0).toInt(),
    );
  }
}
