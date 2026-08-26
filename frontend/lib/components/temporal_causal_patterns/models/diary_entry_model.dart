class DiaryEntryModel {
  final String userId;
  final String activityName;
  final String activityCategory;
  final String entryDate;
  final String startTime;
  final String endTime;
  final String timePeriod;
  final String duration;
  final String locationType;
  final String customLocation;
  final String withWhom;
  final String specificPerson;
  final String moodBefore;
  final String moodAfter;
  final String healthStatus;
  final String productivityLevel;
  final String taskOutcome;
  final String notes;

  DiaryEntryModel({
    required this.userId,
    required this.activityName,
    required this.activityCategory,
    required this.entryDate,
    required this.startTime,
    required this.endTime,
    required this.timePeriod,
    required this.duration,
    required this.locationType,
    required this.customLocation,
    required this.withWhom,
    required this.specificPerson,
    required this.moodBefore,
    required this.moodAfter,
    required this.healthStatus,
    required this.productivityLevel,
    required this.taskOutcome,
    required this.notes,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'activityName': activityName,
      'activityCategory': activityCategory,
      'entryDate': entryDate,
      'startTime': startTime,
      'endTime': endTime,
      'timePeriod': timePeriod,
      'duration': duration,
      'locationType': locationType,
      'customLocation': customLocation,
      'withWhom': withWhom,
      'specificPerson': specificPerson,
      'moodBefore': moodBefore,
      'moodAfter': moodAfter,
      'healthStatus': healthStatus,
      'productivityLevel': productivityLevel,
      'taskOutcome': taskOutcome,
      'notes': notes,
    };
  }
}