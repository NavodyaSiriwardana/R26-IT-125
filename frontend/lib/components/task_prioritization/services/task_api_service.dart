import 'dart:convert';
import 'package:http/http.dart' as http;

class TaskApiService {
  // Android Emulator → 10.0.2.2   |   Chrome/desktop → 127.0.0.1
  static const String baseUrl = "http://127.0.0.1:8000";

  // ── Stage 2: rank tasks (unchanged) ─────────────────────────────────────
  static Future<List<dynamic>> rankTasks(
    List<Map<String, dynamic>> tasks,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/rank-tasks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(tasks),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to rank tasks: ${response.body}");
    }
  }

  static Future<Map<String, dynamic>> generateSchedule({
    required String planningMode,
    required String scheduleDate,
    required String availableStart,
    required String availableEnd,
    required String breakStrategy,
    required List<Map<String, dynamic>> tasks,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/generate-schedule'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "schedule_date": scheduleDate,
        "available_start": availableStart,
        "available_end": availableEnd,
        "break_strategy": breakStrategy,
        "planning_mode": planningMode,
        "tasks": tasks,
      }),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }

    throw Exception("Failed to generate schedule: ${response.body}");
  }

  // ── Stage 1: predict slider scores from task text + structured fields ───
  // Now sends title + description for NLP embedding in the backend.
  // Returns: { predicted_scores: { urgency, importance_score, severity,
  //                                cognitive_load, energy_level },
  //            deadline_hours, time_pressure }
  static Future<Map<String, dynamic>> predictScores({
    required String title,
    required String description,
    required String category,
    required String startTime,
    required String endTime,
    required int taskDuration,
    required int estimatedDurationMinutes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/predict-scores'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "title": title,
        "description": description,
        "category": category,
        "start_time": startTime,
        "end_time": endTime,
        "task_duration": taskDuration,
        "estimated_duration_minutes": estimatedDurationMinutes,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to predict scores: ${response.body}");
    }
  }

  static Future<Map<String, dynamic>> generateReflection({
    required double completionRate,
    required double priorityAdherence,
    required int completed,
    required int pending,

    required int actionablePending,
    required int upcoming,
    required int scoredTaskCount,
    required bool isProvisional,
    required double scheduleStability,

    required int snoozes,
    required int postpones,
    required int highCognitivePostponed,
    required Map<String, int> completedByCategory,
    required Map<String, int> pendingByCategory,
    required int tomorrowHighPriorityCount,
    required int highPriorityTotal,
    required int highPriorityCompleted,
    required int pendingHighPriorityCount,
    required List<Map<String, dynamic>> pendingHighPriorityTasks,

    required int overdueTaskCount,
    required int overdueHighPriorityCount,
    required List<Map<String, dynamic>> overdueTasks,
    required List<Map<String, dynamic>> overdueHighPriorityTasks,

    required int completedOnTime,
    required int completedLate,
    required int overduePending,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/generate-reflection'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'completion_rate': completionRate,

        // This now represents weighted adherence across
        // Critical, High, Medium and Low tasks.
        'priority_adherence': priorityAdherence,

        // Absence of snooze/postpone disruptions.
        'schedule_stability': scheduleStability,

        'completed': completed,
        'pending': pending,
        'actionable_pending': actionablePending,
        'upcoming': upcoming,
        'scored_task_count': scoredTaskCount,
        'is_provisional': isProvisional,

        'snoozes': snoozes,
        'postpones': postpones,
        'high_cognitive_postponed': highCognitivePostponed,
        'completed_by_category': completedByCategory,
        'pending_by_category': pendingByCategory,
        'tomorrow_high_priority_count': tomorrowHighPriorityCount,

        'high_priority_total': highPriorityTotal,
        'high_priority_completed': highPriorityCompleted,
        'pending_high_priority_count': pendingHighPriorityCount,
        'pending_high_priority_tasks': pendingHighPriorityTasks,

        'overdue_task_count': overdueTaskCount,
        'overdue_high_priority_count': overdueHighPriorityCount,
        'overdue_tasks': overdueTasks,
        'overdue_high_priority_tasks': overdueHighPriorityTasks,

        'completed_on_time': completedOnTime,
        'completed_late': completedLate,
        'overdue_pending': overduePending,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to generate reflection: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
