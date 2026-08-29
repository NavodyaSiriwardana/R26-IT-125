import 'package:cloud_firestore/cloud_firestore.dart';

class ProductivityAnalytics {
  final int completed;
  final int pending;
  final int totalRelevantTasks;

  final int highPriorityTotal;
  final int highPriorityCompleted;

  final int snoozes;
  final int postpones;

  final double completionRate;
  final double priorityAdherence;
  final double behaviourScore;
  final double productivityScore;

  final double completionPoints;
  final double priorityPoints;
  final double behaviourPoints;

  final List<Map<String, dynamic>> relevantTasks;

  final int completedOnTime;
  final int completedLate;
  final int overduePending;

  final int actionableTasks;
  final int actionablePending;
  final int upcoming;

  const ProductivityAnalytics({
    required this.completed,
    required this.pending,
    required this.totalRelevantTasks,
    required this.highPriorityTotal,
    required this.highPriorityCompleted,
    required this.snoozes,
    required this.postpones,
    required this.completionRate,
    required this.priorityAdherence,
    required this.behaviourScore,
    required this.productivityScore,
    required this.completionPoints,
    required this.priorityPoints,
    required this.behaviourPoints,
    required this.relevantTasks,

    required this.completedOnTime,
    required this.completedLate,
    required this.overduePending,

    required this.actionableTasks,
    required this.actionablePending,
    required this.upcoming,
  });
}

class DailyProductivityTrend {
  final DateTime date;
  final int completed;
  final int pending;
  final int snoozes;
  final int postpones;

  final double completionRate;
  final double priorityAdherence;
  final double productivityScore;

  const DailyProductivityTrend({
    required this.date,
    required this.completed,
    required this.pending,
    required this.snoozes,
    required this.postpones,
    required this.completionRate,
    required this.priorityAdherence,
    required this.productivityScore,
  });
}

class ProductivityAnalyticsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }

    return null;
  }

  bool _isRelevantForDay(Map<String, dynamic> task, DateTime day) {
    final deadline = _parseDate(task['deadline']);
    final completedAt = _parseDate(task['completed_at']);
    final scheduleDate = _parseDate(task['schedule_date']);
    final scheduledStart = _parseDate(task['scheduled_start']);
    final availableFrom = _parseDate(task['available_from']);

    final startOfDay = DateTime(day.year, day.month, day.day);

    final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);

    final now = DateTime.now();
    final isToday = _isSameDay(day, now);

    final status = (task['status'] ?? 'pending').toString().toLowerCase();

    final completedToday = completedAt != null && _isSameDay(completedAt, day);

    // Always attribute completion to the day on which it happened.
    if (completedToday) {
      return true;
    }

    // A completed task must not appear as pending on another day.
    if (status == 'completed' || completedAt != null) {
      return false;
    }

    final dueToday = deadline != null && _isSameDay(deadline, day);

    final scheduledToday =
        (scheduleDate != null && _isSameDay(scheduleDate, day)) ||
        (scheduledStart != null && _isSameDay(scheduledStart, day));

    if (isToday) {
      // Include every pending task that has already become available
      // or will become available later today.
      //
      // This allows unscheduled active tasks to appear in today's
      // dashboard even when their deadline is on a future day.
      final availableByEndOfToday =
          availableFrom == null || !availableFrom.isAfter(endOfDay);

      // Also retain overdue pending tasks.
      final overdue = deadline != null && deadline.isBefore(startOfDay);

      return availableByEndOfToday || dueToday || scheduledToday || overdue;
    }

    // Keep historical analytics conservative:
    // use tasks due, scheduled or completed on that historical day.
    return dueToday || scheduledToday;
  }

  double _priorityWeight(Map<String, dynamic> task) {
    switch ((task['priority'] ?? '').toString().toLowerCase()) {
      case 'critical':
        return 4.0;
      case 'high':
        return 3.0;
      case 'medium':
        return 2.0;
      case 'low':
        return 1.0;
      default:
        return 1.0;
    }
  }

  bool _isHighPriority(Map<String, dynamic> task) {
    final priority = (task['priority'] ?? '').toString().toLowerCase();

    return priority == 'critical' || priority == 'high';
  }

  int _countEventsForDay(dynamic history, DateTime day) {
    if (history is! List) {
      return 0;
    }

    int count = 0;

    for (final item in history) {
      if (item is! Map) continue;

      final timestamp = _parseDate(item['timestamp']);

      if (timestamp != null && _isSameDay(timestamp, day)) {
        count++;
      }
    }

    return count;
  }

  Future<ProductivityAnalytics> getAnalyticsForDay(DateTime day) async {
    final snapshot = await _firestore.collection('tasks').get();

    final allTasks = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());

      data['id'] = doc.id;

      return data;
    }).toList();

    return _calculateAnalytics(allTasks, day);
  }

  ProductivityAnalytics _calculateAnalytics(
    List<Map<String, dynamic>> allTasks,
    DateTime day,
  ) {
    final relevantTasks = allTasks
        .where((task) => _isRelevantForDay(task, day))
        .toList();

    final now = DateTime.now();
    final isToday = _isSameDay(day, now);

    int completed = 0;
    int pending = 0;

    int actionablePending = 0;
    int upcoming = 0;

    int highPriorityTotal = 0;
    int highPriorityCompleted = 0;

    int snoozes = 0;
    int postpones = 0;

    int completedOnTime = 0;
    int completedLate = 0;
    int overduePending = 0;

    double totalPriorityWeight = 0.0;
    double completedPriorityWeight = 0.0;

    final scoredTasks = <Map<String, dynamic>>[];

    for (final task in relevantTasks) {
      final completedAt = _parseDate(task['completed_at']);

      final isCompleted = completedAt != null && _isSameDay(completedAt, day);

      final availableFrom = _parseDate(task['available_from']);

      final isSnoozed = task['is_snoozed'] == true;

      final snoozedUntil = _parseDate(task['snoozed_until']);

      final currentlySnoozed =
          isToday &&
          isSnoozed &&
          snoozedUntil != null &&
          snoozedUntil.isAfter(now);

      final snoozeEventsToday = _countEventsForDay(task['snooze_history'], day);

      final postponeEventsToday = _countEventsForDay(
        task['postpone_history'],
        day,
      );

      snoozes += snoozeEventsToday;
      postpones += postponeEventsToday;

      final hasBehaviourEventToday =
          snoozeEventsToday > 0 || postponeEventsToday > 0;

      final hasBecomeAvailable =
          availableFrom == null || !availableFrom.isAfter(now);

      final isActionable =
          !isToday || isCompleted || (hasBecomeAvailable && !currentlySnoozed);

      if (isCompleted) {
        completed++;
      } else {
        pending++;

        if (currentlySnoozed) {
          // Currently snoozed tasks are neither actionable nor genuinely upcoming.
        } else if (isActionable) {
          actionablePending++;
        } else {
          upcoming++;
        }
      }

      // A task that was actionable and then snoozed or postponed today
      // must remain in today's scoring cohort. Otherwise, disrupting a
      // task could incorrectly improve the productivity score.
      final isScoreEligible = isActionable || hasBehaviourEventToday;

      if (isScoreEligible) {
        scoredTasks.add(task);

        final priorityWeight = _priorityWeight(task);

        totalPriorityWeight += priorityWeight;

        if (isCompleted) {
          completedPriorityWeight += priorityWeight;
        }

        if (_isHighPriority(task)) {
          highPriorityTotal++;

          if (isCompleted) {
            highPriorityCompleted++;
          }
        }
      }

      final deadline = _parseDate(task['deadline']);

      if (isCompleted) {
        if (deadline != null) {
          if (completedAt.isAfter(deadline)) {
            completedLate++;
          } else {
            completedOnTime++;
          }
        }
      } else if (deadline != null) {
        final referenceTime = isToday
            ? now
            : DateTime(day.year, day.month, day.day, 23, 59, 59);

        if (deadline.isBefore(referenceTime)) {
          overduePending++;
        }
      }
    }

    final totalRelevantTasks = completed + pending;

    // For today's provisional score, upcoming tasks are excluded.
    // For historical days, every relevant task is included.
    final totalScoredTasks = scoredTasks.length;

    final completionRate = totalScoredTasks > 0
        ? completed / totalScoredTasks
        : 0.0;

    final priorityAdherence = totalPriorityWeight > 0
        ? completedPriorityWeight / totalPriorityWeight
        : 0.0;

    double behaviourScore = 0.0;

    final behaviourEvents = snoozes + postpones;

    final hasExecutionEvidence = completed > 0 || behaviourEvents > 0;

    if (totalScoredTasks > 0 && hasExecutionEvidence) {
      final penalty = behaviourEvents / (totalScoredTasks * 2);

      behaviourScore = (1.0 - penalty).clamp(0.0, 1.0);
    }

    final completionPoints = completionRate * 40.0;
    final priorityPoints = priorityAdherence * 35.0;
    final behaviourPoints = behaviourScore * 25.0;

    final productivityScore =
        (completionPoints + priorityPoints + behaviourPoints).clamp(0.0, 100.0);

    return ProductivityAnalytics(
      completed: completed,
      pending: pending,
      totalRelevantTasks: totalRelevantTasks,

      // Retained for compatibility with other screens/services.
      highPriorityTotal: highPriorityTotal,
      highPriorityCompleted: highPriorityCompleted,

      snoozes: snoozes,
      postpones: postpones,

      completionRate: completionRate,
      priorityAdherence: priorityAdherence,
      behaviourScore: behaviourScore,
      productivityScore: productivityScore,

      completionPoints: completionPoints,
      priorityPoints: priorityPoints,
      behaviourPoints: behaviourPoints,

      relevantTasks: relevantTasks,

      completedOnTime: completedOnTime,
      completedLate: completedLate,
      overduePending: overduePending,

      // Includes completed, currently actionable, and tasks disrupted today.
      actionableTasks: totalScoredTasks,
      actionablePending: actionablePending,
      upcoming: upcoming,
    );
  }

  Future<List<DailyProductivityTrend>> getLast7DaysAnalytics() async {
    final snapshot = await _firestore.collection('tasks').get();

    final allTasks = snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());

      data['id'] = doc.id;

      return data;
    }).toList();

    final now = DateTime.now();

    final List<DailyProductivityTrend> trends = [];

    for (int i = 6; i >= 0; i--) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));

      final analytics = _calculateAnalytics(allTasks, day);

      trends.add(
        DailyProductivityTrend(
          date: day,
          completed: analytics.completed,
          pending: analytics.pending,
          snoozes: analytics.snoozes,
          postpones: analytics.postpones,
          completionRate: analytics.completionRate,
          priorityAdherence: analytics.priorityAdherence,
          productivityScore: analytics.productivityScore,
        ),
      );
    }

    return trends;
  }

  Future<SchedulerPreferenceProfile> getSchedulerPreferenceProfile() async {
    final trends = await getLast7DaysAnalytics();

    final activeDays = trends.where((day) {
      return day.completed + day.pending > 0;
    }).toList();

    // Require at least 3 active days before detecting behaviour patterns.
    final hasEnoughHistory = activeDays.length >= 1;

    if (!hasEnoughHistory) {
      return SchedulerPreferenceProfile(
        hasEnoughHistory: false,
        activeDays: activeDays.length,
        frequentSnoozing: false,
        frequentPostponing: false,
        lowPriorityAdherence: false,
        averageCompletionRate: 0.0,
        averagePriorityAdherence: 0.0,
        recommendations: [
          "More activity history is needed before personalized scheduling recommendations can be generated.",
        ],
      );
    }

    final averageCompletionRate =
        activeDays.map((day) => day.completionRate).reduce((a, b) => a + b) /
        activeDays.length;

    final averagePriorityAdherence =
        activeDays.map((day) => day.priorityAdherence).reduce((a, b) => a + b) /
        activeDays.length;

    final totalSnoozes = activeDays.fold<int>(
      0,
      (sum, day) => sum + day.snoozes,
    );

    final totalPostpones = activeDays.fold<int>(
      0,
      (sum, day) => sum + day.postpones,
    );

    final averageSnoozes = totalSnoozes / activeDays.length;

    final averagePostpones = totalPostpones / activeDays.length;

    final frequentSnoozing = averageSnoozes >= 1.5;

    final frequentPostponing = averagePostpones >= 1.0;

    final lowPriorityAdherence = averagePriorityAdherence < 0.6;

    final List<String> recommendations = [];

    if (frequentSnoozing) {
      recommendations.add(
        "Frequent snoozing was detected across recent active days. Consider scheduling demanding tasks earlier within their available time window.",
      );
    }

    if (frequentPostponing) {
      recommendations.add(
        "Repeated task postponement was detected. Consider splitting longer tasks into smaller scheduling blocks.",
      );
    }

    if (lowPriorityAdherence) {
      recommendations.add(
        "High-priority task completion has been relatively low. Consider reserving earlier available slots for Critical and High priority tasks.",
      );
    }

    if (averageCompletionRate < 0.6) {
      recommendations.add(
        "Recent completion rates suggest the daily workload may be too high. Consider scheduling fewer tasks or shorter work blocks.",
      );
    }

    if (recommendations.isEmpty) {
      recommendations.add(
        "Recent task behaviour is stable. No major scheduling adjustment is currently recommended.",
      );
    }

    return SchedulerPreferenceProfile(
      hasEnoughHistory: true,
      activeDays: activeDays.length,
      frequentSnoozing: frequentSnoozing,
      frequentPostponing: frequentPostponing,
      lowPriorityAdherence: lowPriorityAdherence,
      averageCompletionRate: averageCompletionRate,
      averagePriorityAdherence: averagePriorityAdherence,
      recommendations: recommendations,
    );
  }
}

class SchedulerPreferenceProfile {
  final bool hasEnoughHistory;

  final int activeDays;

  final bool frequentSnoozing;
  final bool frequentPostponing;
  final bool lowPriorityAdherence;

  final double averageCompletionRate;
  final double averagePriorityAdherence;

  final List<String> recommendations;

  const SchedulerPreferenceProfile({
    required this.hasEnoughHistory,
    required this.activeDays,
    required this.frequentSnoozing,
    required this.frequentPostponing,
    required this.lowPriorityAdherence,
    required this.averageCompletionRate,
    required this.averagePriorityAdherence,
    required this.recommendations,
  });
}
