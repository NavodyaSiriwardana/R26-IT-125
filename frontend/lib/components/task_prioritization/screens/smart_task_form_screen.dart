import 'package:flutter/material.dart';
import '../services/task_api_service.dart';
import '../services/firestore_service.dart';

class SmartTaskFormScreen extends StatefulWidget {
  const SmartTaskFormScreen({super.key});

  @override
  State<SmartTaskFormScreen> createState() => _SmartTaskFormScreenState();
}

class _SmartTaskFormScreenState extends State<SmartTaskFormScreen> {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final FirestoreService firestoreService = FirestoreService();

  // ── User inputs ──────────────────────────────────────────────────────────
  DateTime? startDate;
  TimeOfDay? startTime;
  bool isFixedEvent = false;
  bool isSplittable = false;
  DateTime? endDate;
  TimeOfDay? endTime;
  String selectedCategory = "Academic";
  int estimatedDurationMinutes = 60;

  // ── Stage 1 values displayed on the 1–10 UI scale ─────────────────────────
  double urgency = 5.0;
  double importance = 5.0;
  double severity = 5.0;
  double cognitiveLoad = 5.0;
  double energyLevel = 5.0;

  // Automatically generated values
  double? _rawUrgency;
  double? _rawCognitiveLoad;
  double? _rawEnergyLevel;

  // Objective features returned by the backend
  double? _deadlineHours;
  double? _timePressure;

  // User-confirmed fields
  bool _importanceSelected = false;
  bool _severitySelected = false;

  // Track changes to automatically generated values
  bool _urgencyAdjusted = false;
  bool _cognitiveLoadAdjusted = false;
  bool _energyLevelAdjusted = false;

  // UI state
  bool _isPredicting = false;
  bool _isAddingTask = false;
  bool _predicted = false;

  // ─────────────────────────────────────────────────────────────────────────
  // INTERACTIVE slider card
  // ─────────────────────────────────────────────────────────────────────────
  Widget buildSliderCard({
    required String title,
    required String description,
    required IconData icon,
    required double value,
    required Color color,
    required String badgeText,
    required ValueChanged<double> onChanged,
    VoidCallback? onReset,
  }) {
    final bool isUserValue =
        badgeText == "You Adjusted" || badgeText == "Your Input";

    final Color badgeColor = isUserValue
        ? Colors.tealAccent
        : badgeText == "Input Required"
        ? Colors.orangeAccent
        : Colors.deepPurpleAccent;

    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: badgeColor, width: 1),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 11,
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Slider(
              value: value.clamp(1.0, 10.0),
              min: 1,
              max: 10,
              divisions: 9,
              label: value.round().toString(),
              activeColor: _predicted ? color : Colors.grey,
              inactiveColor: Colors.grey.withOpacity(0.3),
              onChanged: _predicted ? onChanged : null,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  !_predicted
                      ? "Analyze the task first"
                      : badgeText == "Input Required"
                      ? "Move the slider to confirm your value"
                      : "$badgeText: ${value.round()}/10",
                  style: TextStyle(
                    color: _predicted ? Colors.white54 : Colors.white30,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _predicted ? value.round().toString() : "-",
                  style: TextStyle(
                    color: _predicted ? color : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (_predicted && onReset != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 14,
                    color: Colors.deepPurpleAccent,
                  ),
                  label: const Text(
                    "Reset Suggestion",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.deepPurpleAccent,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1: Analyze Task
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> analyzeTask() async {
    if (titleController.text.trim().isEmpty) {
      _snack("Please enter a task name");
      return;
    }
    if (startDate == null || startTime == null) {
      _snack("Please select a start time");
      return;
    }
    if (endDate == null || endTime == null) {
      _snack("Please select an end time");
      return;
    }

    final startDT = _combine(startDate!, startTime!);
    final endDT = _combine(endDate!, endTime!);

    if (!endDT.isAfter(startDT)) {
      _snack("End time must be after start time");
      return;
    }

    setState(() => _isPredicting = true);

    try {
      final actualDurationMinutes = isFixedEvent
          ? endDT.difference(startDT).inMinutes
          : estimatedDurationMinutes;

      final taskDuration = _durationCodeFromMinutes(actualDurationMinutes);

      final result = await TaskApiService.predictScores(
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
        category: selectedCategory.toLowerCase(),
        startTime: startDT.toIso8601String(),
        endTime: endDT.toIso8601String(),
        taskDuration: taskDuration,
        estimatedDurationMinutes: actualDurationMinutes,
      );

      final scores = result["predicted_scores"] as Map<String, dynamic>;

      setState(() {
        _rawUrgency = (scores["urgency"] as num).toDouble();

        _rawCognitiveLoad = (scores["cognitive_load"] as num).toDouble();

        _rawEnergyLevel = (scores["energy_level"] as num).toDouble();

        _deadlineHours = (result["deadline_hours"] as num).toDouble();

        _timePressure = (result["time_pressure"] as num).toDouble();

        urgency = _toScale(_rawUrgency!);
        cognitiveLoad = _toScale(_rawCognitiveLoad!);
        energyLevel = _toScale(_rawEnergyLevel!);

        // Importance and consequence require explicit student input.
        importance = 5.0;
        severity = 5.0;
        _importanceSelected = false;
        _severitySelected = false;

        _urgencyAdjusted = false;
        _cognitiveLoadAdjusted = false;
        _energyLevelAdjusted = false;

        _predicted = true;
      });

      _snack(
        "Analysis complete. Review the results and provide the required inputs.",
        color: Colors.deepPurpleAccent,
      );
    } catch (e) {
      _snack("Failed to analyze task: $e");
    } finally {
      setState(() => _isPredicting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2: Add Task
  //   1. Save the new task to Firestore with placeholder ranking values
  //      (we get its doc id back — this is how we find it again later)
  //   2. Re-rank ALL pending tasks together (this is what makes XGBRanker
  //      actually compare tasks against each other, not just one alone)
  //   3. Re-fetch this exact task by id to read its real, final ranking
  //   4. Show the success dialog with the real priority + reason tags
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> addTask() async {
    if (!_predicted) {
      _snack("Please analyze the task first");
      return;
    }

    if (!_importanceSelected || !_severitySelected) {
      _snack("Please set Importance and Consequence of Delay.");
      return;
    }

    setState(() => _isAddingTask = true);

    try {
      final startDT = _combine(startDate!, startTime!);
      final endDT = _combine(endDate!, endTime!);
      final actualDurationMinutes = isFixedEvent
          ? endDT.difference(startDT).inMinutes
          : estimatedDurationMinutes;

      final taskDuration = _durationCodeFromMinutes(actualDurationMinutes);

      // ── Final slider values (LLM or user-adjusted) ───────────────────────
      final finalUrgency = _urgencyAdjusted ? urgency / 10.0 : _rawUrgency!;

      // Always provided by the student.
      final finalImportance = importance / 10.0;
      final finalSeverity = severity / 10.0;

      final finalCognitiveLoad = _cognitiveLoadAdjusted
          ? cognitiveLoad / 10.0
          : _rawCognitiveLoad!;

      final finalEnergyLevel = _energyLevelAdjusted
          ? energyLevel / 10.0
          : _rawEnergyLevel!;

      final bool humanAdjusted =
          _urgencyAdjusted || _cognitiveLoadAdjusted || _energyLevelAdjusted;

      // ── Step 1: Save new task to Firestore, get its doc id back ──────────
      // Ranking fields are placeholders — Step 2 overwrites them for
      // real, once this task is compared against the full pending list.
      final newDocId = await firestoreService.addTask(
        task: {
          "title": titleController.text.trim(),
          "description": descriptionController.text.trim(),
          "category": selectedCategory.toLowerCase(),

          // Timing
          "available_from": startDT.toIso8601String(),
          "deadline": endDT.toIso8601String(),
          "estimated_duration_minutes": actualDurationMinutes,

          // Fixed-event data
          "is_fixed": isFixedEvent,
          "fixed_start": isFixedEvent ? startDT.toIso8601String() : "",
          "fixed_end": isFixedEvent ? endDT.toIso8601String() : "",
          "is_splittable": isFixedEvent ? false : isSplittable,

          // AI-generated or user-adjusted features
          "urgency": finalUrgency,
          "importance_score": finalImportance,
          "severity": finalSeverity,
          "cognitive_load": finalCognitiveLoad,
          "energy_level": finalEnergyLevel,

          // Ranking features
          "deadline_hours": _deadlineHours,
          "time_pressure": _timePressure,
          "task_duration": taskDuration,
          "time_of_day": startDT.hour,
          "day_of_week": startDT.weekday - 1,

          // Schedule result placeholders
          "scheduled_start": "",
          "scheduled_end": "",
          "schedule_date": "",
          "schedule_status": "unscheduled",
          "schedule_failure_reason": "",

          // General task fields
          "created_at": DateTime.now().toIso8601String(),
          "pred_score": 0.0,
          "normalized_score": 50,
          "priority": "Medium",
          "reason_tags": [],
          "status": "pending",
          "snooze_count": 0,
          "postpone_count": 0,
          "is_snoozed": false,
          "snoozed_until": "",
          "conflict_flag": 0,
          "human_adjusted": humanAdjusted,

          "model_scores": {
            "urgency": _rawUrgency,
            "cognitive_load": _rawCognitiveLoad,
            "energy_level": _rawEnergyLevel,
          },

          "confirmed_scores": {
            "urgency": finalUrgency,
            "importance_score": finalImportance,
            "severity": finalSeverity,
            "cognitive_load": finalCognitiveLoad,
            "energy_level": finalEnergyLevel,
          },

          "score_sources": {
            "urgency": _urgencyAdjusted ? "user_adjusted" : "calculated",
            "importance_score": "student_input",
            "severity": "student_input",
            "cognitive_load": _cognitiveLoadAdjusted
                ? "user_adjusted"
                : "model_predicted",
            "energy_level": _energyLevelAdjusted
                ? "user_adjusted"
                : "model_predicted",
          },

          // Only adjustment flags belong here
          "adjusted_fields": {
            "urgency": _urgencyAdjusted,
            "cognitive_load": _cognitiveLoadAdjusted,
            "energy_level": _energyLevelAdjusted,
          },
        },
      );

      // ── Step 2: Re-rank ALL pending tasks together ───────────────────────
      await firestoreService.rerankAllTasks();

      // ── Step 3: Fetch this exact task by its doc id ───────────────────────
      final allTasks = await firestoreService.getAllTasksRaw();
      Map<String, dynamic>? myRankedTask;
      for (final t in allTasks) {
        if (t["id"] == newDocId) {
          myRankedTask = t;
          break;
        }
      }

      // ── Step 4: Success dialog ────────────────────────────────────────────
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.greenAccent,
                  size: 28,
                ),
                const SizedBox(width: 10),
                const Text(
                  "Task Added!",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleController.text.trim(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),

                if (humanAdjusted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.tealAccent.withOpacity(0.4),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 14,
                          color: Colors.tealAccent,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Your adjustments were saved — "
                            "helps improve future predictions.",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.tealAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.blueAccent.withOpacity(0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 14,
                        color: Colors.blueAccent,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "All your tasks have been re-ranked.",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _priorityColor(
                      myRankedTask?["priority"] ?? "Medium",
                    ).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _priorityColor(
                        myRankedTask?["priority"] ?? "Medium",
                      ),
                    ),
                  ),
                  child: Text(
                    "Priority: ${myRankedTask?["priority"] ?? "Medium"}",
                    style: TextStyle(
                      color: _priorityColor(
                        myRankedTask?["priority"] ?? "Medium",
                      ),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                const Text(
                  "Why:",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 6),
                ..._buildReasonTags(myRankedTask?["reason_tags"]),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "OK",
                  style: TextStyle(color: Colors.deepPurpleAccent),
                ),
              ),
            ],
          ),
        );

        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      _snack("Failed to add task: $e");
    } finally {
      if (mounted) setState(() => _isAddingTask = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  double _toScale(double raw) => (raw * 10).clamp(1.0, 10.0).roundToDouble();

  int _durationCodeFromMinutes(int minutes) {
    if (minutes <= 20) return 1;
    if (minutes <= 45) return 2;
    if (minutes <= 90) return 3;
    if (minutes <= 180) return 4;
    return 5;
  }

  void _resetPredictions() {
    _predicted = false;

    _urgencyAdjusted = false;
    _cognitiveLoadAdjusted = false;
    _energyLevelAdjusted = false;

    _importanceSelected = false;
    _severitySelected = false;

    urgency = 5.0;
    importance = 5.0;
    severity = 5.0;
    cognitiveLoad = 5.0;
    energyLevel = 5.0;

    _rawUrgency = null;
    _rawCognitiveLoad = null;
    _rawEnergyLevel = null;

    _deadlineHours = null;
    _timePressure = null;
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Color _priorityColor(dynamic priority) {
    switch (priority?.toString()) {
      case "Critical":
        return Colors.redAccent;
      case "High":
        return Colors.orangeAccent;
      case "Medium":
        return Colors.yellowAccent;
      default:
        return Colors.greenAccent;
    }
  }

  List<Widget> _buildReasonTags(dynamic tags) {
    List<String> tagList = [];
    if (tags is List) {
      tagList = tags.map((t) => t.toString()).toList();
    } else if (tags is String) {
      tagList = tags.split(", ");
    }
    if (tagList.isEmpty) return [];
    return tagList
        .map(
          (tag) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.circle,
                  size: 6,
                  color: Colors.deepPurpleAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tag,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  Future<void> pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() {
      startDate = date;
      startTime = time;
      _resetPredictions();
    });
  }

  Future<void> pickEnd() async {
    final date = await showDatePicker(
      context: context,
      initialDate: startDate ?? DateTime.now(),
      firstDate: startDate ?? DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() {
      endDate = date;
      endTime = time;
      _resetPredictions();
    });
  }

  String _fmt(DateTime? date, TimeOfDay? time) {
    if (date == null || time == null) return "Not set";
    return "${date.day}/${date.month}/${date.year}  •  ${time.format(context)}";
  }

  final List<String> _categories = [
    "Academic",
    "Health",
    "Personal",
    "Finance",
    "Social",
    "Extracurricular",
  ];

  String _formatDurationMinutes(int minutes) {
    if (minutes < 60) return "$minutes minutes";

    final hours = minutes ~/ 60;
    final remaining = minutes % 60;

    if (remaining == 0) {
      return hours == 1 ? "1 hour" : "$hours hours";
    }

    return "${hours}h ${remaining}m";
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart Task Creator"),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Task Name",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: "Enter task name...",
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (_) {
                    if (_predicted) setState(_resetPredictions);
                  },
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "Task Description",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "The model uses this information to understand the task.",
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  controller: descriptionController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText:
                        "Describe your task — what it involves, "
                        "why it matters, any time pressure...",
                  ),
                  onChanged: (_) {
                    if (_predicted) setState(_resetPredictions);
                  },
                ),
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              "Task Type",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("Flexible Task"),
                      selected: !isFixedEvent,
                      onSelected: (_) {
                        setState(() {
                          isFixedEvent = false;
                          _resetPredictions();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text("Fixed Event"),
                      selected: isFixedEvent,
                      onSelected: (_) {
                        setState(() {
                          isFixedEvent = true;

                          // Fixed events cannot be split.
                          isSplittable = false;

                          _resetPredictions();
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),

            if (!isFixedEvent) ...[
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  value: isSplittable,
                  activeThumbColor: Colors.deepPurpleAccent,
                  secondary: const Icon(
                    Icons.call_split_rounded,
                    color: Colors.deepPurpleAccent,
                  ),
                  title: const Text(
                    "Allow task splitting",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    "Schedule this task in multiple focused sessions.",
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  onChanged: (value) {
                    setState(() {
                      isSplittable = value;
                      _resetPredictions();
                    });
                  },
                ),
              ),
            ],

            const SizedBox(height: 18),

            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: const Icon(
                  Icons.play_circle_outline_rounded,
                  color: Colors.greenAccent,
                  size: 32,
                ),
                title: Text(
                  isFixedEvent ? "Fixed Start" : "Available From",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(_fmt(startDate, startTime)),
                trailing: ElevatedButton(
                  onPressed: pickStart,
                  child: const Text("Pick"),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Card(
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: const Icon(
                  Icons.flag_circle_rounded,
                  color: Colors.redAccent,
                  size: 32,
                ),
                title: Text(
                  isFixedEvent ? "Fixed End" : "Deadline",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(_fmt(endDate, endTime)),
                trailing: ElevatedButton(
                  onPressed: pickEnd,
                  child: const Text("Pick"),
                ),
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              "Task Category",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _categories.map((c) {
                final isSelected = selectedCategory == c;

                return ChoiceChip(
                  label: Text(c),
                  selected: isSelected,
                  selectedColor: Colors.cyanAccent,
                  backgroundColor: const Color(0xFF1E293B),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (_) => setState(() {
                    selectedCategory = c;
                    _resetPredictions();
                  }),
                );
              }).toList(),
            ),

            // ── Estimated task duration ───────────────────────────────────────
            const SizedBox(height: 30),

            if (!isFixedEvent) ...[
              const Text(
                "Estimated Duration",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                value: estimatedDurationMinutes,
                dropdownColor: const Color(0xFF1E293B),
                decoration: InputDecoration(
                  labelText: "How long will this task take?",
                  prefixIcon: const Icon(
                    Icons.timer_outlined,
                    color: Colors.deepPurpleAccent,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: Colors.deepPurpleAccent,
                      width: 1.5,
                    ),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 15, child: Text("15 minutes")),
                  DropdownMenuItem(value: 30, child: Text("30 minutes")),
                  DropdownMenuItem(value: 45, child: Text("45 minutes")),
                  DropdownMenuItem(value: 60, child: Text("1 hour")),
                  DropdownMenuItem(value: 90, child: Text("1 hour 30 minutes")),
                  DropdownMenuItem(value: 120, child: Text("2 hours")),
                  DropdownMenuItem(value: 180, child: Text("3 hours")),
                  DropdownMenuItem(value: 240, child: Text("4 hours")),
                  DropdownMenuItem(value: 300, child: Text("5 hours")),
                  DropdownMenuItem(value: 360, child: Text("6 hours")),
                  DropdownMenuItem(value: 480, child: Text("8 hours")),
                ],
                onChanged: (value) {
                  if (value == null) return;

                  setState(() {
                    estimatedDurationMinutes = value;
                    _resetPredictions();
                  });
                },
              ),

              const SizedBox(height: 30),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_clock_rounded,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        startDate != null &&
                                startTime != null &&
                                endDate != null &&
                                endTime != null
                            ? "Event duration: ${_formatDurationMinutes(_combine(endDate!, endTime!).difference(_combine(startDate!, startTime!)).inMinutes)}"
                            : "Select the fixed start and end times",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _predicted
                      ? Colors.green.withOpacity(0.3)
                      : Colors.deepPurpleAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: _isPredicting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _predicted
                            ? Icons.check_circle_rounded
                            : Icons.auto_awesome_rounded,
                        color: Colors.white,
                      ),
                label: Text(
                  _isPredicting
                      ? "Analyzing..."
                      : _predicted
                      ? "Update Priority Analysis"
                      : "Generate Priority Analysis",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _isPredicting ? null : analyzeTask,
              ),
            ),

            if (!_predicted)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  "Task information is used to calculate urgency and suggest "
                  "cognitive load and energy required.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),

            const SizedBox(height: 24),

            if (_predicted) ...[
              const Text(
                "Priority Scores",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                "Review the calculated and model-suggested values. "
                "Set Importance and Impact if Delayed before creating the task.",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              buildSliderCard(
                title: "Urgency",
                icon: Icons.warning_amber_rounded,
                description:
                    "How soon this task needs attention based on its "
                    "deadline and required work time.",
                value: urgency,
                color: Colors.redAccent,
                badgeText: _urgencyAdjusted ? "You Adjusted" : "Calculated",
                onChanged: (v) => setState(() {
                  urgency = v;
                  _urgencyAdjusted = true;
                }),
                onReset: _urgencyAdjusted
                    ? () => setState(() {
                        urgency = _toScale(_rawUrgency ?? 0.5);
                        _urgencyAdjusted = false;
                      })
                    : null,
              ),
              buildSliderCard(
                title: "Importance",
                icon: Icons.star_rounded,
                description:
                    "How important this task is to your personal or academic goals.",
                value: importance,
                color: Colors.blueAccent,
                badgeText: _importanceSelected
                    ? "Your Input"
                    : "Input Required",
                onChanged: (v) => setState(() {
                  importance = v;
                  _importanceSelected = true;
                }),
              ),
              buildSliderCard(
                title: "Consequence of Delay",
                icon: Icons.error_outline_rounded,
                description:
                    "How serious the consequences would be if this task "
                    "is delayed or skipped.",
                value: severity,
                color: Colors.orangeAccent,
                badgeText: _severitySelected ? "Your Input" : "Input Required",
                onChanged: (v) => setState(() {
                  severity = v;
                  _severitySelected = true;
                }),
              ),
              buildSliderCard(
                title: "Cognitive Load",
                icon: Icons.psychology_rounded,
                description: "How mentally demanding this task is.",
                value: cognitiveLoad,
                color: Colors.purpleAccent,
                badgeText: _cognitiveLoadAdjusted
                    ? "You Adjusted"
                    : "Model Suggested",
                onChanged: (v) => setState(() {
                  cognitiveLoad = v;
                  _cognitiveLoadAdjusted = true;
                }),
                onReset: _cognitiveLoadAdjusted
                    ? () => setState(() {
                        cognitiveLoad = _toScale(_rawCognitiveLoad ?? 0.5);
                        _cognitiveLoadAdjusted = false;
                      })
                    : null,
              ),
              buildSliderCard(
                title: "Energy Required",
                icon: Icons.bolt_rounded,
                description:
                    "How much physical or mental energy this task requires.",
                value: energyLevel,
                color: Colors.yellowAccent,
                badgeText: _energyLevelAdjusted
                    ? "You Adjusted"
                    : "Model Suggested",
                onChanged: (v) => setState(() {
                  energyLevel = v;
                  _energyLevelAdjusted = true;
                }),
                onReset: _energyLevelAdjusted
                    ? () => setState(() {
                        energyLevel = _toScale(_rawEnergyLevel ?? 0.5);
                        _energyLevelAdjusted = false;
                      })
                    : null,
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _predicted
                        ? Colors.deepPurpleAccent
                        : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: !_isAddingTask ? addTask : null,
                  child: _isAddingTask
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "Create Task",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
