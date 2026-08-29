class DiaryEntry {
  final Object id;
  final String userId;
  final String evidenceId;

  final String activityName;
  final String activityCategory;

  final String startTime;
  final String endTime;
  final int durationMinutes;

  final String productivityLevel;

  final String moodBefore;
  final String moodAfter;

  final String taskOutcome;

  final String? personNames;
  final String healthStatus;

  final String location;
  final String withWhom;

  final String? notes;

  final String entryDate;
  final String weekStart;
  final String weekEnd;

  final String createdAt;
  final String updatedAt;

  DiaryEntry({
    required this.id,
    required this.userId,
    required this.evidenceId,
    required this.activityName,
    required this.activityCategory,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.productivityLevel,
    required this.moodBefore,
    required this.moodAfter,
    required this.taskOutcome,
    required this.personNames,
    required this.healthStatus,
    required this.location,
    required this.withWhom,
    required this.notes,
    required this.entryDate,
    required this.weekStart,
    required this.weekEnd,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    return DiaryEntry(
      id: json['id'] ?? json['evidence_id'] ?? '',
      userId: json['user_id'] ?? '',
      evidenceId: json['evidence_id'] ?? '',
      activityName: json['activity_name'] ?? '',
      activityCategory: json['activity_category'] ?? '',
      startTime: json['start_time'] ?? '',
      endTime: json['end_time'] ?? '',
      durationMinutes: json['duration_minutes'] ?? 0,
      productivityLevel: json['productivity_level'] ?? '',
      moodBefore: json['mood_before'] ?? '',
      moodAfter: json['mood_after'] ?? '',
      taskOutcome: json['task_outcome'] ?? '',
      personNames: json['person_names'],
      healthStatus: json['health_status'] ?? '',
      location: json['location'] ?? '',
      withWhom: json['with_whom'] ?? '',
      notes: json['notes'],
      entryDate: json['entry_date'] ?? '',
      weekStart: json['week_start'] ?? '',
      weekEnd: json['week_end'] ?? '',
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }
}
