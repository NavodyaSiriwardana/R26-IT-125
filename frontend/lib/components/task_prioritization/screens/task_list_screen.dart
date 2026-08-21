import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../services/firestore_service.dart';
import 'smart_task_form_screen.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Smart Task List"),
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
        stream: firestoreService.getTasks(),
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
          final activeTasks = tasks.where((task) {
            if (task.status == "completed") return false;
            if (task.isSnoozed) {
              if (task.snoozedUntil.isEmpty) return true;
              final snoozedUntil = DateTime.tryParse(task.snoozedUntil);
              if (snoozedUntil == null) return true;
              if (snoozedUntil.isBefore(DateTime.now())) {
                firestoreService.unsnoozeTask(task.id);
                return true;
              }
              return false;
            }
            return true;
          }).toList();

          final completedTasks = tasks
              .where((t) => t.status == "completed")
              .toList();

          final snoozedTasks = tasks.where((task) {
            if (!task.isSnoozed || task.snoozedUntil.isEmpty) return false;
            final snoozedUntil = DateTime.tryParse(task.snoozedUntil);
            if (snoozedUntil == null) return false;
            return snoozedUntil.isAfter(DateTime.now());
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
                            .map((task) => buildTaskCard(context, task))
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
                            .map((task) => buildTaskCard(context, task))
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
                      .map((task) => buildTaskCard(context, task))
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

  bool hasValidScheduledTime(TaskModel task) {
    if (task.scheduleStatus != "scheduled") return false;

    if (task.scheduledStart.isEmpty ||
        task.scheduledEnd.isEmpty ||
        task.scheduleDate.isEmpty) {
      return false;
    }

    final start = DateTime.tryParse(task.scheduledStart)?.toLocal();

    final end = DateTime.tryParse(task.scheduledEnd)?.toLocal();

    final scheduleDate = DateTime.tryParse(task.scheduleDate);

    if (start == null || end == null || scheduleDate == null) {
      return false;
    }

    return true;
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

    if (hasValidScheduledTime(task)) {
      return "Scheduled";
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

      case "Active":
        return Colors.orangeAccent;

      default:
        return Colors.white70;
    }
  }

  Widget buildTaskCard(BuildContext context, TaskModel task) {
    final displayStatus = getDisplayStatus(task);

    final isOverdue =
        task.status != "completed" &&
        task.deadline.isNotEmpty &&
        DateTime.tryParse(task.deadline)?.toLocal().isBefore(DateTime.now()) ==
            true;

    final visibleReasonTags = task.reasonTags.take(3).toList();

    final hiddenReasonCount = task.reasonTags.length > 3
        ? task.reasonTags.length - 3
        : 0;

    return Card(
      elevation: 0,
      color: task.status == "completed"
          ? const Color(0xFF162033)
          : const Color(0xFF172238),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isOverdue ? Colors.redAccent : Colors.white.withOpacity(0.07),
          width: isOverdue ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      margin: const EdgeInsets.only(bottom: 18),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title row ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (task.status == "completed")
                        const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                          ),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                decoration: task.status == "completed"
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Category badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.cyanAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                getCategoryName(task.category), // ← now String
                                style: const TextStyle(
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Row(
                  children: [
                    if (isOverdue)
                      Container(
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          "OVERDUE",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                    // Priority badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: getPriorityColor(task.priority).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        task.priority,
                        style: TextStyle(
                          color: getPriorityColor(task.priority),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Scheduling and timing information ──────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF162033),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasValidScheduledTime(task)
                      ? Colors.deepPurpleAccent.withOpacity(0.45)
                      : Colors.white10,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasValidScheduledTime(task)) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.event_available_rounded,
                          color: Colors.deepPurpleAccent,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Scheduled Plan",
                          style: TextStyle(
                            color: Colors.deepPurpleAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    buildInfoRow(
                      icon: Icons.schedule_rounded,
                      label: "Scheduled",
                      value: formatScheduledTime(task),
                      iconColor: Colors.deepPurpleAccent,
                      valueColor: Colors.white,
                    ),
                  ] else
                    buildInfoRow(
                      icon: Icons.play_circle_outline_rounded,
                      label: "Available from",
                      value: formatAvailableFrom(task.availableFrom),
                      iconColor: Colors.greenAccent,
                    ),

                  buildInfoRow(
                    icon: Icons.hourglass_bottom_rounded,
                    label: "Duration",
                    value: formatDuration(task.estimatedDurationMinutes),
                    iconColor: Colors.cyanAccent,
                  ),

                  buildInfoRow(
                    icon: Icons.flag_outlined,
                    label: "Deadline",
                    value: formatDeadline(task.deadline),
                    iconColor: getDeadlineColor(task),
                    valueColor: getDeadlineColor(task),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Reason tags ────────────────────────────────────────────────
            if (visibleReasonTags.isNotEmpty) ...[
              const Text(
                "Why this priority?",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 9),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...visibleReasonTags.map((tag) {
                    return Chip(
                      label: Text(
                        tag.toString(),
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.deepPurple.withOpacity(0.85),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  }),

                  if (hiddenReasonCount > 0)
                    ActionChip(
                      label: Text(
                        "+$hiddenReasonCount more",
                        style: const TextStyle(
                          color: Colors.deepPurpleAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: Colors.deepPurpleAccent.withOpacity(
                        0.12,
                      ),
                      side: BorderSide(
                        color: Colors.deepPurpleAccent.withOpacity(0.4),
                      ),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: const Color(0xFF1E293B),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                          ),
                          builder: (_) {
                            return SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Why “${task.title}” has "
                                      "${task.priority} priority",
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: task.reasonTags.map((tag) {
                                        return Chip(
                                          label: Text(tag.toString()),
                                          backgroundColor: Colors.deepPurple,
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ],

            const SizedBox(height: 14),

            // ── Score + status ─────────────────────────────────────────────
            Text(
              "Priority Score: ${task.normalizedScore.toStringAsFixed(1)}",
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              "Status: $displayStatus",
              style: TextStyle(
                color: getDisplayStatusColor(displayStatus),
                fontWeight: FontWeight.bold,
              ),
            ),

            if (task.isSnoozed && task.snoozedUntil.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Snoozed until: ${DateFormat('MMM d • h:mm a').format(DateTime.parse(task.snoozedUntil).toLocal())}",
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            // ── Action buttons ─────────────────────────────────────────────
            if (task.status != "completed") ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton(
                    onPressed: () async =>
                        await firestoreService.completeTask(task.id),
                    child: const Text("Complete"),
                  ),

                  ElevatedButton(
                    onPressed: () async {
                      showModalBottomSheet(
                        context: context,
                        builder: (context) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: const Text("10 Minutes"),
                              onTap: () async {
                                await firestoreService.snoozeTask(
                                  task.id,
                                  task.snoozeCount,
                                  DateTime.now().add(
                                    const Duration(minutes: 10),
                                  ),
                                );
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              title: const Text("20 Minutes"),
                              onTap: () async {
                                await firestoreService.snoozeTask(
                                  task.id,
                                  task.snoozeCount,
                                  DateTime.now().add(
                                    const Duration(minutes: 20),
                                  ),
                                );
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              title: const Text("1 Hour"),
                              onTap: () async {
                                await firestoreService.snoozeTask(
                                  task.id,
                                  task.snoozeCount,
                                  DateTime.now().add(const Duration(hours: 1)),
                                );
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text("Snooze"),
                  ),

                  ElevatedButton(
                    onPressed: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (pickedDate == null) return;
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (pickedTime == null) return;
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
                    },
                    child: const Text("Postpone"),
                  ),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("Delete Task"),
                          content: const Text(
                            "Are you sure you want to delete this task?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Delete"),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await firestoreService.deleteTask(task.id);
                      }
                    },
                    child: const Text("Delete"),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
