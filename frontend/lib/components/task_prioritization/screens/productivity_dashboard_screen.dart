import 'package:fl_chart/fl_chart.dart';
import '../services/productivity_analytics_service.dart';
import 'package:flutter/material.dart';
import 'daily_reflection_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProductivityDashboardScreen extends StatefulWidget {
  const ProductivityDashboardScreen({super.key});

  @override
  State<ProductivityDashboardScreen> createState() =>
      _ProductivityDashboardScreenState();
}

class _ProductivityDashboardScreenState
    extends State<ProductivityDashboardScreen> {
  late final Stream<Map<String, dynamic>> _dashboardStream;

  @override
  void initState() {
    super.initState();

    _dashboardStream = FirebaseFirestore.instance
        .collection('tasks')
        .snapshots()
        .asyncMap((_) => fetchDashboardData());
  }

  Future<Map<String, dynamic>> fetchDashboardData() async {
    final service = ProductivityAnalyticsService();

    final today = await service.getAnalyticsForDay(DateTime.now());

    final trends = await service.getLast7DaysAnalytics();

    // Exclude days with no relevant tasks from the average.
    final now = DateTime.now();

    final completedActiveDays = trends.where((day) {
      final isToday =
          day.date.year == now.year &&
          day.date.month == now.month &&
          day.date.day == now.day;

      final hasTasks = day.completed + day.pending > 0;

      return hasTasks && !isToday;
    }).toList();

    double sevenDayAverage = 0.0;

    if (completedActiveDays.isNotEmpty) {
      sevenDayAverage =
          completedActiveDays
              .map((day) => day.productivityScore)
              .reduce((a, b) => a + b) /
          completedActiveDays.length;
    }

    DailyProductivityTrend? bestDay;

    if (completedActiveDays.isNotEmpty) {
      bestDay = completedActiveDays.reduce(
        (a, b) => a.productivityScore >= b.productivityScore ? a : b,
      );
    }

    return {
      "today": today,
      "trends": trends,
      "sevenDayAverage": sevenDayAverage,
      "bestDay": bestDay,
    };
  }

  String _shortDayName(DateTime date) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return names[date.weekday - 1];
  }

  Widget _buildProductivityChart(List<DailyProductivityTrend> trends) {
    final segments = <List<FlSpot>>[];

    var currentSegment = <FlSpot>[];

    for (int i = 0; i < trends.length; i++) {
      final day = trends[i];

      final hasTasks = day.completed + day.pending > 0;

      if (hasTasks) {
        currentSegment.add(FlSpot(i.toDouble(), day.productivityScore));
      } else {
        if (currentSegment.isNotEmpty) {
          segments.add(currentSegment);
          currentSegment = <FlSpot>[];
        }
      }
    }

    if (currentSegment.isNotEmpty) {
      segments.add(currentSegment);
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: trends.isEmpty ? 6 : (trends.length - 1).toDouble(),
        minY: 0,
        maxY: 100,

        gridData: FlGridData(
          show: true,
          horizontalInterval: 20,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white.withOpacity(0.12),
              strokeWidth: 1,
              dashArray: [6, 5],
            );
          },
        ),

        borderData: FlBorderData(show: false),

        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),

          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),

          leftTitles: const AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 20,
            ),
          ),

          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();

                if (index < 0 || index >= trends.length) {
                  return const SizedBox.shrink();
                }

                final day = trends[index];

                final hasTasks = day.completed + day.pending > 0;

                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _shortDayName(day.date),
                    style: TextStyle(
                      color: hasTasks ? Colors.white70 : Colors.white30,
                      fontSize: 11,
                      fontWeight: hasTasks
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        lineBarsData: segments.map((segment) {
          return LineChartBarData(
            spots: segment,
            isCurved: segment.length > 2,
            barWidth: 3,
            color: Colors.cyanAccent,

            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: Colors.cyanAccent,
                  strokeWidth: 2,
                  strokeColor: const Color(0xFF1E293B),
                );
              },
            ),

            belowBarData: BarAreaData(
              show: segment.length > 1,
              gradient: LinearGradient(
                colors: [
                  Colors.cyanAccent.withOpacity(0.25),
                  Colors.cyanAccent.withOpacity(0.02),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          );
        }).toList(),

        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) {
              return spots.map((spot) {
                final dayIndex = spot.x.toInt();

                final dayName = dayIndex >= 0 && dayIndex < trends.length
                    ? _shortDayName(trends[dayIndex].date)
                    : "";

                return LineTooltipItem(
                  "$dayName\n${spot.y.toStringAsFixed(1)}/100",
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  Widget buildModernCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 1800),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slideAnimation = Tween<Offset>(
                    begin: const Offset(0, 0.22),
                    end: Offset.zero,
                  ).animate(animation);

                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: slideAnimation,
                      child: child,
                    ),
                  );
                },
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: Text(
                  value,
                  key: ValueKey<String>("$title-$value"),
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Score breakdown row ─────────────────────────────────────────────────
  Widget _breakdownRow(String label, double pts, double maxPts, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
              Text(
                '${pts.round()}/${maxPts.toInt()} pts',
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 0.0,
              end: (pts / maxPts).clamp(0.0, 1.0),
            ),
            duration: const Duration(milliseconds: 1800),
            curve: Curves.easeInOutCubic,
            builder: (context, animatedProgress, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: animatedProgress,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedScoreRing({
    required double score,
    required bool showScore,
  }) {
    final targetScore = showScore ? score.clamp(0.0, 100.0).toDouble() : 0.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: targetScore),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeInOutCubic,
      builder: (context, animatedScore, child) {
        return SizedBox(
          width: 124,
          height: 124,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 124,
                height: 124,
                child: CircularProgressIndicator(
                  value: animatedScore / 100,
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withOpacity(0.18),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    showScore ? animatedScore.round().toString() : "—",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "/100",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Productivity Dashboard"),
        actions: [
          IconButton(
            tooltip: "Daily AI Reflection",
            icon: const Icon(Icons.auto_awesome_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DailyReflectionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _dashboardStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: Colors.redAccent,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Could not load productivity data",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Check your connection and try again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const SizedBox.shrink();
          }

          final data = snapshot.data!;

          final ProductivityAnalytics stats =
              data["today"] as ProductivityAnalytics;

          final List<DailyProductivityTrend> trends =
              data["trends"] as List<DailyProductivityTrend>;

          final double sevenDayAverage = data["sevenDayAverage"] as double;

          final DailyProductivityTrend? bestDay =
              data["bestDay"] as DailyProductivityTrend?;
          final double score = stats.productivityScore;
          final double completionPts = stats.completionPoints;
          final double priorityPts = stats.priorityPoints;
          final double behaviourPts = stats.behaviourPoints;

          final bool hasActivity = stats.totalRelevantTasks > 0;
          final bool hasActionableTasks = stats.actionableTasks > 0;
          final int actionablePending = stats.actionablePending;
          final int upcoming = stats.upcoming;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Compact Productivity Score Card ───────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6D3FE8), Color(0xFF168BD5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF168BD5).withOpacity(0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              "Today's Productivity",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.22),
                              ),
                            ),
                            child: const Text(
                              "PROVISIONAL",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildAnimatedScoreRing(
                            score: score,
                            showScore: hasActivity && hasActionableTasks,
                          ),

                          const SizedBox(width: 20),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  !hasActivity
                                      ? "No activity yet"
                                      : !hasActionableTasks
                                      ? "Tasks have not started"
                                      : score >= 80
                                      ? "Excellent consistency"
                                      : score >= 50
                                      ? "Good progress"
                                      : "Still developing",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),

                                const SizedBox(height: 7),

                                Text(
                                  !hasActivity
                                      ? "Add or begin a task to generate today's score."
                                      : !hasActionableTasks
                                      ? "Your scheduled tasks will become actionable later."
                                      : "Based on ${stats.actionableTasks} evaluated "
                                            "${stats.actionableTasks == 1 ? "task" : "tasks"} so far.",
                                  style: const TextStyle(
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

                      if (hasActivity && hasActionableTasks) ...[
                        const SizedBox(height: 22),

                        Container(
                          width: double.infinity,
                          height: 1,
                          color: Colors.white.withOpacity(0.15),
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          "How your score was calculated",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 8),

                        _breakdownRow(
                          "Completion Rate (40%)",
                          completionPts,
                          40,
                          Colors.greenAccent,
                        ),

                        _breakdownRow(
                          "Priority Adherence (35%)",
                          priorityPts,
                          35,
                          Colors.purpleAccent,
                        ),

                        _breakdownRow(
                          "Plan Consistency (25%)",
                          behaviourPts,
                          25,
                          Colors.orangeAccent,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ── Section Title ──────────────────────────────────────────
                const Text(
                  "Today's Insights",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 18),

                // ── Stats Grid ─────────────────────────────────────────────
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0,
                  children: [
                    buildModernCard(
                      title: "Completion Rate",
                      value:
                          "${(stats.completionRate * 100).toStringAsFixed(0)}%",
                      icon: Icons.check_circle_outline,
                      color: Colors.greenAccent,
                    ),
                    buildModernCard(
                      title: "Completed",
                      value: stats.completed.toString(),
                      icon: Icons.task_alt,
                      color: Colors.blueAccent,
                    ),
                    buildModernCard(
                      title: "Actionable Now",
                      value: actionablePending.toString(),
                      icon: Icons.play_circle_outline,
                      color: Colors.orangeAccent,
                    ),
                    buildModernCard(
                      title: "Upcoming",
                      value: upcoming.toString(),
                      icon: Icons.upcoming_outlined,
                      color: Colors.cyanAccent,
                    ),
                    buildModernCard(
                      title: "Snoozes",
                      value: stats.snoozes.toString(),
                      icon: Icons.snooze,
                      color: Colors.purpleAccent,
                    ),
                    buildModernCard(
                      title: "Postpones",
                      value: stats.postpones.toString(),
                      icon: Icons.event_repeat,
                      color: Colors.redAccent,
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                const Text(
                  "Recent Productivity Overview",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(
                      child: buildModernCard(
                        title: "Previous Active-Day Average",
                        value: "${sevenDayAverage.toStringAsFixed(1)}/100",
                        icon: Icons.insights_rounded,
                        color: Colors.cyanAccent,
                      ),
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: buildModernCard(
                        title: "Best Day",
                        value: bestDay == null
                            ? "—"
                            : _shortDayName(bestDay.date),
                        icon: Icons.emoji_events_outlined,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Productivity Trend",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 6),

                      const Text(
                        "Previous daily scores with today's provisional score",
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 220,
                        child: _buildProductivityChart(trends),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Reflection Button ──────────────────────────────────────
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DailyReflectionScreen(),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Colors.amber,
                            ),
                          ),

                          const SizedBox(width: 16),

                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "AI Daily Reflection",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "View personalized productivity insights and behavioral analysis.",
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),

                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white54,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
