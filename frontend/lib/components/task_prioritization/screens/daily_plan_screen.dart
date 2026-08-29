import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/firestore_service.dart';
import '../services/task_api_service.dart';
import '../services/productivity_analytics_service.dart';
import '../services/notification_service.dart';

class DailyPlanScreen extends StatefulWidget {
  const DailyPlanScreen({super.key});

  @override
  State<DailyPlanScreen> createState() => _DailyPlanScreenState();
}

class _DailyPlanScreenState extends State<DailyPlanScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  TimeOfDay availableStart = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay availableEnd = const TimeOfDay(hour: 18, minute: 0);

  DateTime selectedPlanDate = DateTime.now();

  String planningMode = "include_upcoming";

  String breakStrategy = "adaptive";

  bool isGenerating = false;
  String _generationStatus = "Generate My Plan";
  bool isApplyingPlan = false;
  bool planConfirmed = false;

  Map<String, dynamic>? scheduleResult;

  SchedulerPreferenceProfile? preferenceProfile;
  bool isLoadingPreferences = true;
  bool recommendationsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSchedulerPreferences();
  }

  Future<void> _loadSchedulerPreferences() async {
    try {
      final profile = await ProductivityAnalyticsService()
          .getSchedulerPreferenceProfile();

      if (!mounted) return;

      setState(() {
        preferenceProfile = profile;
        isLoadingPreferences = false;
      });
    } catch (e) {
      debugPrint('Failed to load scheduler preferences: $e');

      if (!mounted) return;

      setState(() {
        isLoadingPreferences = false;
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  int _minutesSinceMidnight(TimeOfDay value) {
    return value.hour * 60 + value.minute;
  }

  Future<void> _generatePlan() async {
    if (isGenerating || isApplyingPlan) {
      return;
    }

    FocusScope.of(context).unfocus();

    final startMinutes = _minutesSinceMidnight(availableStart);

    final endMinutes = _minutesSinceMidnight(availableEnd);

    if (endMinutes <= startMinutes) {
      _showMessage("The planning end time must be after the start time.");

      return;
    }

    setState(() {
      isGenerating = true;
      _generationStatus = "Refreshing priorities...";
      scheduleResult = null;
      planConfirmed = false;
    });

    try {
      // Stage 1: Refresh the time-sensitive Stage 2 ranking.
      await _firestoreService.rerankAllTasks();

      if (!mounted) {
        return;
      }

      setState(() {
        _generationStatus = "Loading eligible tasks...";
      });

      // Stage 2: Retrieve tasks that can participate in scheduling.
      final tasks = await _firestoreService.getSchedulableTasksRaw();

      if (!mounted) {
        return;
      }

      if (tasks.isEmpty) {
        _showMessage("There are no pending tasks to schedule.");

        return;
      }

      setState(() {
        _generationStatus = "Building your schedule...";
      });

      final selectedDateText = DateFormat(
        'yyyy-MM-dd',
      ).format(selectedPlanDate);

      // Stage 3: Generate the constraint-based schedule.
      final result = await TaskApiService.generateSchedule(
        scheduleDate: selectedDateText,
        availableStart: _formatTimeOfDay(availableStart),
        availableEnd: _formatTimeOfDay(availableEnd),
        breakStrategy: breakStrategy,
        planningMode: planningMode,
        tasks: tasks,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _generationStatus = "Preparing preview...";
      });

      // A short frame boundary lets the final progress message
      // render before the larger result UI is inserted.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      if (!mounted) {
        return;
      }

      setState(() {
        scheduleResult = result;
        planConfirmed = false;
      });

      _showMessage("Plan options generated. Review and select a plan.");
    } catch (error, stackTrace) {
      debugPrint("Daily-plan generation failed: $error");

      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage("The plan could not be generated. Please try again.");
      }
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
          _generationStatus = "Generate My Plan";
        });
      }
    }
  }

  Future<void> _applyGeneratedPlan({
    required Map<String, dynamic> plan,
    required String planName,
  }) async {
    if (isApplyingPlan) return;

    // Validate that the preview has not become outdated.
    final scheduledTasks = plan["scheduled_tasks"] as List<dynamic>? ?? [];

    if (scheduledTasks.isNotEmpty) {
      final scheduledStarts = scheduledTasks
          .map((item) {
            final task = Map<String, dynamic>.from(item as Map);

            final value = task["scheduled_start"]?.toString();

            if (value == null || value.isEmpty) {
              return null;
            }

            return DateTime.tryParse(value)?.toLocal();
          })
          .whereType<DateTime>()
          .toList();

      if (scheduledStarts.isEmpty) {
        _showMessage(
          "The generated plan contains invalid scheduling information. "
          "Please generate it again.",
        );

        return;
      }

      scheduledStarts.sort();

      final firstScheduledStart = scheduledStarts.first;

      final now = DateTime.now();

      if (!firstScheduledStart.isAfter(now)) {
        setState(() {
          scheduleResult = null;
          planConfirmed = false;
        });

        _showMessage(
          "This plan has become outdated. "
          "Generate a new plan using the current time.",
        );

        return;
      }
    }

    setState(() {
      isApplyingPlan = true;
    });

    try {
      // Prevent nested alternative data from being sent to
      // the Firestore schedule-saving method.
      final selectedPlan = Map<String, dynamic>.from(plan);

      selectedPlan.remove("deadline_focused_alternative");

      await _firestoreService.validateScheduleCandidates(selectedPlan);

      await _firestoreService.saveGeneratedSchedule(selectedPlan);

      String? notificationWarning;

      try {
        final notificationCount = await NotificationService.instance
            .schedulePlanNotifications(selectedPlan);

        debugPrint('$notificationCount plan reminders scheduled.');

        await NotificationService.instance.printPendingNotifications();
      } catch (error, stackTrace) {
        notificationWarning =
            'The plan was saved, but its reminders could not be scheduled.';

        debugPrint('Plan notification scheduling failed: $error');

        debugPrintStack(stackTrace: stackTrace);
      }

      if (!mounted) return;

      setState(() {
        scheduleResult = selectedPlan;
        planConfirmed = true;
      });

      final message =
          notificationWarning ?? "$planName saved as your daily plan.";

      _showMessage(message);
    } catch (error) {
      if (!mounted) return;

      _showMessage("Failed to save the selected plan: $error");
    } finally {
      if (mounted) {
        setState(() {
          isApplyingPlan = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickStartTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: availableStart,
    );

    if (value != null) {
      setState(() => availableStart = value);
    }
  }

  Future<void> _pickEndTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: availableEnd,
    );

    if (value != null) {
      setState(() => availableEnd = value);
    }
  }

  Future<void> _pickPlanDate() async {
    final today = DateUtils.dateOnly(DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: selectedPlanDate.isBefore(today) ? today : selectedPlanDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );

    if (picked == null) return;

    setState(() {
      selectedPlanDate = picked;
      scheduleResult = null;
    });
  }

  List<Widget> _buildScheduleTimeline(List<dynamic> scheduledTasks) {
    final widgets = <Widget>[];

    if (scheduledTasks.isEmpty) {
      return [
        const Text(
          "No tasks could be scheduled.",
          style: TextStyle(color: Colors.white70),
        ),
      ];
    }

    final tasks = scheduledTasks.map((item) {
      return Map<String, dynamic>.from(item as Map);
    }).toList();

    tasks.sort((a, b) {
      final aStart = DateTime.parse(a["scheduled_start"]).toLocal();

      final bStart = DateTime.parse(b["scheduled_start"]).toLocal();

      return aStart.compareTo(bStart);
    });

    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];

      final start = DateTime.parse(task["scheduled_start"]).toLocal();

      final end = DateTime.parse(task["scheduled_end"]).toLocal();

      widgets.add(_buildTaskTimelineCard(task: task, start: start, end: end));

      if (i < tasks.length - 1) {
        final nextTask = tasks[i + 1];

        final nextStart = DateTime.parse(nextTask["scheduled_start"]).toLocal();

        final gapMinutes = nextStart.difference(end).inMinutes;

        if (gapMinutes > 0) {
          final actualBreakMinutes =
              (task["break_after_minutes"] as num?)?.toInt() ?? 0;

          if (actualBreakMinutes > 0) {
            final breakEnd = end.add(Duration(minutes: actualBreakMinutes));

            widgets.add(
              _buildBreakTimelineCard(
                start: end,
                end: breakEnd,
                minutes: actualBreakMinutes,
              ),
            );
          }

          final freeTimeMinutes = gapMinutes - actualBreakMinutes;

          if (freeTimeMinutes > 0) {
            final freeTimeStart = end.add(
              Duration(minutes: actualBreakMinutes),
            );

            widgets.add(
              _buildFreeTimeTimelineCard(
                start: freeTimeStart,
                end: nextStart,
                minutes: freeTimeMinutes,
              ),
            );
          }
        }
      }
    }

    return widgets;
  }

  String _formatDurationValue(dynamic value) {
    final minutes = (value as num?)?.toInt() ?? 0;

    if (minutes < 60) {
      return "${minutes}m";
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) {
      return "${hours}h";
    }

    return "${hours}h ${remainingMinutes}m";
  }

  Color _workloadStatusColor(String status) {
    switch (status.toLowerCase()) {
      case "overloaded":
        return Colors.redAccent;
      case "high":
      case "busy":
        return Colors.orangeAccent;
      case "balanced":
        return Colors.greenAccent;
      case "light":
        return Colors.cyanAccent;
      default:
        return Colors.white70;
    }
  }

  Widget _buildSummaryMetric({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      width: 135,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanSummaryCard(Map<String, dynamic> result) {
    final status = result["workload_status"]?.toString() ?? "Unknown";

    final statusColor = _workloadStatusColor(status);

    final scheduledCount =
        (result["scheduled_task_count"] as num?)?.toInt() ?? 0;

    final unscheduledCount =
        (result["unscheduled_task_count"] as num?)?.toInt() ?? 0;

    final notConsideredCount =
        (result["not_considered_task_count"] as num?)?.toInt() ??
        (result["not_considered_tasks"] as List<dynamic>?)?.length ??
        0;

    final totalCandidateTasks =
        scheduledCount + unscheduledCount + notConsideredCount;

    final utilization =
        (result["utilization_percentage"] as num?)?.toDouble() ?? 0.0;

    final progressValue = (utilization / 100).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Today's Plan",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.35)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              "$scheduledCount of $totalCandidateTasks candidate tasks scheduled",
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),

            const SizedBox(height: 18),

            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildSummaryMetric(
                  icon: Icons.schedule_rounded,
                  value: _formatDurationValue(
                    result["total_available_minutes"],
                  ),
                  label: "Available",
                  color: Colors.blueAccent,
                ),
                _buildSummaryMetric(
                  icon: Icons.task_alt_rounded,
                  value: _formatDurationValue(
                    result["total_scheduled_minutes"],
                  ),
                  label: "Task time",
                  color: Colors.deepPurpleAccent,
                ),
                _buildSummaryMetric(
                  icon: Icons.coffee_rounded,
                  value: _formatDurationValue(result["total_break_minutes"]),
                  label: "Breaks",
                  color: Colors.tealAccent,
                ),
                _buildSummaryMetric(
                  icon: Icons.hourglass_empty_rounded,
                  value: _formatDurationValue(result["remaining_free_minutes"]),
                  label: "Free time",
                  color: Colors.greenAccent,
                ),
              ],
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                const Text(
                  "Schedule utilization",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const Spacer(),
                Text(
                  "${utilization.toStringAsFixed(1)}%",
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: 7,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),

            if (unscheduledCount > 0) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.orangeAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "$unscheduledCount "
                      "${unscheduledCount == 1 ? "task could" : "tasks could"} "
                      "not fit within the selected planning period.",
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSmartRecommendationCard() {
    if (isLoadingPreferences) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.amberAccent,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Analyzing your activity",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 3),
                    Text(
                      "Preparing personalized scheduling insights...",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final profile = preferenceProfile;

    if (profile == null) {
      return const SizedBox.shrink();
    }

    final recommendations = profile.recommendations;

    final recommendationCount = recommendations.length;

    final hasRecommendations = recommendations.isNotEmpty;

    final subtitle = profile.hasEnoughHistory
        ? "$recommendationCount "
              "${recommendationCount == 1 ? "personalized insight" : "personalized insights"}"
        : "${profile.activeDays} of 3 active days recorded";

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                recommendationsExpanded = !recommendationsExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.psychology_alt_rounded,
                      color: Colors.amberAccent,
                      size: 23,
                    ),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Smart Recommendations",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  AnimatedRotation(
                    turns: recommendationsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Colors.white12, height: 1),

                  const SizedBox(height: 16),

                  if (!profile.hasEnoughHistory) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Colors.cyanAccent,
                          size: 19,
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            hasRecommendations
                                ? recommendations.first
                                : "More activity history is needed before personalized scheduling recommendations can be generated.",
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Text(
                          "${profile.activeDays} active "
                          "${profile.activeDays == 1 ? "day" : "days"}",
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          "3 days needed",
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: (profile.activeDays / 3).clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.cyanAccent,
                        ),
                      ),
                    ),
                  ] else if (!hasRecommendations) ...[
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: Colors.greenAccent,
                          size: 19,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "No scheduling recommendations are available at the moment.",
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    ...recommendations.asMap().entries.map((entry) {
                      final index = entry.key;
                      final recommendation = entry.value;

                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == recommendationCount - 1 ? 0 : 14,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.amberAccent.withOpacity(0.10),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                "${index + 1}",
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),

                            const SizedBox(width: 11),

                            Expanded(
                              child: Text(
                                recommendation,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "Early insights based on "
                        "${profile.activeDays} active "
                        "${profile.activeDays == 1 ? "day" : "days"}",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: recommendationsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildFreeTimeTimelineCard({
    required DateTime start,
    required DateTime end,
    required int minutes,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 24, right: 24, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_empty_rounded,
            color: Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Free time • ${_formatMinutes(minutes)}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${DateFormat('h:mm a').format(start)}"
                  " – "
                  "${DateFormat('h:mm a').format(end)}",
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) {
      return "$minutes minutes";
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) {
      return hours == 1 ? "1 hour" : "$hours hours";
    }

    return "${hours}h ${remainingMinutes}m";
  }

  Widget _buildTaskTimelineCard({
    required Map<String, dynamic> task,
    required DateTime start,
    required DateTime end,
  }) {
    final partNumber = (task["part_number"] as num?)?.toInt() ?? 1;

    final partCount = (task["part_count"] as num?)?.toInt() ?? 1;

    final originalTitle = task["title"]?.toString() ?? "Untitled task";

    final priority = task["priority"]?.toString() ?? "Medium";

    final priorityColor = _priorityColor(priority);

    final durationMinutes = end.difference(start).inMinutes;

    final displayTitle = partCount > 1
        ? "$originalTitle — Part $partNumber of $partCount"
        : originalTitle;

    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: priorityColor),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.task_alt_rounded,
                        color: priorityColor,
                        size: 23,
                      ),
                    ),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  displayTitle,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 10),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: priorityColor.withOpacity(0.11),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: priorityColor.withOpacity(0.30),
                                  ),
                                ),
                                child: Text(
                                  priority.toUpperCase(),
                                  style: TextStyle(
                                    color: priorityColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 9),

                          Wrap(
                            spacing: 12,
                            runSpacing: 7,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 16,
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    "${DateFormat('h:mm a').format(start)}"
                                    " – "
                                    "${DateFormat('h:mm a').format(end)}",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),

                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.timelapse_rounded,
                                    size: 16,
                                    color: Colors.white38,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _formatMinutes(durationMinutes),
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          if (partCount > 1) ...[
                            const SizedBox(height: 10),

                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: partNumber / partCount,
                                minHeight: 5,
                                backgroundColor: Colors.white12,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  priorityColor,
                                ),
                              ),
                            ),

                            const SizedBox(height: 5),

                            Text(
                              "Part $partNumber of $partCount",
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _priorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case "critical":
        return Colors.deepPurpleAccent;

      case "high":
        return Colors.redAccent;

      case "medium":
        return Colors.orangeAccent;

      case "low":
        return Colors.greenAccent;

      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildBreakTimelineCard({
    required DateTime start,
    required DateTime end,
    required int minutes,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 24, right: 24, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.tealAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.tealAccent.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.coffee_rounded, color: Colors.tealAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Break • $minutes minutes",
                  style: const TextStyle(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "${DateFormat('h:mm a').format(start)}"
                  " – "
                  "${DateFormat('h:mm a').format(end)}",
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnscheduledTaskCard(Map<String, dynamic> task) {
    final title = task["title"]?.toString() ?? "Untitled task";

    final reason =
        task["reason"]?.toString() ??
        "This task could not fit within the selected planning period.";

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: Colors.orangeAccent),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orangeAccent,
                        size: 23,
                      ),
                    ),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ),

                              const SizedBox(width: 8),

                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  "NEEDS ATTENTION",
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 9),

                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Colors.white38,
                              ),

                              const SizedBox(width: 7),

                              Expanded(
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanSelectionTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
    Color iconColor = Colors.deepPurpleAccent,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.035),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white38,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendedPlanChoiceCard() {
    final result = scheduleResult;

    if (result == null || planConfirmed) {
      return const SizedBox.shrink();
    }

    final scheduledCount =
        (result["scheduled_task_count"] as num?)?.toInt() ?? 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14, bottom: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurpleAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.recommend_rounded,
                color: Colors.deepPurpleAccent,
                size: 21,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  "Recommended Plan",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                "PREVIEW",
                style: TextStyle(
                  color: Colors.deepPurpleAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            "$scheduledCount "
            "${scheduledCount == 1 ? "task" : "tasks"} "
            "scheduled using the model ranking and planning constraints.",
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: isApplyingPlan || isGenerating
                  ? null
                  : () {
                      _applyGeneratedPlan(
                        plan: result,
                        planName: "Recommended plan",
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.deepPurpleAccent.withOpacity(
                  0.30,
                ),
                disabledForegroundColor: Colors.white60,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: isApplyingPlan
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                isApplyingPlan ? "Saving your plan..." : "Use Recommended Plan",
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlineAlternativeCard(Map<String, dynamic> alternative) {
    final protectedTitle =
        alternative["protected_task_title"]?.toString() ??
        "Deadline-sensitive task";

    final tradeoffMessage =
        alternative["tradeoff_message"]?.toString() ??
        "This option protects an excluded deadline-sensitive task.";

    final alternativeScheduled =
        alternative["scheduled_tasks"] as List<dynamic>? ?? [];

    final alternativeUnscheduled =
        alternative["unscheduled_tasks"] as List<dynamic>? ?? [];

    final scheduledCount =
        (alternative["scheduled_task_count"] as num?)?.toInt() ??
        alternativeScheduled.length;

    return Card(
      margin: const EdgeInsets.only(top: 18),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.shield_outlined,
            color: Colors.orangeAccent,
            size: 22,
          ),
        ),
        title: const Text(
          "Deadline-Focused Alternative",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Protects "$protectedTitle"',
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
          ),
        ),
        children: [
          const Divider(color: Colors.white12, height: 1),

          const SizedBox(height: 14),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.07),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.swap_horiz_rounded,
                  color: Colors.orangeAccent,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    tradeoffMessage,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Text(
                  "$scheduledCount "
                  "${scheduledCount == 1 ? "task" : "tasks"} "
                  "scheduled",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Text(
                "ALTERNATIVE",
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          ..._buildScheduleTimeline(alternativeScheduled),

          if (alternativeUnscheduled.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              "${alternativeUnscheduled.length} "
              "${alternativeUnscheduled.length == 1 ? "task does" : "tasks do"} "
              "not fit in this alternative.",
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: isApplyingPlan
                  ? null
                  : () {
                      _applyGeneratedPlan(
                        plan: alternative,
                        planName: "Deadline-focused alternative",
                      );
                    },
              icon: const Icon(Icons.shield_rounded),
              label: const Text(
                "Use Deadline-Focused Plan",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduled =
        scheduleResult?["scheduled_tasks"] as List<dynamic>? ?? [];

    final unscheduled =
        scheduleResult?["unscheduled_tasks"] as List<dynamic>? ?? [];

    final notConsidered =
        scheduleResult?["not_considered_tasks"] as List<dynamic>? ?? [];

    final alternativeRaw = scheduleResult?["deadline_focused_alternative"];

    final deadlineAlternative = alternativeRaw is Map
        ? Map<String, dynamic>.from(alternativeRaw)
        : null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Intelligent Daily Plan"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Plan Settings",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 4),

                  const Text(
                    "Choose when and how your day should be planned.",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),

                  const SizedBox(height: 18),

                  _buildPlanSelectionTile(
                    icon: Icons.calendar_today_rounded,
                    label: "Plan date",
                    value: DateFormat(
                      'EEEE, MMM d, yyyy',
                    ).format(selectedPlanDate),
                    onTap: isGenerating ? null : _pickPlanDate,
                    iconColor: Colors.deepPurpleAccent,
                  ),

                  const SizedBox(height: 10),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final useVerticalLayout = constraints.maxWidth < 340;

                      final startTile = _buildPlanSelectionTile(
                        icon: Icons.wb_sunny_outlined,
                        label: "Start time",
                        value: availableStart.format(context),
                        onTap: isGenerating ? null : _pickStartTime,
                        iconColor: Colors.orangeAccent,
                      );

                      final endTile = _buildPlanSelectionTile(
                        icon: Icons.nights_stay_outlined,
                        label: "End time",
                        value: availableEnd.format(context),
                        onTap: isGenerating ? null : _pickEndTime,
                        iconColor: Colors.indigoAccent,
                      );

                      if (useVerticalLayout) {
                        return Column(
                          children: [
                            startTile,
                            const SizedBox(height: 10),
                            endTile,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(child: startTile),
                          const SizedBox(width: 10),
                          Expanded(child: endTile),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    initialValue: breakStrategy,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white54,
                    ),
                    decoration: InputDecoration(
                      labelText: "Break strategy",
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.coffee_rounded,
                          color: Colors.tealAccent,
                          size: 21,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.035),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Colors.deepPurpleAccent,
                          width: 1.3,
                        ),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: "adaptive",
                        child: Text("Adaptive breaks"),
                      ),
                      DropdownMenuItem(
                        value: "none",
                        child: Text("No automatic breaks"),
                      ),
                      DropdownMenuItem(
                        value: "fixed_5",
                        child: Text("Fixed 5-minute breaks"),
                      ),
                      DropdownMenuItem(
                        value: "fixed_10",
                        child: Text("Fixed 10-minute breaks"),
                      ),
                      DropdownMenuItem(
                        value: "fixed_15",
                        child: Text("Fixed 15-minute breaks"),
                      ),
                    ],
                    onChanged: isGenerating
                        ? null
                        : (value) {
                            if (value == null) return;

                            setState(() {
                              breakStrategy = value;
                              scheduleResult = null;
                            });
                          },
                  ),

                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    initialValue: planningMode,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white54,
                    ),
                    decoration: InputDecoration(
                      labelText: "Planning mode",
                      labelStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.event_note_rounded,
                          color: Colors.blueAccent,
                          size: 21,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.035),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Colors.deepPurpleAccent,
                          width: 1.3,
                        ),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: "due_today_only",
                        child: Text("Due today only"),
                      ),
                      DropdownMenuItem(
                        value: "include_upcoming",
                        child: Text("Include upcoming tasks"),
                      ),
                    ],
                    onChanged: isGenerating
                        ? null
                        : (value) {
                            if (value == null) return;

                            setState(() {
                              planningMode = value;
                              scheduleResult = null;
                            });
                          },
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isGenerating || isApplyingPlan
                          ? null
                          : _generatePlan,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.deepPurpleAccent
                            .withOpacity(0.30),
                        disabledForegroundColor: Colors.white60,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: Row(
                          key: ValueKey<String>(_generationStatus),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isGenerating) ...[
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ] else ...[
                              const Icon(Icons.auto_awesome_rounded, size: 20),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                _generationStatus,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (scheduleResult != null) ...[
            const SizedBox(height: 20),

            _buildPlanSummaryCard(scheduleResult!),

            _buildRecommendedPlanChoiceCard(),

            if (!planConfirmed && deadlineAlternative != null)
              _buildDeadlineAlternativeCard(deadlineAlternative),

            if (planConfirmed)
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.greenAccent,
                      size: 20,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        "This plan has been saved as your active daily plan.",
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (scheduleResult?["effective_available_start"] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "Plan starts at "
                  "${DateFormat('h:mm a').format(DateTime.parse(scheduleResult!["effective_available_start"]).toLocal())}",
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              "Scheduled Tasks",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._buildScheduleTimeline(scheduled),
            if (unscheduled.isNotEmpty) ...[
              const SizedBox(height: 24),

              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Could Not Schedule",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.orangeAccent.withOpacity(0.30),
                      ),
                    ),
                    child: Text(
                      "${unscheduled.length}",
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 5),

              const Text(
                "These tasks could not fit within the selected time and scheduling constraints.",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 12),

              ...unscheduled.map((item) {
                final task = Map<String, dynamic>.from(item as Map);

                return _buildUnscheduledTaskCard(task);
              }),
            ],

            if (notConsidered.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                "Not Considered for This Plan",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...notConsidered.map((item) {
                final task = Map<String, dynamic>.from(item as Map);

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_busy_outlined),
                    title: Text(task["title"] ?? "Untitled task"),
                    subtitle: Text(
                      task["reason"] ??
                          "This task is outside the selected plan.",
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 20),

            _buildSmartRecommendationCard(),
          ] else ...[
            _buildSmartRecommendationCard(),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
