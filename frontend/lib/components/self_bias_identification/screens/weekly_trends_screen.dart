import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/entry_time.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/your_trend_card.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_history_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/facial_history_screen.dart';

class WeeklyTrendsScreen extends StatefulWidget {
  const WeeklyTrendsScreen({super.key});

  @override
  State<WeeklyTrendsScreen> createState() => _WeeklyTrendsScreenState();
}

class _WeeklyTrendsScreenState extends State<WeeklyTrendsScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  double _avgPas = 0;
  int _totalEntries = 0;
  int _biasCount = 0;
  Map<String, int> _biasFrequency = {};
  List<HistoryEntry> _entries = [];
  List<DateTime> _pasDates = [];
  List<Map<String, dynamic>> _moodPatterns = [];
  List<Map<String, dynamic>?> _facialHistory = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiService.baseUrl}/api/bias/history/${AppState.userId}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['history'] as List? ?? [];

        double total = 0;
        int biasCount = 0;
        Map<String, int> freq = {};
        List<DateTime> dates = [];
        List<Map<String, dynamic>?> facialHistory = [];
        Map<String, int> moodMap = {};

        for (var entry in history) {
          final pas = entry['pas_score'] ?? 0;
          total += pas;
          final entryId = entry['entry_id']?.toString() ?? '';
          final ts = entryTimestampMs(entryId);
          dates.add(ts != null
              ? DateTime.fromMillisecondsSinceEpoch(ts)
              : DateTime.now());
          if (pas < 70) biasCount++;

          final comparisonForFacial = entry['comparison'] as Map? ?? {};
          final facial = comparisonForFacial['facial_emotion'];
          facialHistory.add(
            facial is Map ? Map<String, dynamic>.from(facial) : null,
          );

          final bias = entry['primary_bias']?['bias_type'] ?? '';
          if (bias.isNotEmpty) {
            freq[bias] = (freq[bias] ?? 0) + 1;
          }

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
          _biasFrequency = freq;
          _pasDates = dates.take(7).toList().reversed.toList();
          _entries = history
              .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          _facialHistory = facialHistory.take(7).toList().reversed.toList();
          _moodPatterns = moodList.take(4).toList();
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) AppToast.error(context, AppToast.friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const Text(
              'Last 7 entries',
              style: TextStyle(fontSize: 14, color: Colors.white54),
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

                  // The trend, against the student's own usual level.
                  YourTrendCard(entries: _entries),

                  if (_facialHistory.any((f) => f != null)) ...[
                    const SizedBox(height: 24),
                    _facialHistoryCard(),
                  ],

                  const SizedBox(height: 24),

                  if (_biasFrequency.isNotEmpty)
                    _modernCard(
                      title: 'Bias Frequency',
                      subtitle: 'All time',
                      onSeeAll: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BiasHistoryScreen()),
                      ),
                      child: _biasFreqChart(),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
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
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.55),
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
    VoidCallback? onSeeAll,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          if (onSeeAll != null)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onSeeAll,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'See all ›',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFB2A8FF),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          child,
        ],
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
      onSeeAll: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FacialHistoryScreen()),
      ),
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
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.15)),
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
    final emoji = isNegative ? '😔' : '😊';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16, height: 1)),
        const SizedBox(height: 4),
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Text(
          dayLabel,
          style: TextStyle(fontSize: 8, color: Colors.white.withValues(alpha: 0.4)),
        ),
      ],
    );
  }

  Widget _biasFreqChart() {
    final sorted = _biasFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sorted.isNotEmpty ? sorted.first.value.toDouble() : 1;

    return Column(
      children: sorted.take(5).map((entry) {
        final color = entry.key == 'accurate_perception'
            ? const Color(0xFF4ADE80)
            : const Color(0xFFFFB74D);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  _formatShort(entry.key),
                  style: const TextStyle(fontSize: 15, color: Colors.white70),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: entry.value / maxVal,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${entry.value}x',
                style: const TextStyle(fontSize: 15, color: Colors.white54),
              ),
            ],
          ),
        );
      }).toList(),
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
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_right_alt,
                  color: Colors.white38,
                  size: 18,
                ),
              ),
              Text(
                after,
                style: TextStyle(
                  fontSize: 14,
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
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${count}x',
                  style: const TextStyle(fontSize: 14, color: Colors.white60),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatShort(String type) {
    switch (type) {
      case 'productivity_overestimation':
        return 'Productivity';
      case 'focus_mismatch':
        return 'Focus Mismatch';
      case 'context_mismatch':
        return 'Context';
      case 'stress_underestimation':
        return 'Stress';
      case 'accurate_perception':
        return 'Accurate';
      default:
        return type.replaceAll('_', ' ').toUpperCase();
    }
  }
}
