import 'dart:async';

import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../services/firestore_service.dart';
import 'smart_task_form_screen.dart';
import 'package:intl/intl.dart';

import 'notification_preferences_screen.dart';

class TaskListScreen extends StatefulWidget {
  final ValueNotifier<String?> taskToReveal;

  const TaskListScreen({super.key, required this.taskToReveal});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  late final Stream<List<TaskModel>> _tasksStream;

  Timer? refreshTimer;
  Timer? rankingRefreshTimer;

  final ExpansibleController _activeTasksController = ExpansibleController();

  final Map<String, GlobalKey> _taskCardKeys = {};

  Timer? _highlightTimer;

  String? _highlightedTaskId;

  bool _rankingRefreshInProgress = false;

  final Set<String> _busyTaskIds = <String>{};

  final Set<String> _expiredSnoozeUpdatesInProgress = <String>{};

  GlobalKey _taskCardKey(String taskId) {
    return _taskCardKeys.putIfAbsent(taskId, GlobalKey.new);
  }

  Future<void> _refreshTimeSensitiveRankings() async {
    if (_rankingRefreshInProgress) {
      return;
    }

    _rankingRefreshInProgress = true;

    try {
      final missedCount = await firestoreService.markMissedSchedules();

      if (missedCount > 0) {
        debugPrint('$missedCount expired schedule(s) marked as missed.');
      }

      await firestoreService.rerankAllTasks();

      if (mounted) {
        setState(() {});
      }
    } catch (error, stackTrace) {
      debugPrint("Time-sensitive ranking refresh failed: $error");

      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _rankingRefreshInProgress = false;
    }
  }

  void _handleTaskRevealRequest() {
    final taskId = widget.taskToReveal.value;

    if (taskId == null || taskId.isEmpty) {
      return;
    }

    _highlightTimer?.cancel();

    if (mounted) {
      setState(() {
        _highlightedTaskId = taskId;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        _activeTasksController.expand();
      } catch (error) {
        debugPrint('Could not expand Active Tasks: $error');
      }

      _scrollToTask(taskId, remainingAttempts: 6);
    });

    _highlightTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;

      if (_highlightedTaskId == taskId) {
        setState(() {
          _highlightedTaskId = null;
        });
      }
    });
  }

  Future<void> _scrollToTask(
    String taskId, {
    required int remainingAttempts,
  }) async {
    if (!mounted) {
      return;
    }

    final taskContext = _taskCardKeys[taskId]?.currentContext;

    if (taskContext != null) {
      await Scrollable.ensureVisible(
        taskContext,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );

      debugPrint('Revealed notification task card: $taskId');

      return;
    }

    if (remainingAttempts <= 0) {
      debugPrint(
        'Could not find notification task card: '
        '$taskId',
      );

      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));

    await _scrollToTask(taskId, remainingAttempts: remainingAttempts - 1);
  }

  @override
  void initState() {
    super.initState();

    _tasksStream = firestoreService.getTasks();

    widget.taskToReveal.addListener(_handleTaskRevealRequest);

    // Refresh visual countdown and deadline labels.
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() {});
      }
    });

    // Recalculate time-sensitive ranking when this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshTimeSensitiveRankings();
    });

    // Keep urgency and timing features reasonably current.
    rankingRefreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _refreshTimeSensitiveRankings();
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    rankingRefreshTimer?.cancel();

    widget.taskToReveal.removeListener(_handleTaskRevealRequest);

    _highlightTimer?.cancel();
    _activeTasksController.dispose();

    super.dispose();
  }

  final FirestoreService firestoreService = FirestoreService();

  Color getPriorityColor(String priority) {
    switch (priority) {
      case "Critical":
        return Colors.deepPurpleAccent;
      case "High":
        return Colors.redAccent;
      case "Medium":
        return Colors.orangeAccent;
      case "Low":
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  String getPriorityRangeLabel(TaskModel task) {
    final score = task.normalizedScore;
    final priority = task.priority.toLowerCase();

    switch (priority) {
      case "critical":
        return score < 87.5 ? "Lower Critical range" : "Upper Critical range";

      case "high":
        return score < 62.5 ? "Lower High range" : "Upper High range";

      case "medium":
        return score < 37.5 ? "Lower Medium range" : "Upper Medium range";

      case "low":
        return score < 12.5 ? "Lower Low range" : "Upper Low range";

      default:
        return "Relative priority";
    }
  }

  Widget _buildStage2Badge() {
    const color = Color(0xFF9B87FF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_graph_rounded, color: color, size: 13),
          SizedBox(width: 5),
          Text(
            "RELATIVE PRIORITY",
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
            ),
          ),
        ],
      ),
    );
  }

  // ── FIXED: category is now a String ("academic", "health" etc.) ───────────
  String getCategoryName(String category) {
    switch (category.toLowerCase()) {
      case "academic":
        return "Academic";
      case "health":
        return "Health";
      case "personal":
        return "Personal";
      case "finance":
        return "Finance";
      case "social":
        return "Social";
      case "extracurricular":
        return "Extracurricular";
      // Legacy int values (in case old tasks still exist in Firestore)
      case "0":
        return "Academic";
      case "1":
        return "Health";
      case "2":
        return "Personal";
      case "3":
        return "Finance";
      case "4":
        return "Social";
      case "5":
        return "Extracurricular";
      default:
        return "General";
    }
  }

  void _queueExpiredSnoozeCleanup(List<TaskModel> tasks) {
    final now = DateTime.now();

    final expiredTaskIds = tasks
        .where((task) {
          if (!task.isSnoozed || task.snoozedUntil.isEmpty) {
            return false;
          }

          final snoozedUntil = DateTime.tryParse(task.snoozedUntil)?.toLocal();

          return snoozedUntil != null &&
              !snoozedUntil.isAfter(now) &&
              !_expiredSnoozeUpdatesInProgress.contains(task.id);
        })
        .map((task) => task.id)
        .toList();

    if (expiredTaskIds.isEmpty) {
      return;
    }

    // Reserve these IDs immediately so another build cannot queue them again.
    _expiredSnoozeUpdatesInProgress.addAll(expiredTaskIds);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _expiredSnoozeUpdatesInProgress.removeAll(expiredTaskIds);
        return;
      }

      for (final taskId in expiredTaskIds) {
        try {
          await firestoreService.unsnoozeTask(taskId);
        } catch (error, stackTrace) {
          debugPrint(
            'Could not automatically resume expired snooze '
            'for $taskId: $error',
          );

          debugPrintStack(stackTrace: stackTrace);
        } finally {
          _expiredSnoozeUpdatesInProgress.remove(taskId);
        }
      }
    });
  }

  Future<void> _runTaskAction({
    required String taskId,
    required Future<void> Function() action,
    required String errorMessage,
  }) async {
    if (_busyTaskIds.contains(taskId)) {
      return;
    }

    setState(() {
      _busyTaskIds.add(taskId);
    });

    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('$errorMessage: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.redAccent,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyTaskIds.remove(taskId);
        });
      } else {
        _busyTaskIds.remove(taskId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Smart Task List"),
        actions: [
          IconButton(
            tooltip: 'Notification preferences',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationPreferencesScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurpleAccent,
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SmartTaskFormScreen()),
          );
        },
      ),

      body: StreamBuilder<List<TaskModel>>(
        stream: _tasksStream,
        builder: (context, snapshot) {
          // ── Error state ──────────────────────────────────────────────────
          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error loading tasks:\n${snapshot.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          // ── Loading state ────────────────────────────────────────────────
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final tasks = snapshot.data!;

          _queueExpiredSnoozeCleanup(tasks);

          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_alt, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    "No tasks yet",
                    style: TextStyle(color: Colors.white54, fontSize: 18),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Tap + to add your first task",
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          // ── Filter tasks ─────────────────────────────────────────────────
          final now = DateTime.now();

          final activeTasks = tasks.where((task) {
            if (task.status == "completed") {
              return false;
            }

            if (!task.isSnoozed) {
              return true;
            }

            if (task.snoozedUntil.isEmpty) {
              return true;
            }

            final snoozedUntil = DateTime.tryParse(
              task.snoozedUntil,
            )?.toLocal();

            if (snoozedUntil == null) {
              return true;
            }

            // Expired snoozes appear immediately while Firestore is updated
            // safely after the current frame.
            return !snoozedUntil.isAfter(now);
          }).toList();

          final completedTasks = tasks
              .where((t) => t.status == "completed")
              .toList();

          final snoozedTasks = tasks.where((task) {
            if (task.status == "completed" ||
                !task.isSnoozed ||
                task.snoozedUntil.isEmpty) {
              return false;
            }

            final snoozedUntil = DateTime.tryParse(
              task.snoozedUntil,
            )?.toLocal();

            return snoozedUntil != null && snoozedUntil.isAfter(now);
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Text(
                DateFormat('EEEE, MMM d').format(DateTime.now()),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),

              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ExpansionTile(
                  controller: _activeTasksController,
                  key: const PageStorageKey<String>("active-tasks"),
                  expansionAnimationStyle: const AnimationStyle(
                    duration: Duration(milliseconds: 180),
                    reverseDuration: Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                  initiallyExpanded: true,
                  maintainState: false,
                  leading: const Icon(
                    Icons.pending_actions_rounded,
                    color: Colors.deepPurpleAccent,
                  ),
                  title: Text(
                    "Active Tasks (${activeTasks.length})",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    "Tasks that currently need your attention",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  children: activeTasks.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.all(18),
                            child: Text(
                              "No active tasks",
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        ]
                      : activeTasks
                            .map(
                              (task) => KeyedSubtree(
                                key: _taskCardKey(task.id),
                                child: RepaintBoundary(
                                  child: buildTaskCard(context, task),
                                ),
                              ),
                            )
                            .toList(),
                ),
              ),

              const SizedBox(height: 12),

              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ExpansionTile(
                  key: const PageStorageKey<String>("completed-tasks"),
                  expansionAnimationStyle: const AnimationStyle(
                    duration: Duration(milliseconds: 180),
                    reverseDuration: Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                  maintainState: false,
                  leading: const Icon(
                    Icons.task_alt_rounded,
                    color: Colors.greenAccent,
                  ),
                  title: Text(
                    "Completed Tasks (${completedTasks.length})",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    "Tasks you have already finished",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  children: completedTasks.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.all(18),
                            child: Text(
                              "No completed tasks",
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        ]
                      : completedTasks
                            .map(
                              (task) => RepaintBoundary(
                                key: ValueKey('completed-${task.id}'),
                                child: buildTaskCard(context, task),
                              ),
                            )
                            .toList(),
                ),
              ),

              const SizedBox(height: 12),

              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ExpansionTile(
                  key: const PageStorageKey<String>("snoozed-tasks"),
                  expansionAnimationStyle: const AnimationStyle(
                    duration: Duration(milliseconds: 180),
                    reverseDuration: Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                  maintainState: false,
                  leading: Icon(
                    Icons.snooze_rounded,
                    color: snoozedTasks.isEmpty
                        ? Colors.white38
                        : Colors.cyanAccent,
                  ),
                  title: Text(
                    "Snoozed Tasks (${snoozedTasks.length})",
                    style: TextStyle(
                      color: snoozedTasks.isEmpty
                          ? Colors.white54
                          : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    snoozedTasks.isEmpty
                        ? "No snoozed tasks"
                        : "Tasks temporarily paused until later",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  children: snoozedTasks
                      .map(
                        (task) => RepaintBoundary(
                          key: ValueKey('snoozed-${task.id}'),
                          child: buildTaskCard(context, task),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String formatDuration(int totalMinutes) {
    if (totalMinutes < 60) {
      return "$totalMinutes min";
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (minutes == 0) {
      return hours == 1 ? "1 hour" : "$hours hours";
    }

    return "${hours}h ${minutes}m";
  }

  String formatAvailableFrom(String value) {
    if (value.isEmpty) return "Not specified";

    final date = DateTime.tryParse(value)?.toLocal();

    if (date == null) return "Invalid date";

    final now = DateTime.now();

    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    final tomorrow = now.add(const Duration(days: 1));

    final isTomorrow =
        date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day;

    if (isToday) {
      return "Today • ${DateFormat('h:mm a').format(date)}";
    }

    if (isTomorrow) {
      return "Tomorrow • ${DateFormat('h:mm a').format(date)}";
    }

    return DateFormat('MMM d • h:mm a').format(date);
  }

  String formatDeadline(String value) {
    if (value.isEmpty) return "No deadline";

    final deadline = DateTime.tryParse(value)?.toLocal();

    if (deadline == null) return "Invalid deadline";

    final now = DateTime.now();

    if (deadline.isBefore(now)) {
      return "Overdue • ${DateFormat('MMM d • h:mm a').format(deadline)}";
    }

    final isToday =
        deadline.year == now.year &&
        deadline.month == now.month &&
        deadline.day == now.day;

    final tomorrow = now.add(const Duration(days: 1));

    final isTomorrow =
        deadline.year == tomorrow.year &&
        deadline.month == tomorrow.month &&
        deadline.day == tomorrow.day;

    if (isToday) {
      return "Today • ${DateFormat('h:mm a').format(deadline)}";
    }

    if (isTomorrow) {
      return "Tomorrow • ${DateFormat('h:mm a').format(deadline)}";
    }

    return DateFormat('MMM d • h:mm a').format(deadline);
  }

  bool isTaskOverdue(TaskModel task) {
    if (task.status.toLowerCase() == "completed") {
      return false;
    }

    final deadline = DateTime.tryParse(task.deadline)?.toLocal();

    return deadline != null && deadline.isBefore(DateTime.now());
  }

  String getDisplayReason(TaskModel task, Object reason) {
    final reasonText = reason.toString();

    if (!isTaskOverdue(task)) {
      return reasonText;
    }

    const deadlineReasons = {
      "Closer deadline than the other tasks",
      "Deadline is very close",
      "Due within the next day",
      "Tighter completion window than the other tasks",
      "More time remains before its deadline",
    };

    if (deadlineReasons.contains(reasonText)) {
      return "Its deadline has already passed";
    }

    return reasonText;
  }

  String getDeadlineSummary(TaskModel task) {
    if (task.deadline.isEmpty) {
      return "No deadline";
    }

    final deadline = DateTime.tryParse(task.deadline)?.toLocal();

    if (deadline == null) {
      return "Deadline unavailable";
    }

    final now = DateTime.now();
    final difference = deadline.difference(now);

    if (difference.isNegative && task.status != "completed") {
      final overdueBy = now.difference(deadline);

      if (overdueBy.inDays >= 1) {
        return "Overdue by ${overdueBy.inDays} "
            "${overdueBy.inDays == 1 ? "day" : "days"}";
      }

      if (overdueBy.inHours >= 1) {
        return "Overdue by ${overdueBy.inHours} "
            "${overdueBy.inHours == 1 ? "hour" : "hours"}";
      }

      return "Overdue by ${overdueBy.inMinutes} min";
    }

    if (task.status == "completed") {
      return "Completed";
    }

    if (difference.inDays >= 1) {
      return "${difference.inDays} "
          "${difference.inDays == 1 ? "day" : "days"} remaining";
    }

    if (difference.inHours >= 1) {
      final remainingMinutes = difference.inMinutes % 60;

      if (remainingMinutes == 0) {
        return "${difference.inHours} "
            "${difference.inHours == 1 ? "hour" : "hours"} remaining";
      }

      return "${difference.inHours}h ${remainingMinutes}m remaining";
    }

    return "${difference.inMinutes.clamp(0, 59)} min remaining";
  }

  DateTime? getFinalScheduledEnd(TaskModel task) {
    // For split tasks, use the end time of the final scheduled part.
    if (task.scheduledParts.isNotEmpty) {
      DateTime? latestEnd;

      for (final part in task.scheduledParts) {
        final rawEnd = part['scheduled_end']?.toString() ?? '';
        final end = DateTime.tryParse(rawEnd)?.toLocal();

        if (end != null && (latestEnd == null || end.isAfter(latestEnd))) {
          latestEnd = end;
        }
      }

      if (latestEnd != null) {
        return latestEnd;
      }
    }

    if (task.scheduledEnd.isEmpty) {
      return null;
    }

    return DateTime.tryParse(task.scheduledEnd)?.toLocal();
  }

  bool hasMissedSchedule(TaskModel task) {
    if (task.status == "completed") {
      return false;
    }

    // Supports both persisted and not-yet-persisted missed states.
    if (task.scheduleStatus != "scheduled" && task.scheduleStatus != "missed") {
      return false;
    }

    final finalScheduledEnd = getFinalScheduledEnd(task);

    if (finalScheduledEnd == null) {
      return false;
    }

    return finalScheduledEnd.isBefore(DateTime.now());
  }

  bool hasValidScheduledTime(TaskModel task) {
    if (task.status == "completed") {
      return false;
    }

    if (task.scheduleStatus != "scheduled") {
      return false;
    }

    if (hasMissedSchedule(task)) {
      return false;
    }

    if (task.scheduledStart.isEmpty ||
        task.scheduledEnd.isEmpty ||
        task.scheduleDate.isEmpty) {
      return false;
    }

    final start = DateTime.tryParse(task.scheduledStart)?.toLocal();

    final end = DateTime.tryParse(task.scheduledEnd)?.toLocal();

    final scheduleDate = DateTime.tryParse(task.scheduleDate);

    return start != null && end != null && scheduleDate != null;
  }

  String formatScheduledTime(TaskModel task) {
    final start = DateTime.parse(task.scheduledStart).toLocal();
    final end = DateTime.parse(task.scheduledEnd).toLocal();

    final now = DateTime.now();

    final isToday =
        start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;

    final dateLabel = isToday ? "Today" : DateFormat('MMM d').format(start);

    return "$dateLabel • "
        "${DateFormat('h:mm a').format(start)} – "
        "${DateFormat('h:mm a').format(end)}";
  }

  String formatMissedScheduledTime(TaskModel task) {
    final start = DateTime.tryParse(task.scheduledStart)?.toLocal();

    final end = getFinalScheduledEnd(task);

    if (start == null || end == null) {
      return "Previous schedule expired";
    }

    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    final wasYesterday =
        start.year == yesterday.year &&
        start.month == yesterday.month &&
        start.day == yesterday.day;

    final dateLabel = wasYesterday
        ? "Yesterday"
        : DateFormat('MMM d').format(start);

    return "$dateLabel • "
        "${DateFormat('h:mm a').format(start)} – "
        "${DateFormat('h:mm a').format(end)}";
  }

  Color getDeadlineColor(TaskModel task) {
    if (task.deadline.isEmpty) return Colors.white70;

    final deadline = DateTime.tryParse(task.deadline)?.toLocal();

    if (deadline == null) return Colors.white70;

    final now = DateTime.now();

    if (deadline.isBefore(now) && task.status != "completed") {
      return Colors.redAccent;
    }

    final isToday =
        deadline.year == now.year &&
        deadline.month == now.month &&
        deadline.day == now.day;

    final tomorrow = now.add(const Duration(days: 1));

    final isTomorrow =
        deadline.year == tomorrow.year &&
        deadline.month == tomorrow.month &&
        deadline.day == tomorrow.day;

    if (isToday) return Colors.orangeAccent;
    if (isTomorrow) return Colors.lightBlueAccent;

    return Colors.white70;
  }

  Widget buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color iconColor = Colors.white54,
    Color valueColor = Colors.white70,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMetadata({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool isUpcomingTask(TaskModel task) {
    if (task.status == "completed" || task.availableFrom.isEmpty) {
      return false;
    }

    final availableFrom = DateTime.tryParse(task.availableFrom)?.toLocal();

    if (availableFrom == null) {
      return false;
    }

    return availableFrom.isAfter(DateTime.now());
  }

  String getDisplayStatus(TaskModel task) {
    if (task.status == "completed") {
      return "Completed";
    }

    if (task.isSnoozed && task.snoozedUntil.isNotEmpty) {
      final snoozedUntil = DateTime.tryParse(task.snoozedUntil)?.toLocal();

      if (snoozedUntil != null && snoozedUntil.isAfter(DateTime.now())) {
        return "Snoozed";
      }
    }

    if (hasMissedSchedule(task)) {
      return "Needs rescheduling";
    }

    // A saved schedule takes precedence over availability status.
    if (hasValidScheduledTime(task)) {
      return "Scheduled";
    }

    if (isUpcomingTask(task)) {
      return "Upcoming";
    }

    return "Active";
  }

  Color getDisplayStatusColor(String status) {
    switch (status) {
      case "Completed":
        return Colors.greenAccent;

      case "Snoozed":
        return Colors.cyanAccent;

      case "Scheduled":
        return Colors.deepPurpleAccent;

      case "Upcoming":
        return Colors.cyanAccent;

      case "Needs rescheduling":
        return Colors.orangeAccent;

      case "Active":
        return Colors.orangeAccent;

      default:
        return Colors.white70;
    }
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
      onTap: onTap,
    );
  }

  Future<void> _showSnoozeOptions(BuildContext context, TaskModel task) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF172235),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Future<void> snoozeFor(Duration duration) async {
          Navigator.pop(sheetContext);

          await firestoreService.snoozeTask(
            task.id,
            task.snoozeCount,
            DateTime.now().add(duration),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Snooze task",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Hide this task temporarily. It will return automatically.",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),

                _buildActionTile(
                  icon: Icons.timer_outlined,
                  title: "10 minutes",
                  subtitle: "Return shortly",
                  color: Colors.cyanAccent,
                  onTap: () => snoozeFor(const Duration(minutes: 10)),
                ),

                _buildActionTile(
                  icon: Icons.timer_outlined,
                  title: "20 minutes",
                  subtitle: "Take a short break",
                  color: Colors.cyanAccent,
                  onTap: () => snoozeFor(const Duration(minutes: 20)),
                ),

                _buildActionTile(
                  icon: Icons.schedule_rounded,
                  title: "1 hour",
                  subtitle: "Return later today",
                  color: Colors.cyanAccent,
                  onTap: () => snoozeFor(const Duration(hours: 1)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _postponeTask(TaskModel task) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime == null || !mounted) return;

    final newDeadline = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    await firestoreService.postponeTask(
      task.id,
      task.postponeCount,
      newDeadline,
      task.estimatedDurationMinutes,
    );
  }

  Future<void> _confirmDeleteTask(TaskModel task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF172235),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              SizedBox(width: 10),
              Text("Delete task?"),
            ],
          ),
          content: Text(
            "“${task.title}” will be permanently removed. "
            "This action cannot be undone.",
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text("Cancel"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await firestoreService.deleteTask(task.id);
    }
  }

  Future<void> _showTaskActions(BuildContext context, TaskModel task) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF172235),
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Task actions",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                if (task.isSnoozed)
                  _buildActionTile(
                    icon: Icons.play_arrow_rounded,
                    title: "Resume now",
                    subtitle: "Return this task to the active list",
                    color: Colors.greenAccent,
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await firestoreService.unsnoozeTask(task.id);
                    },
                  )
                else
                  _buildActionTile(
                    icon: Icons.snooze_rounded,
                    title: "Snooze",
                    subtitle: "Temporarily hide this task",
                    color: Colors.cyanAccent,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _showSnoozeOptions(context, task);
                    },
                  ),

                _buildActionTile(
                  icon: Icons.event_repeat_rounded,
                  title: isTaskOverdue(task)
                      ? "Reschedule deadline"
                      : "Postpone",
                  subtitle: isTaskOverdue(task)
                      ? "Choose a new deadline for this overdue task"
                      : "Move the task deadline",
                  color: Colors.orangeAccent,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _postponeTask(task);
                  },
                ),

                const Divider(height: 24),

                _buildActionTile(
                  icon: Icons.delete_outline_rounded,
                  title: "Delete task",
                  subtitle: "Permanently remove this task",
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmDeleteTask(task);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPriorityExplanation(
    BuildContext context,
    TaskModel task,
  ) async {
    final priorityColor = getPriorityColor(task.priority);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF172235),
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStage2Badge(),

                const SizedBox(height: 16),

                Text(
                  "Why “${task.title}” is ${task.priority}",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  "The Stage 2 ranking model compared this task with "
                  "your other pending tasks.",
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: priorityColor.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Priority",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              task.priority,
                              style: TextStyle(
                                color: priorityColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 42, color: Colors.white12),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Relative score",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "${task.normalizedScore.round()}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFF9B87FF),
                        size: 17,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          "This is a relative priority score, not a percentage. "
                          "It shows how this task compares with your other "
                          "pending tasks.",
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  "Key ranking factors",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),

                const SizedBox(height: 10),

                if (task.reasonTags.isEmpty)
                  const Text(
                    "No explanation factors are available.",
                    style: TextStyle(color: Colors.white54),
                  )
                else
                  ...task.reasonTags.map((tag) {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: priorityColor,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              getDisplayReason(task, tag),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompletedTaskCard(BuildContext context, TaskModel task) {
    final priorityColor = getPriorityColor(task.priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF162033),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.greenAccent,
                  size: 22,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${getCategoryName(task.category)} · Completed",
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              IconButton(
                tooltip: "Delete task",
                onPressed: () => _confirmDeleteTask(task),
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Colors.white38,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  task.priority,
                  style: TextStyle(
                    color: priorityColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Text(
                "Score ${task.normalizedScore.round()}",
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const Spacer(),

              TextButton(
                onPressed: () {
                  _showPriorityExplanation(context, task);
                },
                child: const Text(
                  "View ranking",
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildTaskCard(BuildContext context, TaskModel task) {
    if (task.status == "completed") {
      return _buildCompletedTaskCard(context, task);
    }

    final priorityColor = getPriorityColor(task.priority);
    final isNotificationTarget = task.id == _highlightedTaskId;
    final isBusy = _busyTaskIds.contains(task.id);
    final deadlineColor = getDeadlineColor(task);
    final displayStatus = getDisplayStatus(task);
    final missedSchedule = hasMissedSchedule(task);
    final validSchedule = hasValidScheduledTime(task);

    final isOverdue = isTaskOverdue(task);

    final visibleReasons = task.reasonTags.take(2).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF172238),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isNotificationTarget
              ? Colors.cyanAccent
              : isOverdue
              ? Colors.redAccent.withValues(alpha: 0.70)
              : priorityColor.withValues(alpha: 0.20),
          width: isNotificationTarget
              ? 2.2
              : isOverdue
              ? 1.4
              : 1,
        ),
        boxShadow: [
          if (isNotificationTarget)
            BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.28),
              blurRadius: 24,
              spreadRadius: 2,
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Task title and actions ────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: "Task actions",
                visualDensity: VisualDensity.compact,
                onPressed: isBusy
                    ? null
                    : () {
                        _showTaskActions(context, task);
                      },
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: Colors.white54,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Category, status and priority ─────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  getCategoryName(task.category),
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: getDisplayStatusColor(
                    displayStatus,
                  ).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  displayStatus,
                  style: TextStyle(
                    color: getDisplayStatusColor(displayStatus),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: priorityColor.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  "${task.priority} priority",
                  style: TextStyle(
                    color: priorityColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // ── Deadline spotlight ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: deadlineColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: deadlineColor.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: deadlineColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isOverdue
                        ? Icons.warning_amber_rounded
                        : Icons.flag_outlined,
                    color: deadlineColor,
                    size: 21,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDeadline(task.deadline),
                        style: TextStyle(
                          color: deadlineColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        getDeadlineSummary(task),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (task.isSnoozed && task.snoozedUntil.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.snooze_rounded,
                    color: Colors.cyanAccent,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Returns ${DateFormat('MMM d • h:mm a').format(DateTime.parse(task.snoozedUntil).toLocal())}",
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Compact task metadata ──────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCompactMetadata(
                icon: missedSchedule
                    ? Icons.event_busy_rounded
                    : validSchedule
                    ? Icons.event_available_rounded
                    : Icons.play_circle_outline_rounded,

                label: missedSchedule
                    ? "MISSED SCHEDULE"
                    : validSchedule
                    ? "SCHEDULED"
                    : "AVAILABLE",

                value: missedSchedule
                    ? formatMissedScheduledTime(task)
                    : validSchedule
                    ? formatScheduledTime(task)
                    : formatAvailableFrom(task.availableFrom),

                color: missedSchedule
                    ? Colors.orangeAccent
                    : validSchedule
                    ? Colors.deepPurpleAccent
                    : Colors.greenAccent,
              ),

              const SizedBox(width: 10),

              _buildCompactMetadata(
                icon: Icons.hourglass_bottom_rounded,
                label: "DURATION",
                value: formatDuration(task.estimatedDurationMinutes),
                color: Colors.cyanAccent,
              ),
            ],
          ),

          const SizedBox(height: 15),

          // ── Stage 2 ranking ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFF9B87FF).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                _buildStage2Badge(),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      task.normalizedScore.round().toString(),
                      style: TextStyle(
                        color: priorityColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      getPriorityRangeLabel(task),
                      style: TextStyle(
                        color: priorityColor.withValues(alpha: 0.75),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (visibleReasons.isNotEmpty) ...[
            const SizedBox(height: 13),

            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: visibleReasons.map((reason) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    getDisplayReason(task, reason),
                    style: TextStyle(
                      color: priorityColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 5),

            TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                _showPriorityExplanation(context, task);
              },
              icon: const Icon(Icons.help_outline_rounded, size: 15),
              label: Text(
                task.reasonTags.length > 2
                    ? "Why this priority? · "
                          "${task.reasonTags.length - 2} more factors"
                    : "Why this priority?",
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // ── Primary and secondary actions ─────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: task.isSnoozed
                        ? Colors.cyanAccent
                        : Colors.greenAccent,
                    disabledBackgroundColor:
                        (task.isSnoozed
                                ? Colors.cyanAccent
                                : Colors.greenAccent)
                            .withValues(alpha: 0.55),
                    foregroundColor: const Color(0xFF081028),
                    disabledForegroundColor: const Color(0xFF081028),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: isBusy
                      ? null
                      : () {
                          _runTaskAction(
                            taskId: task.id,
                            errorMessage: task.isSnoozed
                                ? "Could not resume the task. Please try again."
                                : "Could not complete the task. Please try again.",
                            action: () {
                              if (task.isSnoozed) {
                                return firestoreService.unsnoozeTask(task.id);
                              }

                              return firestoreService.completeTask(task.id);
                            },
                          );
                        },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: isBusy
                        ? const Row(
                            key: ValueKey<String>('working'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Color(0xFF081028),
                                ),
                              ),
                              SizedBox(width: 10),
                              Text(
                                "Updating...",
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          )
                        : Row(
                            key: ValueKey<String>(
                              task.isSnoozed ? 'resume' : 'complete',
                            ),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                task.isSnoozed
                                    ? Icons.play_arrow_rounded
                                    : Icons.check_rounded,
                                size: 19,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                task.isSnoozed
                                    ? "Resume task"
                                    : "Complete task",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: isBusy
                      ? null
                      : () {
                          _showTaskActions(context, task);
                        },
                  icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  label: const Text(
                    "More",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
