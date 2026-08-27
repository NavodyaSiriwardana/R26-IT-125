import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';
import '../services/task_api_service.dart';

import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _cancelTaskNotificationsSafely(String taskId) async {
    try {
      await NotificationService.instance.cancelTaskNotifications(taskId);

      debugPrint('Notifications cancelled for task: $taskId');
    } catch (error, stackTrace) {
      /*
     * A notification cancellation failure must not undo a successfully
     * completed Firestore operation.
     */
      debugPrint(
        'Could not cancel notifications for '
        'task $taskId: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _scheduleSnoozeReminderSafely({
    required String taskId,
    required String taskTitle,
    required DateTime snoozedUntil,
  }) async {
    try {
      final scheduled = await NotificationService.instance
          .scheduleSnoozeReminder(
            taskId: taskId,
            taskTitle: taskTitle,
            snoozedUntil: snoozedUntil,
          );

      debugPrint(
        scheduled
            ? 'Snooze notification scheduled for task: $taskId'
            : 'Snooze notification was not scheduled for task: $taskId',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Could not schedule snooze notification '
        'for task $taskId: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ── Add a new task ────────────────────────────────────────────────────────
  // Returns the new document's Firestore ID so callers (e.g. the form
  // screen) can reliably find THIS exact task after a rerankAllTasks()
  // call, instead of guessing by title/deadline matching.
  Future<String> addTask({required Map<String, dynamic> task}) async {
    final docRef = await _firestore.collection('tasks').add(task);
    return docRef.id;
  }

  // ── Stream all tasks ordered by pred_score ────────────────────────────────
  Stream<List<TaskModel>> getTasks() {
    return _firestore
        .collection('tasks')
        .orderBy('pred_score', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return TaskModel.fromFirestore(doc.data(), doc.id);
          }).toList();
        });
  }

  // ── Fetch ALL tasks as raw maps (doc id included) ─────────────────────────
  // Used by the form screen right after re-ranking, to find the newly added
  // task's final priority/reason_tags for the success dialog.
  Future<List<Map<String, dynamic>>> getAllTasksRaw() async {
    final snapshot = await _firestore
        .collection('tasks')
        .orderBy('pred_score', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  // ── Mark task as completed ────────────────────────────────────────────────
  Future<void> completeTask(String taskId) async {
    await _firestore.collection('tasks').doc(taskId).update({
      "status": "completed",
      "completed_at": DateTime.now().toIso8601String(),
      "completion_status": 1.0,

      "schedule_date": "",
      "schedule_status": "completed",
      "scheduled_start": "",
      "scheduled_end": "",
      "scheduled_parts": [],
      "scheduled_part_count": 0,
      "schedule_failure_reason": "",
    });

    await _cancelTaskNotificationsSafely(taskId);

    await rerankAllTasks();
  }

  // ── Snooze a task ─────────────────────────────────────────────────────────
  Future<void> snoozeTask(
    String taskId,
    int currentCount,
    DateTime snoozedUntil,
  ) async {
    final now = DateTime.now();

    final taskReference = _firestore.collection('tasks').doc(taskId);

    final taskSnapshot = await taskReference.get();

    final taskData = taskSnapshot.data();

    final taskTitle = taskData?['title']?.toString().trim();

    final safeTaskTitle = taskTitle == null || taskTitle.isEmpty
        ? 'Your task'
        : taskTitle;

    await taskReference.update({
      "snooze_count": currentCount + 1,
      "is_snoozed": true,
      "snoozed_until": snoozedUntil.toIso8601String(),

      "schedule_date": "",
      "schedule_status": "unscheduled",
      "scheduled_start": "",
      "scheduled_end": "",
      "scheduled_parts": [],
      "scheduled_part_count": 0,
      "schedule_failure_reason": "",

      "snooze_history": FieldValue.arrayUnion([
        {
          "timestamp": now.toIso8601String(),
          "snoozed_until": snoozedUntil.toIso8601String(),
        },
      ]),
    });

    /*
   * scheduleSnoozeReminder() first cancels the task's existing
   * daily-plan notifications and then creates its snooze reminder.
   */
    await _scheduleSnoozeReminderSafely(
      taskId: taskId,
      taskTitle: safeTaskTitle,
      snoozedUntil: snoozedUntil,
    );

    await rerankAllTasks();
  }

  // ── Unsnooze a task ───────────────────────────────────────────────────────
  Future<void> unsnoozeTask(String taskId) async {
    await _firestore.collection('tasks').doc(taskId).update({
      "is_snoozed": false,
      "snoozed_until": "",

      "schedule_date": "",
      "schedule_status": "unscheduled",
      "scheduled_start": "",
      "scheduled_end": "",
      "scheduled_parts": [],
      "scheduled_part_count": 0,
      "schedule_failure_reason": "",
    });

    await _cancelTaskNotificationsSafely(taskId);

    await rerankAllTasks();
  }

  // ── Postpone a task — updates deadline then re-ranks everything ───────────
  Future<void> postponeTask(
    String taskId,
    int currentCount,
    DateTime newDeadline,
    int estimatedDurationMinutes,
  ) async {
    final deadlineHours =
        newDeadline.difference(DateTime.now()).inSeconds / 3600.0;

    final taskHours = (estimatedDurationMinutes / 60.0)
        .clamp(0.25, double.infinity)
        .toDouble();

    final timePressure = (deadlineHours.clamp(0.0, double.infinity) / taskHours)
        .clamp(0.0, 200.0)
        .toDouble();

    await _firestore.collection('tasks').doc(taskId).update({
      "postpone_count": currentCount + 1,
      "deadline": newDeadline.toIso8601String(),
      "deadline_hours": deadlineHours,
      "time_pressure": timePressure,

      "schedule_date": "",
      "schedule_status": "unscheduled",
      "scheduled_start": "",
      "scheduled_end": "",
      "scheduled_parts": [],
      "scheduled_part_count": 0,
      "schedule_failure_reason": "",

      "postpone_history": FieldValue.arrayUnion([
        {
          "timestamp": DateTime.now().toIso8601String(),
          "new_deadline": newDeadline.toIso8601String(),
        },
      ]),
    });

    await _cancelTaskNotificationsSafely(taskId);

    // The changed deadline and time pressure can affect
    // the ranking of the complete active task set.
    await rerankAllTasks();
  }

  // ── Rerank a SINGLE task in isolation ──────────────────────────────────────
  // Kept for backward compatibility / quick single-task checks, but this
  // does NOT compare the task against the rest of the list. Prefer
  // rerankAllTasks() anywhere ranking actually needs to reflect the full
  // task set (adding a task, postponing a task, deleting a task, etc).
  Future<void> rerankTask(String taskId, Map<String, dynamic> taskData) async {
    final rankedTasks = await TaskApiService.rankTasks([
      {
        "deadline_hours": taskData["deadline_hours"] ?? 24,
        "time_pressure": taskData["time_pressure"] ?? 1,
        "urgency": taskData["urgency"] ?? 0.5,
        "importance_score": taskData["importance_score"] ?? 0.5,
        "severity": taskData["severity"] ?? 0.5,
        "cognitive_load": taskData["cognitive_load"] ?? 0.5,
        "energy_level": taskData["energy_level"] ?? 0.5,
        "category": taskData["category"] ?? "academic",
        "task_duration": taskData["task_duration"] ?? 3,
        "time_of_day": taskData["time_of_day"] ?? 9,
        "day_of_week": taskData["day_of_week"] ?? 0,
      },
    ]);

    final ranked = rankedTasks[0] as Map<String, dynamic>;

    await _firestore.collection('tasks').doc(taskId).update({
      "pred_score": ranked["pred_score"],
      "normalized_score": ranked["normalized_score"],
      "priority": ranked["priority"],
      "reason_tags": ranked["reason_tags"],
    });
  }

  // ── Rerank ALL pending tasks together ──────────────────────────────────────
  // This is the fix for the "only one task ranked alone" bug.
  // XGBRanker is a learning-to-RANK model — it needs the full candidate
  // set to produce meaningful relative scores. Every time the task list
  // changes (add / postpone / delete), the whole pending set is re-sent.
  //
  // NOTE on matching results back to Firestore docs:
  // We tag each outgoing task with its Firestore doc id via "_doc_id".
  // If /rank-tasks on your FastAPI backend simply passes unknown extra
  // fields through untouched (FastAPI + Pydantic will do this only if the
  // request model allows extra fields, or if the backend explicitly
  // echoes the field back), we match by id — this is safe even if the
  // backend reorders results by score.
  // If "_doc_id" is NOT present in the response items, we fall back to
  // assuming the response preserves input order (index-based matching).
  // ⚠️ Confirm with your ranker.py which behavior actually applies — if
  // it strips unknown fields AND reorders by score, index-based matching
  // will silently mismatch tasks. Safest fix on the backend: have
  // /rank-tasks echo back whatever "_doc_id" (or similar passthrough key)
  // it received for each task.

  // ── Mark expired scheduled sessions as missed ───────────────────────────────
  //
  // A task remains pending because missing a scheduled work session does not
  // mean the task itself is completed or its deadline has passed.
  //
  // Existing scheduled timestamps are preserved for history and analytics.

  DateTime? _getFinalScheduledEndFromData(Map<String, dynamic> data) {
    final rawParts = data['scheduled_parts'];

    // For split tasks, use the latest scheduled-part end.
    if (rawParts is List && rawParts.isNotEmpty) {
      DateTime? latestEnd;

      for (final rawPart in rawParts) {
        if (rawPart is! Map) {
          continue;
        }

        final rawEnd = rawPart['scheduled_end']?.toString() ?? '';

        final end = DateTime.tryParse(rawEnd)?.toLocal();

        if (end != null && (latestEnd == null || end.isAfter(latestEnd))) {
          latestEnd = end;
        }
      }

      if (latestEnd != null) {
        return latestEnd;
      }
    }

    final rawEnd = data['scheduled_end']?.toString() ?? '';

    if (rawEnd.isEmpty) {
      return null;
    }

    return DateTime.tryParse(rawEnd)?.toLocal();
  }

  Future<int> markMissedSchedules() async {
    final snapshot = await _firestore
        .collection('tasks')
        .where('schedule_status', isEqualTo: 'scheduled')
        .get();

    if (snapshot.docs.isEmpty) {
      return 0;
    }

    final now = DateTime.now();
    final batch = _firestore.batch();

    int missedCount = 0;

    for (final document in snapshot.docs) {
      final data = document.data();

      final status = data['status']?.toString().toLowerCase() ?? 'pending';

      // Completed tasks must never be converted to missed.
      if (status != 'pending') {
        continue;
      }

      final finalScheduledEnd = _getFinalScheduledEndFromData(data);

      if (finalScheduledEnd == null) {
        continue;
      }

      if (finalScheduledEnd.isBefore(now)) {
        batch.update(document.reference, {
          'schedule_status': 'missed',
          'schedule_failure_reason':
              'The scheduled time passed before the task was completed.',
          'schedule_missed_at': now.toIso8601String(),
        });

        missedCount++;
      }
    }

    if (missedCount > 0) {
      await batch.commit();
    }

    return missedCount;
  }

  Future<void> rerankAllTasks() async {
    // Snoozed tasks are excluded from ranking — "snooze" means "don't show
    // or compare me right now." They rejoin the pool automatically once
    // unsnoozeTask() runs (either manually, or via the auto-unsnooze check
    // in task_list_screen.dart when snoozed_until passes).
    //
    // ⚠️ This is a compound query (status == 'pending' AND is_snoozed ==
    // false). Firestore may prompt you to create a composite index the
    // first time this runs — if so, click the link in the error/console,
    // it's a one-time setup step, not a bug.
    final snapshot = await _firestore
        .collection('tasks')
        .where('status', isEqualTo: 'pending')
        .where('is_snoozed', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) return;

    final docs = snapshot.docs;

    final now = DateTime.now();

    final payload = docs.map((doc) {
      final t = doc.data();

      final deadlineString = t["deadline"]?.toString() ?? "";
      final deadline = DateTime.tryParse(deadlineString);

      final estimatedMinutes =
          (t["estimated_duration_minutes"] as num?)?.toInt() ?? 60;

      double deadlineHours = 24.0;

      if (deadline != null) {
        deadlineHours = deadline.difference(now).inSeconds / 3600.0;

        if (deadlineHours < 0) {
          deadlineHours = 0.0;
        }
      }

      // Matches Stage 1 and training:
      // durations below 15 minutes still use a 0.25-hour floor.
      final taskHours = (estimatedMinutes / 60.0)
          .clamp(0.25, double.infinity)
          .toDouble();

      final timePressure = (deadlineHours / taskHours)
          .clamp(0.0, 200.0)
          .toDouble();

      return {
        "_doc_id": doc.id,

        // Metadata only — XGBRanker does NOT use this as a feature
        "title": t["title"] ?? "",

        "deadline_hours": deadlineHours,
        "time_pressure": timePressure,

        "urgency": t["urgency"] ?? 0.5,
        "urgency_source": (t["score_sources"] is Map)
            ? (t["score_sources"]["urgency"] ?? "calculated")
            : "calculated",

        "importance_score": t["importance_score"] ?? 0.5,
        "severity": t["severity"] ?? 0.5,
        "cognitive_load": t["cognitive_load"] ?? 0.5,
        "energy_level": t["energy_level"] ?? 0.5,

        "category": t["category"] ?? "academic",
        "task_duration": t["task_duration"] ?? 3,
        "time_of_day": t["time_of_day"] ?? 9,
        "day_of_week": t["day_of_week"] ?? 0,
      };
    }).toList();

    final ranked = await TaskApiService.rankTasks(payload);

    if (ranked.length != docs.length) {
      throw StateError(
        "Stage 2 returned ${ranked.length} tasks, "
        "but ${docs.length} were submitted.",
      );
    }

    final returnedIds = ranked
        .map((item) => (item as Map<String, dynamic>)["_doc_id"]?.toString())
        .toSet();

    final expectedIds = docs.map((doc) => doc.id).toSet();

    if (returnedIds.contains(null) ||
        returnedIds.length != expectedIds.length ||
        !returnedIds.containsAll(expectedIds)) {
      throw StateError(
        "Stage 2 response task IDs do not match Firestore task IDs.",
      );
    }

    final batch = _firestore.batch();

    // Check whether the backend echoed "_doc_id" back to us.
    final bool hasDocIdPassthrough =
        ranked.isNotEmpty &&
        (ranked[0] as Map<String, dynamic>).containsKey("_doc_id");

    if (hasDocIdPassthrough) {
      // Safe path — match by id regardless of response order.
      final byId = {for (final doc in docs) doc.id: doc.reference};

      for (final item in ranked) {
        final r = item as Map<String, dynamic>;
        final docId = r["_doc_id"] as String?;
        final ref = docId != null ? byId[docId] : null;
        if (ref == null) continue;

        final updatedUrgency = (r["urgency"] as num?)?.toDouble();

        final updateData = <String, dynamic>{
          "pred_score": r["pred_score"],
          "normalized_score": r["normalized_score"],
          "priority": r["priority"],
          "rank_position": r["rank_position"],
          "reason_tags": r["reason_tags"] ?? [],
          "reason_details": r["reason_details"] ?? [],
          "score_interpretation":
              r["score_interpretation"] ?? "relative_priority_not_probability",
          "deadline_hours": r["deadline_hours"],
          "time_pressure": r["time_pressure"],
        };

        if (updatedUrgency != null) {
          updateData["urgency"] = updatedUrgency;
          updateData["confirmed_scores.urgency"] = updatedUrgency;

          final urgencySource = r["urgency_source"]?.toString() ?? "calculated";

          // Only update the stored automatic value when urgency
          // was not manually adjusted.
          if (urgencySource != "user_adjusted") {
            updateData["model_scores.urgency"] = updatedUrgency;
          }
        }

        batch.update(ref, updateData);
      }
    } else {
      // Fallback path — assumes /rank-tasks preserves input order.
      // ⚠️ If your backend sorts results by score before returning them,
      // this WILL mismatch. Add "_doc_id" passthrough on the backend to
      // avoid relying on this fallback.
      final count = docs.length < ranked.length ? docs.length : ranked.length;
      for (int i = 0; i < count; i++) {
        final r = ranked[i] as Map<String, dynamic>;

        final updatedUrgency = (r["urgency"] as num?)?.toDouble();

        final updateData = <String, dynamic>{
          "pred_score": r["pred_score"],
          "normalized_score": r["normalized_score"],
          "priority": r["priority"],
          "reason_tags": r["reason_tags"],
          "deadline_hours": r["deadline_hours"],
          "time_pressure": r["time_pressure"],
        };

        if (updatedUrgency != null) {
          updateData["urgency"] = updatedUrgency;
          updateData["confirmed_scores.urgency"] = updatedUrgency;

          final urgencySource = r["urgency_source"]?.toString() ?? "calculated";

          if (urgencySource != "user_adjusted") {
            updateData["model_scores.urgency"] = updatedUrgency;
          }
        }

        batch.update(docs[i].reference, updateData);
      }
    }

    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getSchedulableTasksRaw() async {
    final snapshot = await _firestore
        .collection('tasks')
        .where('status', isEqualTo: 'pending')
        .where('is_snoozed', isEqualTo: false)
        .get();

    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());

      return {
        "_doc_id": doc.id,
        "title": data["title"] ?? "",
        "deadline": data["deadline"] ?? "",
        "available_from": data["available_from"] ?? "",
        "estimated_duration_minutes": data["estimated_duration_minutes"] ?? 60,
        "pred_score": data["pred_score"] ?? 0.0,
        "normalized_score": data["normalized_score"] ?? 50,
        "priority": data["priority"] ?? "Medium",
        "cognitive_load": data["cognitive_load"] ?? 0.5,
        "energy_level": data["energy_level"] ?? 0.5,
        "category": data["category"] ?? "academic",
        "is_fixed": data["is_fixed"] ?? false,
        "fixed_start": data["fixed_start"] ?? "",
        "fixed_end": data["fixed_end"] ?? "",
        "is_splittable": data["is_splittable"] ?? false,
      };
    }).toList();
  }

  Future<void> validateScheduleCandidates(Map<String, dynamic> plan) async {
    final scheduled = plan["scheduled_tasks"] as List<dynamic>? ?? [];

    final taskIds = scheduled
        .map((item) {
          final task = Map<String, dynamic>.from(item as Map);

          return task["_doc_id"]?.toString();
        })
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (taskIds.isEmpty) {
      return;
    }

    final documents = await Future.wait(
      taskIds.map((id) => _firestore.collection('tasks').doc(id).get()),
    );

    final invalidTasks = <String>[];

    for (final document in documents) {
      if (!document.exists) {
        invalidTasks.add("A task was removed");

        continue;
      }

      final data = document.data()!;

      final title = data["title"]?.toString() ?? "Untitled task";

      final status = data["status"]?.toString().toLowerCase() ?? "pending";

      final isSnoozed = data["is_snoozed"] == true;

      if (status != "pending") {
        invalidTasks.add("$title is no longer pending");
      } else if (isSnoozed) {
        invalidTasks.add("$title is currently snoozed");
      }
    }

    if (invalidTasks.isNotEmpty) {
      throw StateError(invalidTasks.join("; "));
    }
  }

  Future<void> saveGeneratedSchedule(Map<String, dynamic> result) async {
    final scheduled = result["scheduled_tasks"] as List<dynamic>? ?? [];

    final unscheduled = result["unscheduled_tasks"] as List<dynamic>? ?? [];

    final notConsidered =
        result["not_considered_tasks"] as List<dynamic>? ?? [];

    final batch = _firestore.batch();

    // Group all scheduled parts by their original Firestore task ID.
    final Map<String, List<Map<String, dynamic>>> partsByTask = {};

    for (final item in scheduled) {
      final part = Map<String, dynamic>.from(item as Map);
      final docId = part["_doc_id"]?.toString();

      if (docId == null || docId.isEmpty) continue;

      partsByTask.putIfAbsent(docId, () => []);
      partsByTask[docId]!.add(part);
    }

    for (final entry in partsByTask.entries) {
      final docId = entry.key;
      final parts = entry.value;

      parts.sort((a, b) {
        final aStart = DateTime.parse(a["scheduled_start"].toString());

        final bStart = DateTime.parse(b["scheduled_start"].toString());

        return aStart.compareTo(bStart);
      });

      final firstPart = parts.first;
      final lastPart = parts.last;

      final scheduledParts = parts.map((part) {
        return {
          "part_number": part["part_number"] ?? 1,
          "part_count": part["part_count"] ?? 1,
          "scheduled_start": part["scheduled_start"] ?? "",
          "scheduled_end": part["scheduled_end"] ?? "",
          "duration_minutes": part["estimated_duration_minutes"] ?? 0,
          "break_after_minutes": part["break_after_minutes"] ?? 0,
        };
      }).toList();

      final ref = _firestore.collection('tasks').doc(docId);

      batch.update(ref, {
        "scheduled_start": firstPart["scheduled_start"] ?? "",
        "scheduled_end": lastPart["scheduled_end"] ?? "",
        "scheduled_parts": scheduledParts,
        "scheduled_part_count": parts.length,
        "schedule_date": result["schedule_date"] ?? "",
        "schedule_status": "scheduled",
        "schedule_failure_reason": "",
      });
    }

    for (final item in unscheduled) {
      final task = Map<String, dynamic>.from(item as Map);
      final docId = task["_doc_id"]?.toString();

      if (docId == null || docId.isEmpty) continue;

      final ref = _firestore.collection('tasks').doc(docId);

      batch.update(ref, {
        "scheduled_start": "",
        "scheduled_end": "",
        "scheduled_parts": [],
        "scheduled_part_count": 0,
        "schedule_date": result["schedule_date"] ?? "",
        "schedule_status": "unscheduled",
        "schedule_failure_reason": task["reason"] ?? "Could not be scheduled",
      });
    }

    for (final item in notConsidered) {
      final task = Map<String, dynamic>.from(item as Map);
      final docId = task["_doc_id"]?.toString();

      if (docId == null || docId.isEmpty) continue;

      final ref = _firestore.collection('tasks').doc(docId);

      batch.update(ref, {
        "scheduled_start": "",
        "scheduled_end": "",
        "scheduled_parts": [],
        "scheduled_part_count": 0,
        "schedule_date": result["schedule_date"] ?? "",
        "schedule_status": "not_considered",
        "schedule_failure_reason":
            task["reason"] ?? "Not considered for this plan",
      });
    }

    await batch.commit();
  }

  // ── Delete a task ─────────────────────────────────────────────────────────
  Future<void> deleteTask(String taskId) async {
    await _firestore.collection('tasks').doc(taskId).delete();

    await _cancelTaskNotificationsSafely(taskId);

    // Deleting changes the candidate set.
    await rerankAllTasks();
  }

  // ── Conflict flag check (kept for future use) ─────────────────────────────
  Duration parseDuration(String duration) {
    switch (duration) {
      case "15 min":
        return const Duration(minutes: 15);
      case "30 min":
        return const Duration(minutes: 30);
      case "1 hour":
        return const Duration(hours: 1);
      case "2 hours":
        return const Duration(hours: 2);
      case "4+ hours":
        return const Duration(hours: 4);
      default:
        return const Duration(hours: 1);
    }
  }
}
