import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';

class WeeklyTrendsScreen extends StatefulWidget {
  const WeeklyTrendsScreen({super.key});

  @override
  State<WeeklyTrendsScreen> createState() => _WeeklyTrendsScreenState();
}

class _WeeklyTrendsScreenState extends State<WeeklyTrendsScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  double _avgPas = 0;
  int _totalEntries = 0;
  int _biasCount = 0;
  List<int> _pasScores = [];
  List<DateTime> _pasDates = [];
  List<Map<String, dynamic>> _moodPatterns = [];
  List<Map<String, dynamic>?> _facialHistory = [];

  // Drives the breathing glow on the trend chart's latest point.
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _loadData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/bias/history/${AppState.userId}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['history'] as List? ?? [];

        double total = 0;
        int biasCount = 0;
        List<int> scores = [];
        List<DateTime> dates = [];
        List<Map<String, dynamic>?> facialHistory = [];
        Map<String, int> moodMap = {};

        for (var entry in history) {
          final pas = entry['pas_score'] ?? 0;
          total += pas;
          scores.add(pas);
          final entryId = entry['entry_id']?.toString() ?? '';
          final ts = int.tryParse(entryId.replaceAll(RegExp(r'\D'), ''));
          dates.add(ts != null
              ? DateTime.fromMillisecondsSinceEpoch(ts)
              : DateTime.now());
          if (pas < 70) biasCount++;

          final comparisonForFacial = entry['comparison'] as Map? ?? {};
          final facial = comparisonForFacial['facial_emotion'];
          facialHistory.add(
            facial is Map ? Map<String, dynamic>.from(facial) : null,
          );

          final comparison = entry['comparison'] as Map? ?? {};
          final before = comparison['mood_before'] ?? '';
          final after = comparison['mood_after'] ?? '';
          if (before.isNotEmpty && after.isNotEmpty) {
            final key = '$before→$after';
            moodMap[key] = (moodMap[key] ?? 0) + 1;
          }
        }

        final moodList =
            moodMap.entries
                .map(
                  (e) => {
                    'before': e.key.split('→')[0],
                    'after': e.key.split('→')[1],
                    'count': e.value,
                  },
                )
                .toList()
              ..sort(
                (a, b) => (b['count'] as int).compareTo(a['count'] as int),
              );

        setState(() {
          _history = history.map((e) => e as Map<String, dynamic>).toList();
          _totalEntries = history.length;
          _avgPas = history.isNotEmpty ? total / history.length : 0;
          _biasCount = biasCount;
          _pasScores = scores.take(7).toList().reversed.toList();
          _pasDates = dates.take(7).toList().reversed.toList();
          _facialHistory = facialHistory.take(7).toList().reversed.toList();
          _moodPatterns = moodList.take(4).toList();
        });
      }
    } catch (e) {
      print('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly Report',
              style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const Text(
              'Last 7 entries',
              style: TextStyle(fontSize: 13.5, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.6, -1.1),
            radius: 1.3,
            colors: [
              const Color(0xFF7B6EFF).withValues(alpha: 0.16),
              Colors.transparent,
            ],
            stops: const [0.0, 0.58],
          ),
        ),
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B6EFF)),
            )
          : _history.isEmpty
          ? const Center(
              child: Text(
                'No entries yet',
                style: TextStyle(color: Colors.white38, fontSize: 16),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Stats Grid
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.65,
                    children: [
                      _modernStatCard(
                        'Avg PAS',
                        _avgPas.toStringAsFixed(0),
                        const Color(0xFF7B6EFF),
                      ),
                      _modernStatCard(
                        'Total Entries',
                        '$_totalEntries',
                        Colors.white70,
                      ),
                      _modernStatCard(
                        'Bias Detected',
                        '${_biasCount}x',
                        const Color(0xFFFF6B6B),
                      ),
                      _modernStatCard(
                        'Accurate',
                        '${_totalEntries - _biasCount}x',
                        const Color(0xFF4ADE80),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // PAS Trend — stock-app style hero panel
                  _pasHeroPanel(),

                  if (_facialHistory.any((f) => f != null)) ...[
                    const SizedBox(height: 24),
                    _facialHistoryCard(),
                  ],

                  const SizedBox(height: 24),

                  if (_pasScores.isNotEmpty)
                    _modernCard(
                      title: 'Bias Frequency',
                      subtitle: 'Last 7 entries',
                      child: _biasFrequencyStrip(),
                    ),

                  const SizedBox(height: 24),

                  if (_moodPatterns.isNotEmpty)
                    _modernCard(
                      title: 'Mood Shift Patterns',
                      subtitle: 'Before → After',
                      child: _moodChart(),
                    ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _modernStatCard(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A1F2C), const Color(0xFF12161F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.18),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              color: Colors.white.withOpacity(0.55),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modernCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.07),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ==================== STOCK-APP STYLE HERO PANEL ====================
  Widget _pasHeroPanel() {
    final hasScores = _pasScores.isNotEmpty;
    final latest = hasScores ? _pasScores.last : 0;
    final int? delta = _pasScores.length >= 2
        ? _pasScores.last - _pasScores[_pasScores.length - 2]
        : null;
    final deltaColor = delta == null
        ? Colors.white38
        : delta >= 0
        ? const Color(0xFF4ADE80)
        : const Color(0xFFFF6B6B);

    final trendColor = !hasScores
        ? const Color(0xFF7B6EFF)
        : _avgPas >= 70
        ? const Color(0xFF4ADE80)
        : _avgPas >= 50
        ? const Color(0xFFFFB74D)
        : const Color(0xFFFF6B6B);

    return Container(
      padding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.07),
            Colors.white.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Ambient trend-colored glow tucked in the corner — ties the
          // whole card together instead of a flat glass panel.
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [trendColor.withOpacity(0.18), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAS Score Trend',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          if (hasScores) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$latest',
                  style: GoogleFonts.outfit(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                if (delta != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: deltaColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          delta >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 12.5,
                          color: deltaColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${delta.abs()}',
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: deltaColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Text(
              delta == null ? 'Last ${_pasScores.length} entries' : 'vs previous entry',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.45)),
            ),
            const SizedBox(height: 18),
          ],
          _pasLineChart(),
          if (hasScores) ...[
            const SizedBox(height: 8),
            Divider(color: Colors.white.withOpacity(0.08), height: 25),
            Row(
              children: [
                Expanded(
                  child: _heroStat(
                    'BEST',
                    '${_pasScores.reduce((a, b) => a > b ? a : b)}',
                    const Color(0xFF4ADE80),
                  ),
                ),
                Expanded(
                  child: _heroStat(
                    'AVG',
                    '${(_pasScores.reduce((a, b) => a + b) / _pasScores.length).round()}',
                    Colors.white70,
                  ),
                ),
                Expanded(
                  child: _heroStat(
                    'WORST',
                    '${_pasScores.reduce((a, b) => a < b ? a : b)}',
                    const Color(0xFFFF6B6B),
                  ),
                ),
              ],
            ),
          ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _pasLineChart() {
    if (_pasScores.isEmpty) return const SizedBox(height: 180);
    return SizedBox(
      height: 190,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return CustomPaint(
            painter: _LineChartPainter(
              _pasScores,
              _pasDates,
              pulse: _pulseController.value,
            ),
            size: const Size(double.infinity, 190),
          );
        },
      ),
    );
  }

  // ==================== FACIAL CHECK HISTORY ====================
  // A weekly strip of the real facial-capture result per entry — same
  // emoji + stress-color language as the Facial Check card on Bias
  // Result, so it reads as the same feature over time, not a new one.
  Widget _facialHistoryCard() {
    return _modernCard(
      title: 'Facial Check History',
      subtitle: 'Last ${_facialHistory.length} entries',
      child: Container(
        padding: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_facialHistory.length, (i) {
            final facial = _facialHistory[i];
            final date = i < _pasDates.length ? _pasDates[i] : null;
            return _facialDayChip(facial, date);
          }),
        ),
      ),
    );
  }

  Widget _facialDayChip(Map<String, dynamic>? facial, DateTime? date) {
    const weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final dayLabel = date != null ? weekdayLetters[date.weekday - 1] : '—';

    final captured = facial != null && facial['status'] == 'success';
    if (!captured) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '·',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.15)),
          ),
          const SizedBox(height: 4),
          const SizedBox(width: 4, height: 4),
          const SizedBox(height: 4),
          Text(
            dayLabel,
            style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.25)),
          ),
        ],
      );
    }

    final dominant = (facial['dominant_emotion'] ?? '').toString().toLowerCase();
    const negativeEmotions = ['sad', 'angry', 'fear', 'disgust'];
    final isNegative = negativeEmotions.contains(dominant);
    final color = isNegative ? const Color(0xFFFF6B6B) : const Color(0xFF4ADE80);
    final emoji = isNegative ? '😢' : '😊';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 30,
          height: 34,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28, height: 1)),
              if (isNegative) const _FallingTear(),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 5),
        Text(
          dayLabel,
          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4)),
        ),
      ],
    );
  }

  // A row of colored columns, one per recent entry (oldest to newest,
  // left to right) — green for accurate/good, orange for mild bias, red
  // for moderate/severe, dark grey for a day with no entry. Reads at a
  // glance like a usage/battery graph's daily bars, instead of the
  // previous per-bias-type progress-bar list.
  Widget _biasFrequencyStrip() {
    const slots = 7;
    final scores = _pasScores.length > slots
        ? _pasScores.sublist(_pasScores.length - slots)
        : _pasScores;
    final padding = slots - scores.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (int i = 0; i < padding; i++) _freqBar(null),
            for (final score in scores) _freqBar(score),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _freqLegendItem(const Color(0xFF4ADE80), 'Good'),
            _freqLegendItem(const Color(0xFFFFB74D), 'Mild'),
            _freqLegendItem(const Color(0xFFFF6B6B), 'Bias'),
            _freqLegendItem(Colors.white.withValues(alpha: 0.2), 'No entry'),
          ],
        ),
      ],
    );
  }

  Widget _freqLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  Widget _freqBar(int? score) {
    final hasEntry = score != null;
    final color = !hasEntry
        ? Colors.white.withValues(alpha: 0.08)
        : score >= 70
        ? const Color(0xFF4ADE80)
        : score >= 50
        ? const Color(0xFFFFB74D)
        : const Color(0xFFFF6B6B);
    final height = hasEntry ? 24.0 + (score / 100) * 48.0 : 24.0;

    return Container(
      width: 26,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _moodChart() {
    return Column(
      children: _moodPatterns.map((m) {
        final before = m['before'] as String;
        final after = m['after'] as String;
        final count = m['count'] as int;
        final isPositive = [
          'Happy',
          'Motivated',
          'Calm',
          'Normal',
        ].contains(after);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Text(
                before,
                style: const TextStyle(fontSize: 15.5, color: Colors.white70),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_right_alt,
                  color: Colors.white38,
                  size: 20,
                ),
              ),
              Text(
                after,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: isPositive
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFFFF6B6B),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${count}x',
                  style: const TextStyle(fontSize: 13.5, color: Colors.white60),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

}

// ==================== FALLING TEAR (sad/negative facial check days) ====================
// A small drop that repeatedly falls and fades beneath a sad-emotion day's
// emoji — a quiet motion cue instead of a static face, since a whole week
// of unhappy days is exactly the kind of thing this screen should make hit
// harder than a still icon would.
class _FallingTear extends StatefulWidget {
  const _FallingTear();

  @override
  State<_FallingTear> createState() => _FallingTearState();
}

class _FallingTearState extends State<_FallingTear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Positioned(
          top: 20 + t * 12,
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: const Text('💧', style: TextStyle(fontSize: 9, height: 1)),
          ),
        );
      },
    );
  }
}

// ==================== MODERN LINE CHART PAINTER ====================
class _LineChartPainter extends CustomPainter {
  final List<int> scores;
  final List<DateTime> dates;
  final double pulse;
  _LineChartPainter(this.scores, this.dates, {this.pulse = 0});

  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// A dashed straight line — Canvas has no native dash support, so this
  /// walks the segment in fixed-length on/off steps.
  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint,
      {double dashLength = 4, double gapLength = 3}) {
    final total = (to - from).distance;
    if (total == 0) return;
    final direction = (to - from) / total;
    double covered = 0;
    while (covered < total) {
      final segEnd = (covered + dashLength).clamp(0.0, total);
      canvas.drawLine(
        from + direction * covered,
        from + direction * segEnd,
        paint,
      );
      covered += dashLength + gapLength;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.length < 2) return;

    final w = size.width;
    // Reserve space on the right for reference value labels and at the
    // bottom for weekday labels, matching a real stock-chart layout.
    const rightAxisWidth = 30.0;
    const bottomAxisHeight = 20.0;
    final chartW = w - rightAxisWidth;
    final h = size.height - bottomAxisHeight;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    final targetPaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Right-axis reference values (100 / target 70 / 40), like a stock
    // chart's price axis.
    void axisLabel(String text, double y, {Color color = Colors.white38, bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(chartW + 6, y - tp.height / 2));
    }

    // Grid + right-axis labels at 100 / 70 (target) / 40
    canvas.drawLine(Offset(0, 2), Offset(chartW, 2), gridPaint);
    axisLabel('100', 2);

    final targetY = h * (1 - 70 / 100);

    // Target-zone tint — the whole 70+ band gets a faint green wash so it
    // reads instantly as "the good zone" without checking the axis number.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, chartW, targetY),
      Paint()..color = const Color(0xFF4ADE80).withOpacity(0.045),
    );
    _drawDashedLine(
      canvas,
      Offset(0, targetY),
      Offset(chartW, targetY),
      targetPaint,
    );
    final zoneLabelTp = TextPainter(
      text: TextSpan(
        text: 'TARGET ZONE 70+',
        style: TextStyle(
          color: const Color(0xFF4ADE80).withOpacity(0.55),
          fontSize: 8,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    zoneLabelTp.paint(canvas, Offset(4, targetY - zoneLabelTp.height - 4));
    axisLabel('70', targetY, color: const Color(0xFF4ADE80), bold: true);

    final lowY = h * (1 - 40 / 100);
    canvas.drawLine(Offset(0, lowY), Offset(chartW, lowY), gridPaint);
    axisLabel('40', lowY);

    // Points — bar-chart layout (evenly spaced columns, like a battery/
    // usage graph) instead of a continuous curve. x is each bar's center;
    // y is the top of its column, kept as the reference point the
    // "latest" crosshair/glow/tooltip below anchors to.
    final points = <Offset>[];
    for (int i = 0; i < scores.length; i++) {
      final x = i * chartW / (scores.length - 1);
      final y = h * (1 - scores[i] / 100) - 10;
      points.add(Offset(x, y));
    }

    // Dense waveform of thin bars (like a battery/usage-history graph)
    // instead of one wide bar per real entry — interpolated between the
    // real data points so 7 entries still fill the chart the way a real
    // usage graph's many-hours-of-data would.
    final barBaseline = h - 10;
    const barCount = 56;
    const barGap = 2.0;
    final barW = (chartW / barCount) - barGap;
    for (int b = 0; b < barCount; b++) {
      final frac = b / (barCount - 1); // 0..1 across the chart
      final pos = frac * (scores.length - 1); // maps to fractional index
      final i0 = pos.floor().clamp(0, scores.length - 1);
      final i1 = (i0 + 1).clamp(0, scores.length - 1);
      final segT = pos - i0;
      final score = scores[i0] + (scores[i1] - scores[i0]) * segT;

      final x = frac * chartW;
      final barTop = h * (1 - score / 100) - 10;
      final isRecent = frac >= 0.92; // last sliver of the chart, like the
      // reference's highlighted final bars representing "now".
      final barColor = isRecent ? const Color(0xFFFFB74D) : const Color(0xFF2DD9BE);
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTRB(x - barW / 2, barTop, x + barW / 2, barBaseline),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );
      canvas.drawRRect(rect, Paint()..color = barColor.withOpacity(0.85));
    }

    // Only the latest (current) bar carries the glow/crosshair/tooltip,
    // matching how a stock app emphasizes just the current price and
    // keeps history bars understated.
    for (int i = 0; i < points.length; i++) {
      // Matches the bar chart's own two-tone palette (teal base, amber
      // "now" highlight) instead of a third traffic-light color.
      const color = Color(0xFFFFB74D);
      final isLatest = i == points.length - 1;

      if (isLatest) {
        // Dashed crosshair down to the baseline — same idea as a trading
        // app's guide line under the current price.
        _drawDashedLine(
          canvas,
          Offset(points[i].dx, points[i].dy),
          Offset(points[i].dx, h - 10),
          Paint()
            ..color = color.withOpacity(0.25)
            ..strokeWidth = 1,
          dashLength: 2,
          gapLength: 3,
        );

        // Breathing glow ring, driven by the animation controller.
        final pulseRadius = 8 + 5 * pulse;
        final pulseOpacity = 0.28 - 0.20 * pulse;
        canvas.drawCircle(
          points[i],
          pulseRadius,
          Paint()..color = color.withOpacity(pulseOpacity.clamp(0.0, 1.0)),
        );
        canvas.drawCircle(points[i], 5.5, Paint()..color = color);
        canvas.drawCircle(points[i], 2.4, Paint()..color = const Color(0xFF0A0E14));

        // Floating tooltip — exact score + day, anchored above the dot.
        final tooltipText =
            '${scores[i]}  ·  ${_weekdayLabels[dates[i].weekday - 1]}';
        final tooltipTp = TextPainter(
          text: TextSpan(
            text: tooltipText,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final tooltipPadding = 7.0;
        final tooltipW = tooltipTp.width + tooltipPadding * 2;
        final tooltipH = tooltipTp.height + tooltipPadding * 1.2;
        final tooltipLeft = (points[i].dx - tooltipW).clamp(0.0, chartW - tooltipW);
        final tooltipTop = (points[i].dy - tooltipH - 12).clamp(0.0, h);
        final tooltipRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(tooltipLeft, tooltipTop, tooltipW, tooltipH),
          const Radius.circular(8),
        );
        canvas.drawRRect(
          tooltipRect,
          Paint()..color = const Color(0xFF171B23),
        );
        canvas.drawRRect(
          tooltipRect,
          Paint()
            ..color = color.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        tooltipTp.paint(
          canvas,
          Offset(tooltipLeft + tooltipPadding, tooltipTop + tooltipPadding * 0.6),
        );
      }
    }

    // Weekday labels along the bottom, from each entry's real timestamp.
    for (int i = 0; i < points.length && i < dates.length; i++) {
      final label = _weekdayLabels[dates[i].weekday - 1];
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = (points[i].dx - tp.width / 2).clamp(0.0, chartW - tp.width);
      tp.paint(
        canvas,
        Offset(labelX, h + bottomAxisHeight - 16),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
