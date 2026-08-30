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
  String _submissionStatus = "Create & Rank Task";
  bool _predicted = false;

  // Editors remain hidden until the student chooses to adjust a
  // calculated or Stage 1 ML-generated value.
  bool _showUrgencyEditor = false;
  bool _showCognitiveEditor = false;
  bool _showEnergyEditor = false;

  // ─────────────────────────────────────────────────────────────────────────
  // PRODUCT-LEVEL PRIORITY ANALYSIS COMPONENTS
  // ─────────────────────────────────────────────────────────────────────────

  String _scoreLabel(double value) {
    final score = value.round();

    if (score <= 3) return "Low";
    if (score <= 6) return "Moderate";
    if (score <= 8) return "High";
    return "Very High";
  }

  Widget _buildSourceBadge({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisCompleteBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF6D5DFB).withValues(alpha: 0.22),
            const Color(0xFF22D3EE).withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF8B7CFF).withValues(alpha: 0.45),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF7C6CFF),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(7),
              child: Icon(Icons.check_rounded, size: 18, color: Colors.white),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Priority analysis complete",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  "Time Urgency was calculated from the available time, "
                  "deadline and required work time. Cognitive Load and "
                  "Energy Required were predicted by the Stage 1 ML model.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemScoreRow({
    required String title,
    required String description,
    required IconData icon,
    required double value,
    required double originalValue,
    required Color color,
    required String sourceLabel,
    required IconData sourceIcon,
    required bool adjusted,
    required bool editorVisible,
    required VoidCallback onToggleEditor,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${value.round()}/10",
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _scoreLabel(value),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              _buildSourceBadge(
                label: adjusted ? "Student adjusted" : sourceLabel,
                icon: adjusted ? Icons.person_rounded : sourceIcon,
                color: adjusted ? Colors.tealAccent : color,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onToggleEditor,
                icon: Icon(
                  editorVisible ? Icons.close_rounded : Icons.tune_rounded,
                  size: 16,
                ),
                label: Text(editorVisible ? "Done" : "Adjust"),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),

          if (adjusted) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.compare_arrows_rounded,
                    color: Colors.tealAccent,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Original: ${originalValue.round()}/10  →  "
                      "Your adjustment: ${value.round()}/10",
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(onPressed: onReset, child: const Text("Restore")),
                ],
              ),
            ),
          ],

          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: editorVisible
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 5,
                            activeTrackColor: color,
                            inactiveTrackColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            thumbColor: color,
                            overlayColor: color.withValues(alpha: 0.12),
                            valueIndicatorColor: color,
                            showValueIndicator: ShowValueIndicator.always,
                          ),
                          child: Slider(
                            value: value.clamp(1.0, 10.0),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            label: value.round().toString(),
                            onChanged: onChanged,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Low",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                "Moderate",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                "Very High",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemAnalysisCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF172235),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "SYSTEM ANALYSIS",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),

          _buildSystemScoreRow(
            title: "Time Urgency",
            description:
                "How soon this task needs attention based on its deadline "
                "and required work time. Final priority also considers "
                "your ratings and other pending tasks.",
            icon: Icons.schedule_rounded,
            value: urgency,
            originalValue: _toScale(_rawUrgency ?? 0.5),
            color: const Color(0xFF60A5FA),
            sourceLabel: "Calculated",
            sourceIcon: Icons.calculate_rounded,
            adjusted: _urgencyAdjusted,
            editorVisible: _showUrgencyEditor,
            onToggleEditor: () {
              setState(() {
                _showUrgencyEditor = !_showUrgencyEditor;
              });
            },
            onChanged: (value) {
              setState(() {
                urgency = value;
                _urgencyAdjusted = true;
              });
            },
            onReset: () {
              setState(() {
                urgency = _toScale(_rawUrgency ?? 0.5);
                _urgencyAdjusted = false;
              });
            },
          ),

          Divider(color: Colors.white.withValues(alpha: 0.08)),

          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 2),
            child: Row(
              children: [
                _buildSourceBadge(
                  label: "Stage 1 ML predictions",
                  icon: Icons.auto_awesome_rounded,
                  color: const Color(0xFF9B87FF),
                ),
              ],
            ),
          ),

          _buildSystemScoreRow(
            title: "Cognitive Load",
            description: "Estimated mental demand for completing this task.",
            icon: Icons.psychology_rounded,
            value: cognitiveLoad,
            originalValue: _toScale(_rawCognitiveLoad ?? 0.5),
            color: const Color(0xFFB56CFF),
            sourceLabel: "Stage 1 ML",
            sourceIcon: Icons.model_training_rounded,
            adjusted: _cognitiveLoadAdjusted,
            editorVisible: _showCognitiveEditor,
            onToggleEditor: () {
              setState(() {
                _showCognitiveEditor = !_showCognitiveEditor;
              });
            },
            onChanged: (value) {
              setState(() {
                cognitiveLoad = value;
                _cognitiveLoadAdjusted = true;
              });
            },
            onReset: () {
              setState(() {
                cognitiveLoad = _toScale(_rawCognitiveLoad ?? 0.5);
                _cognitiveLoadAdjusted = false;
              });
            },
          ),

          Divider(color: Colors.white.withValues(alpha: 0.08)),

          _buildSystemScoreRow(
            title: "Energy Required",
            description:
                "Estimated physical or mental energy needed for the task.",
            icon: Icons.bolt_rounded,
            value: energyLevel,
            originalValue: _toScale(_rawEnergyLevel ?? 0.5),
            color: const Color(0xFF9B87FF),
            sourceLabel: "Stage 1 ML",
            sourceIcon: Icons.model_training_rounded,
            adjusted: _energyLevelAdjusted,
            editorVisible: _showEnergyEditor,
            onToggleEditor: () {
              setState(() {
                _showEnergyEditor = !_showEnergyEditor;
              });
            },
            onChanged: (value) {
              setState(() {
                energyLevel = value;
                _energyLevelAdjusted = true;
              });
            },
            onReset: () {
              setState(() {
                energyLevel = _toScale(_rawEnergyLevel ?? 0.5);
                _energyLevelAdjusted = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSelector({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required double value,
    required bool selected,
    required ValueChanged<double> onSelected,
  }) {
    final selectedScore = value.round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF172235),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? Colors.tealAccent.withValues(alpha: 0.28)
              : Colors.orangeAccent.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _buildSourceBadge(
                label: selected ? "Your input" : "Input required",
                icon: selected
                    ? Icons.person_rounded
                    : Icons.priority_high_rounded,
                color: selected ? Colors.tealAccent : Colors.orangeAccent,
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            description,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 16),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 10,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.35,
            ),
            itemBuilder: (context, index) {
              final score = index + 1;
              final isSelected = selected && selectedScore == score;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelected(score.toDouble()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color
                          : Colors.white.withValues(alpha: 0.055),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : Colors.white.withValues(alpha: 0.10),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.24),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      score.toString(),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Low",
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              Text(
                "Moderate",
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              Text(
                "Very High",
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),

          if (selected) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.tealAccent,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Selected: $selectedScore/10 · "
                    "${_scoreLabel(value)}",
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentConfirmationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Your Confirmation",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          "These values depend on your personal goals and the consequences "
          "you expect. Select one score for each.",
          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 14),

        _buildRatingSelector(
          title: "Importance",
          description:
              "How important is this task to your personal or academic goals?",
          icon: Icons.star_rounded,
          color: const Color(0xFF4F8CFF),
          value: importance,
          selected: _importanceSelected,
          onSelected: (score) {
            setState(() {
              importance = score;
              _importanceSelected = true;
            });
          },
        ),

        const SizedBox(height: 14),

        _buildRatingSelector(
          title: "Consequence of Delay",
          description:
              "How serious would the consequences be if this task were "
              "delayed or skipped?",
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFFFA63D),
          value: severity,
          selected: _severitySelected,
          onSelected: (score) {
            setState(() {
              severity = score;
              _severitySelected = true;
            });
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1: Analyze Task
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> analyzeTask() async {
    if (_isPredicting || _isAddingTask) {
      return;
    }

    FocusScope.of(context).unfocus();

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

      if (!mounted) {
        return;
      }

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

        _showUrgencyEditor = false;
        _showCognitiveEditor = false;
        _showEnergyEditor = false;
      });

      _snack(
        "Analysis complete. Review the results and provide the required inputs.",
        color: const Color(0xFF4C8DFF),
      );
    } catch (e) {
      _snack("Failed to analyze task: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isPredicting = false;
        });
      }
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
    if (_isAddingTask || _isPredicting) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (!_predicted) {
      _snack("Please analyze the task first");
      return;
    }

    if (!_importanceSelected || !_severitySelected) {
      _snack("Please set Importance and Consequence of Delay.");
      return;
    }

    setState(() {
      _isAddingTask = true;
      _submissionStatus = "Saving task...";
    });

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

      if (!mounted) {
        return;
      }

      setState(() {
        _submissionStatus = "Comparing priorities...";
      });

      // ── Step 2: Re-rank ALL pending tasks together ───────────────────────
      await firestoreService.rerankAllTasks();

      if (!mounted) {
        return;
      }

      setState(() {
        _submissionStatus = "Preparing results...";
      });

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
                  style: TextStyle(color: const Color(0xFF4C8DFF)),
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
      if (mounted) {
        setState(() {
          _isAddingTask = false;
          _submissionStatus = "Create & Rank Task";
        });
      }
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

    _showUrgencyEditor = false;
    _showCognitiveEditor = false;
    _showEnergyEditor = false;

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
                  color: const Color(0xFF4C8DFF),
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
    FocusScope.of(context).unfocus();

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final initialDate = startDate == null || startDate!.isBefore(today)
        ? today
        : startDate!;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(2030, 12, 31),
    );

    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: startTime ?? TimeOfDay.now(),
    );

    if (time == null || !mounted) {
      return;
    }

    setState(() {
      startDate = date;
      startTime = time;

      /*
     * If the existing deadline would now be before the new
     * availability time, clear it instead of leaving invalid data.
     */
      if (endDate != null && endTime != null) {
        final selectedStart = _combine(date, time);

        final selectedEnd = _combine(endDate!, endTime!);

        if (!selectedEnd.isAfter(selectedStart)) {
          endDate = null;
          endTime = null;
        }
      }

      _resetPredictions();
    });
  }

  Future<void> pickEnd() async {
    FocusScope.of(context).unfocus();

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final earliestDate = startDate ?? today;

    final initialDate = endDate != null && !endDate!.isBefore(earliestDate)
        ? endDate!
        : earliestDate;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: earliestDate,
      lastDate: DateTime(2030, 12, 31),
    );

    if (date == null || !mounted) {
      return;
    }

    TimeOfDay suggestedTime = endTime ?? TimeOfDay.now();

    /*
   * When the deadline date is the same as the availability
   * date, suggest a sensible time after the task begins.
   */
    if (startDate != null &&
        startTime != null &&
        date.year == startDate!.year &&
        date.month == startDate!.month &&
        date.day == startDate!.day &&
        endTime == null) {
      final suggestedDateTime = _combine(
        startDate!,
        startTime!,
      ).add(Duration(minutes: estimatedDurationMinutes));

      suggestedTime = TimeOfDay.fromDateTime(suggestedDateTime);
    }

    final time = await showTimePicker(
      context: context,
      initialTime: suggestedTime,
    );

    if (time == null || !mounted) {
      return;
    }

    final selectedEnd = _combine(date, time);

    if (startDate != null && startTime != null) {
      final selectedStart = _combine(startDate!, startTime!);

      if (!selectedEnd.isAfter(selectedStart)) {
        _snack(
          "Deadline must be after the available-from time.",
          color: Colors.orangeAccent,
        );

        return;
      }
    }

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
                  activeThumbColor: const Color(0xFF4C8DFF),
                  secondary: const Icon(
                    Icons.call_split_rounded,
                    color: const Color(0xFF4C8DFF),
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
                    color: const Color(0xFF4C8DFF),
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
                      color: const Color(0xFF4C8DFF),
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
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _predicted
                      ? Colors.green.withValues(alpha: 0.30)
                      : const Color(0xFF4C8DFF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF4C8DFF).withValues(
                    alpha: 0.40,
                  ),
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _isPredicting || _isAddingTask ? null : analyzeTask,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _isPredicting
                      ? const Row(
                          key: ValueKey<String>('analyzing'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              "Analyzing...",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          key: ValueKey<String>(
                            _predicted
                                ? 'update-analysis'
                                : 'generate-analysis',
                          ),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _predicted
                                  ? Icons.check_circle_rounded
                                  : Icons.auto_awesome_rounded,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _predicted
                                  ? "Update Priority Analysis"
                                  : "Generate Priority Analysis",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
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
              _buildAnalysisCompleteBanner(),

              const SizedBox(height: 24),

              const Text(
                "Priority Analysis",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),

              const SizedBox(height: 5),

              const Text(
                "Review the system-generated results, then provide the two "
                "values that require your personal judgement.",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 14),

              _buildSystemAnalysisCard(),

              const SizedBox(height: 26),

              _buildStudentConfirmationSection(),

              const SizedBox(height: 30),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF172235),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF7C6CFF,
                            ).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.sort_rounded,
                            color: Color(0xFF9B87FF),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Stage 2 Task Ranking",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                "This task will be compared with your pending tasks "
                                "to determine its priority.",
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _importanceSelected && _severitySelected
                              ? const Color(0xFF7C4DFF)
                              : Colors.white.withValues(alpha: 0.08),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white.withValues(
                            alpha: 0.08,
                          ),
                          disabledForegroundColor: Colors.white38,
                          elevation: _importanceSelected && _severitySelected
                              ? 4
                              : 0,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed:
                            !_isAddingTask &&
                                !_isPredicting &&
                                _importanceSelected &&
                                _severitySelected
                            ? addTask
                            : null,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _isAddingTask
                              ? Row(
                                  key: ValueKey<String>(_submissionStatus),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 19,
                                      height: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        _submissionStatus,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : const Row(
                                  key: ValueKey<String>('create-task'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.auto_awesome_rounded),
                                    SizedBox(width: 8),
                                    Text(
                                      "Create & Rank Task",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),

                    if (!_importanceSelected || !_severitySelected) ...[
                      const SizedBox(height: 10),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Colors.orangeAccent,
                            size: 14,
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              "Complete both required ratings to continue",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
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
