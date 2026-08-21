import '../services/task_api_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/productivity_analytics_service.dart';

// ---------------------------------------------------------------------------
// DATA MODEL
// ---------------------------------------------------------------------------

class _ReflectionData {
  final int completed;
  final int pending;
  final int snoozed;
  final int postponed;
  final double completionRate;
  final double productivityScore;
  final Map<String, int> completedByCategory;
  final Map<String, int> pendingByCategory;
  final Map<String, int> actionableByCategory;
  final Map<String, int> upcomingByCategory;
  final List<Map<String, dynamic>> completedTasks;
  final List<Map<String, dynamic>> tomorrowTasks;
  final List<String> insights;
  final int urgentCompleted;
  final double completionPoints;
  final double priorityPoints;
  final double behaviourPoints;
  final String reflectionSummary;
  final List<String> reflectionStrengths;
  final List<String> reflectionImprovements;
  final String tomorrowFocus;

  final int actionablePending;
  final int upcoming;

  _ReflectionData({
    required this.completed,
    required this.pending,
    required this.snoozed,
    required this.postponed,
    required this.completionRate,
    required this.productivityScore,
    required this.completedByCategory,
    required this.pendingByCategory,
    required this.actionableByCategory,
    required this.upcomingByCategory,
    required this.completedTasks,
    required this.tomorrowTasks,
    required this.insights,
    required this.urgentCompleted,
    required this.completionPoints,
    required this.priorityPoints,
    required this.behaviourPoints,
    required this.reflectionSummary,
    required this.reflectionStrengths,
    required this.reflectionImprovements,
    required this.tomorrowFocus,

    required this.actionablePending,
    required this.upcoming,
  });
}

// ---------------------------------------------------------------------------
// SCREEN
// ---------------------------------------------------------------------------

class DailyReflectionScreen extends StatelessWidget {
  const DailyReflectionScreen({super.key});

  String _categoryName(dynamic raw) {
    if (raw == null) return 'Other';
    final s = raw.toString();
    return s.isEmpty ? 'Other' : s[0].toUpperCase() + s.substring(1);
  }

  DateTime? _parseTaskDate(dynamic value) {
    if (value == null) {
      return null;
    }

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

  Future<_ReflectionData> _buildReflectionData() async {
    final analytics = await ProductivityAnalyticsService().getAnalyticsForDay(
      DateTime.now(),
    );

    final now = DateTime.now();

    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final endOfTomorrow = DateTime(
      now.year,
      now.month,
      now.day + 1,
      23,
      59,
      59,
    );

    final completed = analytics.completed;
    final pending = analytics.pending;
    final actionablePending = analytics.actionablePending;
    final upcoming = analytics.upcoming;
    final snoozed = analytics.snoozes;
    final postponed = analytics.postpones;
    final completionRate = analytics.completionRate;
    final productivityScore = analytics.productivityScore;

    final todayTasks = analytics.relevantTasks;

    // ── Tomorrow's tasks ───────────────────────────────────────────────────
    final tomorrowSnap = await FirebaseFirestore.instance
        .collection('tasks')
        .where('deadline', isGreaterThanOrEqualTo: tomorrow.toIso8601String())
        .where('deadline', isLessThanOrEqualTo: endOfTomorrow.toIso8601String())
        .get();

    int urgentCompleted = 0;
    int highCognitivePostponed = 0;

    final Map<String, int> completedByCategory = {};
    final Map<String, int> pendingByCategory = {};
    final Map<String, int> actionableByCategory = {};
    final Map<String, int> upcomingByCategory = {};
    final List<Map<String, dynamic>> completedTasks = [];

    for (final d in analytics.relevantTasks) {
      final category = _categoryName(d['category']);
      final status = d['status'] ?? 'pending';

      final postponeCount = (d['postpone_count'] as num?)?.toInt() ?? 0;

      final urgency = (d['urgency'] as num?)?.toDouble() ?? 0.0;

      final cognitiveLoad = (d['cognitive_load'] as num?)?.toDouble() ?? 0.0;

      if (status == 'completed') {
        completedByCategory[category] =
            (completedByCategory[category] ?? 0) + 1;

        completedTasks.add({
          'title': d['title'] ?? 'Untitled',
          'priority': d['priority'] ?? 'Medium',
          'category': category,
        });

        if (urgency >= 0.7) {
          urgentCompleted++;
        }
      } else {
        // Retain the overall pending-category map for the backend.
        pendingByCategory[category] = (pendingByCategory[category] ?? 0) + 1;

        final availableFrom = _parseTaskDate(d['available_from']);

        final isUpcoming = availableFrom != null && availableFrom.isAfter(now);

        if (isUpcoming) {
          upcomingByCategory[category] =
              (upcomingByCategory[category] ?? 0) + 1;
        } else {
          actionableByCategory[category] =
              (actionableByCategory[category] ?? 0) + 1;
        }
      }

      if (cognitiveLoad >= 0.7 && postponeCount > 0) {
        highCognitivePostponed++;
      }
    }

    // ── Insights ───────────────────────────────────────────────────────────
    final List<String> insights = [];

    if (completionRate >= 0.8) {
      insights.add('Excellent task completion — strong focus today!');
    } else if (completionRate >= 0.5) {
      insights.add('Moderate completion rate — room to improve tomorrow.');
    } else {
      insights.add('Low completion observed — consider reducing task load.');
    }

    if (snoozed >= 3) {
      insights.add(
        'Frequent snoozing detected — possible procrastination pattern.',
      );
    }
    if (postponed >= 3) {
      insights.add(
        'High postponements — consider breaking tasks into smaller steps.',
      );
    }
    if (highCognitivePostponed >= 2) {
      insights.add(
        'High cognitive-load tasks were avoided — plan energy-heavy tasks for peak hours.',
      );
    }
    if (urgentCompleted >= 2) {
      insights.add(
        'Urgent tasks handled well — great deadline responsiveness!',
      );
    }

    // ── Tomorrow tasks (filter completed in Dart to avoid composite index) ──
    final List<Map<String, dynamic>> tomorrowTasks = tomorrowSnap.docs
        .where((doc) => doc.data()['status'] != 'completed')
        .map((doc) {
          final d = doc.data();
          return {
            'title': d['title'] ?? 'Untitled',
            'priority': d['priority'] ?? 'Medium',
            'category': _categoryName(d['category']),
            'deadline': d['deadline'] ?? '',
          };
        })
        .toList();

    final pendingHighPriorityTasks = todayTasks
        .where((task) {
          final status = (task['status'] ?? 'pending').toString().toLowerCase();

          final priority = (task['priority'] ?? '').toString().toLowerCase();

          return status != 'completed' &&
              (priority == 'critical' || priority == 'high');
        })
        .map((task) {
          return {
            'title': task['title'] ?? 'Untitled',
            'priority': task['priority'] ?? 'Medium',
            'category': _categoryName(task['category']),
          };
        })
        .toList();

    final pendingHighPriorityCount = pendingHighPriorityTasks.length;

    final overdueTasks = todayTasks
        .where((task) {
          final status = (task['status'] ?? 'pending').toString().toLowerCase();

          if (status == 'completed') {
            return false;
          }

          final deadlineRaw = task['deadline'];

          if (deadlineRaw == null || deadlineRaw.toString().isEmpty) {
            return false;
          }

          final deadline = DateTime.tryParse(deadlineRaw.toString())?.toLocal();

          if (deadline == null) {
            return false;
          }

          return deadline.isBefore(DateTime.now());
        })
        .map((task) {
          return {
            'title': task['title'] ?? 'Untitled',
            'priority': task['priority'] ?? 'Medium',
            'category': _categoryName(task['category']),
            'deadline': task['deadline'] ?? '',
          };
        })
        .toList();

    final overdueTaskCount = overdueTasks.length;

    final overdueHighPriorityTasks = overdueTasks.where((task) {
      final priority = (task['priority'] ?? '').toString().toLowerCase();

      return priority == 'critical' || priority == 'high';
    }).toList();

    final overdueHighPriorityCount = overdueHighPriorityTasks.length;

    final tomorrowHighPriorityCount = tomorrowTasks.where((task) {
      final priority = (task['priority'] ?? '').toString().toLowerCase();

      return priority == 'critical' || priority == 'high';
    }).length;

    Map<String, dynamic> reflectionResult = {};

    try {
      reflectionResult = await TaskApiService.generateReflection(
        completionRate: analytics.completionRate,
        priorityAdherence: analytics.priorityAdherence,
        scheduleStability: analytics.behaviourScore,

        completed: analytics.completed,
        pending: analytics.pending,
        actionablePending: analytics.actionablePending,
        upcoming: analytics.upcoming,
        scoredTaskCount: analytics.actionableTasks,
        isProvisional: true,
        snoozes: analytics.snoozes,
        postpones: analytics.postpones,
        highCognitivePostponed: highCognitivePostponed,
        completedByCategory: completedByCategory,
        pendingByCategory: pendingByCategory,
        tomorrowHighPriorityCount: tomorrowHighPriorityCount,

        highPriorityTotal: analytics.highPriorityTotal,
        highPriorityCompleted: analytics.highPriorityCompleted,
        pendingHighPriorityCount: pendingHighPriorityCount,
        pendingHighPriorityTasks: pendingHighPriorityTasks,

        overdueTaskCount: overdueTaskCount,
        overdueHighPriorityCount: overdueHighPriorityCount,
        overdueTasks: overdueTasks,
        overdueHighPriorityTasks: overdueHighPriorityTasks,

        completedOnTime: analytics.completedOnTime,
        completedLate: analytics.completedLate,
        overduePending: analytics.overduePending,
      );
    } catch (e) {
      debugPrint('Reflection API error: $e');
    }

    final reflectionSummary =
        reflectionResult['summary']?.toString() ??
        (analytics.actionablePending > 0
            ? 'Your day is still in progress. Focus on the tasks that are currently actionable.'
            : analytics.upcoming > 0
            ? 'You have completed your currently actionable work. Additional tasks are scheduled for later today.'
            : analytics.completed > 0
            ? 'You have completed today’s currently recorded tasks.'
            : 'No actionable task activity is available for reflection yet.');

    final reflectionStrengths =
        (reflectionResult['strengths'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final reflectionImprovements =
        (reflectionResult['improvements'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final tomorrowFocus =
        reflectionResult['tomorrow_focus']?.toString() ??
        (analytics.actionablePending > 0
            ? 'Complete your remaining actionable work before planning tomorrow.'
            : analytics.upcoming > 0
            ? 'Review your upcoming tasks later today before preparing tomorrow’s plan.'
            : 'Review tomorrow’s highest-priority tasks and reserve suitable time for them.');

    return _ReflectionData(
      completed: completed,
      pending: pending,
      snoozed: snoozed,
      postponed: postponed,
      completionRate: completionRate,
      productivityScore: productivityScore,
      completedByCategory: completedByCategory,
      pendingByCategory: pendingByCategory,
      actionableByCategory: actionableByCategory,
      upcomingByCategory: upcomingByCategory,
      completedTasks: completedTasks,
      tomorrowTasks: tomorrowTasks,
      insights: insights,
      urgentCompleted: urgentCompleted,
      completionPoints: analytics.completionPoints,
      priorityPoints: analytics.priorityPoints,
      behaviourPoints: analytics.behaviourPoints,
      reflectionSummary: reflectionSummary,
      reflectionStrengths: reflectionStrengths,
      reflectionImprovements: reflectionImprovements,
      tomorrowFocus: tomorrowFocus,

      actionablePending: actionablePending,
      upcoming: upcoming,
    );
  }

  // ── Colours ──────────────────────────────────────────────────────────────
  static const _bg = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);
  static const _accent = Color(0xFF6C63FF);
  static const _green = Color(0xFF10B981);
  static const _orange = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);
  static const _blue = Color(0xFF3B82F6);
  static const _textPrimary = Color(0xFFF1F5F9);
  static const _textSecondary = Color(0xFF94A3B8);

  // ── Priority colour ──────────────────────────────────────────────────────
  Color _priorityColor(String p) {
    switch (p.toLowerCase()) {
      case 'critical':
        return _red;
      case 'high':
        return _orange;
      case 'medium':
        return _blue;
      default:
        return _textSecondary;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionTitle({
    required String title,
    required IconData icon,
    Color color = _accent,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardBox(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _statChip(String label, String value, Color color) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: _textSecondary)),
    ],
  );

  Widget _categoryRow(String cat, int count, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            cat,
            style: const TextStyle(fontSize: 13, color: _textPrimary),
          ),
        ),
        Text(
          '$count task${count != 1 ? "s" : ""}',
          style: const TextStyle(fontSize: 13, color: _textSecondary),
        ),
      ],
    ),
  );

  Widget _taskRow(Map<String, dynamic> t, {bool showDeadline = false}) {
    final deadline = t['deadline'] as String? ?? '';
    String deadlineStr = '';
    if (showDeadline && deadline.isNotEmpty) {
      try {
        final dt = DateTime.parse(deadline);
        deadlineStr =
            'Due ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            showDeadline ? Icons.schedule_rounded : Icons.check_circle_rounded,
            size: 16,
            color: showDeadline ? _orange : _green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t['title'] as String,
              style: const TextStyle(fontSize: 13, color: _textPrimary),
            ),
          ),
          if (deadlineStr.isNotEmpty)
            Text(
              deadlineStr,
              style: const TextStyle(fontSize: 11, color: _textSecondary),
            ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _priorityColor(t['priority'] as String).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              t['priority'] as String,
              style: TextStyle(
                fontSize: 10,
                color: _priorityColor(t['priority'] as String),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _insightRow(String text, {Color color = _accent}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: _textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Score bar ─────────────────────────────────────────────────────────────
  Widget _scoreBreakdownRow(
    String label,
    double pts,
    double maxPts,
    Color color,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: _textSecondary),
              ),
            ),
            Text(
              '${pts.toStringAsFixed(1)} / ${maxPts.toInt()}pts',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: maxPts > 0 ? (pts / maxPts).clamp(0.0, 1.0) : 0,
            minHeight: 5,
            backgroundColor: _bg,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    ),
  );

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr =
        '${_weekday(now.weekday)}, ${_monthName(now.month)} ${now.day}';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'Daily AI Reflection',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: _textPrimary),
      ),
      body: FutureBuilder<_ReflectionData>(
        future: _buildReflectionData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: _red.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_off_rounded,
                        color: _red,
                        size: 27,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Reflection unavailable",
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "We couldn't load today's reflection. Please return and try again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final r = snapshot.data!;
          final scoreColor = r.productivityScore >= 80
              ? _green
              : r.productivityScore >= 50
              ? _orange
              : _red;

          final double completionPts = r.completionPoints;
          final double priorityPts = r.priorityPoints;
          final double behaviourPts = r.behaviourPoints;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Date header ──────────────────────────────────────────
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Insights ──────────────────────────────────────────
                _sectionTitle(
                  title: "Today's Reflection",
                  icon: Icons.auto_awesome_rounded,
                ),

                _cardBox(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.reflectionSummary,
                        style: const TextStyle(
                          fontSize: 14,
                          color: _textPrimary,
                          height: 1.5,
                        ),
                      ),

                      if (r.reflectionStrengths.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Strengths',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _green,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...r.reflectionStrengths.map(
                          (item) => _insightRow(item, color: _green),
                        ),
                      ],

                      if (r.reflectionImprovements.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Improvements',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _orange,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...r.reflectionImprovements.map(
                          (item) => _insightRow(item, color: _orange),
                        ),
                      ],

                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _accent.withOpacity(0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _accent.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.flag_rounded,
                                color: _accent,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Tomorrow's Focus",
                                    style: TextStyle(
                                      color: _accent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    r.tomorrowFocus,
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Productivity Score Card ──────────────────────────────
                _sectionTitle(
                  title: "Today's Provisional Score",
                  icon: Icons.insights_rounded,
                  color: scoreColor,
                ),
                _cardBox(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${r.productivityScore.toStringAsFixed(1)}/100',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: scoreColor,
                              ),
                            ),
                          ),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _accent.withOpacity(0.30),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.pending_actions_rounded,
                                  size: 14,
                                  color: _accent,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  "PROVISIONAL",
                                  style: TextStyle(
                                    color: _accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        "A live summary of today's progress. It may change as remaining tasks become actionable.",
                        style: TextStyle(
                          fontSize: 11,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Stat row ─────────────────────────────────────────
                      Wrap(
                        spacing: 24,
                        runSpacing: 14,
                        alignment: WrapAlignment.spaceAround,
                        children: [
                          _statChip('Done', '${r.completed}', _green),
                          _statChip(
                            'Actionable',
                            '${r.actionablePending}',
                            _orange,
                          ),
                          _statChip(
                            'Upcoming',
                            '${r.upcoming}',
                            Colors.cyanAccent,
                          ),
                          _statChip('Snoozed', '${r.snoozed}', _blue),
                          _statChip('Postponed', '${r.postponed}', _red),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // ── Score breakdown ───────────────────────────────────
                      const Text(
                        'How your score was calculated',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _scoreBreakdownRow(
                        'Completion Rate (40%)',
                        completionPts,
                        40,
                        _green,
                      ),
                      _scoreBreakdownRow(
                        'Priority Adherence (35%)',
                        priorityPts,
                        35,
                        _accent,
                      ),
                      _scoreBreakdownRow(
                        'Plan Consistency (25%)',
                        behaviourPts.clamp(0.0, 25.0),
                        25,
                        _orange,
                      ),
                    ],
                  ),
                ),

                // ── Category Breakdown ───────────────────────────────────
                _sectionTitle(
                  title: "Activity Breakdown",
                  icon: Icons.category_rounded,
                ),

                _cardBox(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (r.completedByCategory.isEmpty &&
                          r.actionableByCategory.isEmpty &&
                          r.upcomingByCategory.isEmpty)
                        const Text(
                          'No tasks recorded today.',
                          style: TextStyle(color: _textSecondary),
                        ),

                      ...r.completedByCategory.entries.map(
                        (e) => _categoryRow(
                          '${e.key} — Completed',
                          e.value,
                          _green,
                        ),
                      ),

                      ...r.actionableByCategory.entries.map(
                        (e) => _categoryRow(
                          '${e.key} — Actionable',
                          e.value,
                          _orange,
                        ),
                      ),

                      ...r.upcomingByCategory.entries.map(
                        (e) => _categoryRow(
                          '${e.key} — Upcoming',
                          e.value,
                          Colors.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Completed Tasks ──────────────────────────────────────
                if (r.completedTasks.isNotEmpty) ...[
                  _sectionTitle(
                    title: "Completed Tasks",
                    icon: Icons.task_alt_rounded,
                    color: _green,
                  ),
                  _cardBox(
                    Column(
                      children: r.completedTasks
                          .map((t) => _taskRow(t))
                          .toList(),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  String _weekday(int d) => const [
    '',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][d];

  String _monthName(int m) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][m];
}
