import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_support_card.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';
import 'package:frontend/components/self_bias_identification/services/data_refresh.dart';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  bool _hasHistory = false;
  final List<Map<String, dynamic>> _recommendations = [];
  String _todayRec = '';
  Map<String, dynamic>? _latestMoodSupport;
  Map<String, dynamic>? _latestFacial;
  String _latestEntryId = '';
  List<Map<String, dynamic>> _resets = [];
  String _mostCommonBias = '';
  double _avgPas = 0;
  int _avgSocial = 0;
  int _avgSwitches = 0;

  @override
  void initState() {
    super.initState();
    DataRefresh.tick.addListener(_onDataChanged);
    _loadData();
    _loadResets();
  }

  @override
  void dispose() {
    DataRefresh.tick.removeListener(_onDataChanged);
    super.dispose();
  }

  /// A reset or analysis finished while this screen was underneath it.
  void _onDataChanged() {
    if (!mounted) return;
    _loadData();
    _loadResets();
  }

  /// Mood Reset history (before/after stress). Optional: the screen works
  /// without it, so failures are swallowed.
  Future<void> _loadResets() async {
    try {
      final response = await ApiClient.get(
        Uri.parse(
          '${ApiService.baseUrl}/api/bias/mood-resets/${AppState.userId}',
        ),
      );
      if (response.statusCode != 200 || !mounted) return;
      final data = jsonDecode(response.body);
      setState(() {
        _resets = (data['resets'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiService.baseUrl}/api/bias/history/${AppState.userId}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['history'] as List? ?? [];

        if (history.isNotEmpty) {
          // History comes back newest-first from the backend.
          final latest = history.first as Map;
          if (latest['mood_support'] is Map) {
            _latestMoodSupport = Map<String, dynamic>.from(
              latest['mood_support'] as Map,
            );
          }
          final latestFacial = (latest['comparison'] as Map?)?['facial_emotion'];
          _latestFacial = latestFacial is Map
              ? Map<String, dynamic>.from(latestFacial)
              : null;
          _latestEntryId = latest['entry_id']?.toString() ?? '';

          double totalPas = 0;
          int totalSocial = 0;
          int totalSwitches = 0;
          Map<String, int> biasFreq = {};

          for (var e in history) {
            totalPas += (e['pas_score'] as num?)?.toDouble() ?? 0;
            final comp = e['comparison'] as Map? ?? {};
            totalSocial += (comp['social_media_minutes'] as num?)?.toInt() ?? 0;
            totalSwitches += (comp['app_switches'] as num?)?.toInt() ?? 0;

            final bias = e['primary_bias']?['bias_type'] ?? '';
            if (bias.isNotEmpty) biasFreq[bias] = (biasFreq[bias] ?? 0) + 1;
          }

          _avgPas = totalPas / history.length;
          _avgSocial = (totalSocial / history.length).round();
          _avgSwitches = (totalSwitches / history.length).round();

          if (biasFreq.isNotEmpty) {
            _mostCommonBias = biasFreq.entries
                .reduce((a, b) => a.value > b.value ? a : b)
                .key;
          }

          _generateRecommendations();
          _hasHistory = true;
        }
      } else {
        _hasError = true;
      }
    } catch (e) {
      _hasError = true;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _generateRecommendations() {
    _recommendations.clear();

    // Today's Recommendation
    switch (_mostCommonBias) {
      case 'productivity_overestimation':
        _todayRec =
            'Start with one 25-minute Pomodoro session. Set a specific goal before starting.';
        break;
      case 'focus_mismatch':
        _todayRec =
            'Close all non-study apps and enable Do Not Disturb. Focus on one task at a time.';
        break;
      case 'context_mismatch':
        _todayRec = 'Study at the exact location you planned today.';
        break;
      case 'stress_underestimation':
        _todayRec =
            'Take a 10-minute break before studying. Be honest with your energy levels.';
        break;
      default:
        _todayRec =
            'Excellent consistency! Keep maintaining your current study habits.';
    }

    // Dynamic Recommendations
    if (_avgSocial > 30) {
      _recommendations.add({
        'title': 'Reduce Social Media',
        'detail': 'Average ${_avgSocial}min per session. Use app blockers.',
        'priority': 'High',
        'color': const Color(0xFFFF6B6B),
        'icon': Icons.block,
      });
    }

    if (_mostCommonBias == 'context_mismatch' ||
        _mostCommonBias == 'productivity_overestimation') {
      _recommendations.add({
        'title': 'Study in Planned Location',
        'detail': 'Location consistency greatly improves your PAS score.',
        'priority': 'High',
        'color': const Color(0xFFFFB74D),
        'icon': Icons.location_on_outlined,
      });
    }

    if (_avgSwitches > 20) {
      _recommendations.add({
        'title': 'Minimize App Switching',
        'detail':
            'Average $_avgSwitches switches per session. Keep only study apps open.',
        'priority': 'Focus',
        'color': const Color(0xFF7B6EFF),
        'icon': Icons.phonelink_off_outlined,
      });
    }

    // Always show general tips
    _recommendations.add({
      'title': 'Track Learning Outcomes',
      'detail': 'Write down 3 key things you learned after each session.',
      'priority': 'Habit',
      'color': const Color(0xFF4ADE80),
      'icon': Icons.check_circle_outline,
    });
    _recommendations.add({
      'title': 'Use Calendar Planning',
      'detail': 'Schedule study sessions in advance for better commitment.',
      'priority': 'Planning',
      'color': const Color(0xFF60A5FA),
      'icon': Icons.calendar_today_outlined,
    });

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final avgColor = _avgPas >= 70
        ? const Color(0xFF4ADE80)
        : _avgPas >= 50
        ? const Color(0xFFFFB74D)
        : const Color(0xFFFF6B6B);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recommendations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              'Based on your recent entries',
              style: TextStyle(fontSize: 14, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B6EFF)),
            )
          : _hasError
              ? _messageState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Could not load recommendations',
                  detail: 'Check your connection and try again.',
                )
              : !_hasHistory
                  ? _messageState(
                      icon: Icons.insights_outlined,
                      title: 'No entries yet',
                      detail:
                          'Add a diary entry first — recommendations are built from your entry history.',
                    )
                  : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_latestMoodSupport != null) ...[
                    MoodSupportCard(
                      moodSupport: _latestMoodSupport!,
                      facialEmotion: _latestFacial,
                      entryId: _latestEntryId,
                      title: "Today's mood plan",
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_resets.isNotEmpty) ...[
                    _resetsCard(),
                    const SizedBox(height: 20),
                  ],
                  // Today's Focus - More Premium Look
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF7B6EFF).withValues(alpha: 0.2),
                          const Color(0xFF12161F),
                        ],
                        begin: Alignment.topLeft,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF7B6EFF).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: Color(0xFF7B6EFF),
                              size: 24,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              "TODAY'S FOCUS",
                              style: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF7B6EFF),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _todayRec,
                          style: const TextStyle(
                            fontSize: 15.5,
                            height: 1.65,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  _sectionHeader('Recommended Actions'),
                  ..._recommendations.map((rec) => _modernRecCard(rec)),

                  const SizedBox(height: 28),

                  _sectionHeader('Your Current Progress'),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12161F),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      children: [
                        _progressRow(
                          'PAS Score',
                          _avgPas,
                          70,
                          avgColor,
                          '${_avgPas.toStringAsFixed(0)}/70',
                        ),
                        const Divider(height: 32, color: Colors.white12),
                        _progressRow(
                          'Social Media',
                          _avgSocial.toDouble(),
                          30,
                          _avgSocial > 30
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFF4ADE80),
                          '$_avgSocial min avg',
                        ),
                        const Divider(height: 32, color: Colors.white12),
                        _progressRow(
                          'App Switches',
                          _avgSwitches.toDouble(),
                          20,
                          _avgSwitches > 20
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFF4ADE80),
                          '$_avgSwitches avg',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  /// Summary of the user's Mood Resets: how many, how often stress dropped,
  /// and the average change — real before/after numbers from the camera.
  Widget _resetsCard() {
    final compared = _resets.where((r) => r['delta_points'] is num).toList();
    final improved = compared.where((r) => r['outcome'] == 'improved').length;
    final helpedPct = compared.isEmpty
        ? 0
        : (improved / compared.length * 100).round();
    final avgDrop = compared.isEmpty
        ? 0.0
        : compared
                  .map((r) => (r['delta_points'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              compared.length;
    final dropColor = avgDrop >= 0 ? MoodPalette.mint : MoodPalette.coral;
    final dropText = avgDrop >= 0
        ? '${avgDrop.round()} pts'
        : '+${avgDrop.abs().round()} pts';

    final last = _resets.first;
    final lastBefore = (last['before_stress'] as num?)?.toDouble();
    final lastAfter = (last['after_stress'] as num?)?.toDouble();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.air_rounded, color: MoodPalette.mint, size: 22),
              SizedBox(width: 10),
              Text(
                'Your Mood Resets',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _resetStat(
                  '${_resets.length}',
                  'Resets done',
                  MoodPalette.violetSoft,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _resetStat(
                  compared.isEmpty ? '-' : '$helpedPct%',
                  'Stress dropped',
                  MoodPalette.mint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _resetStat(
                  compared.isEmpty ? '-' : dropText,
                  avgDrop >= 0 ? 'Avg lower' : 'Avg higher',
                  dropColor,
                ),
              ),
            ],
          ),
          if (lastBefore != null && lastAfter != null) ...[
            const SizedBox(height: 14),
            Text(
              'Last reset: ${(lastBefore * 100).round()}% → ${(lastAfter * 100).round()}% stress',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resetStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 14),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.55),
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _modernRecCard(Map<String, dynamic> rec) {
    final color = rec['color'] as Color;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF12161F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(rec['icon'] as IconData, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rec['title'],
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  rec['priority'],
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            rec['detail'],
            style: const TextStyle(
              fontSize: 13.8,
              height: 1.6,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressRow(
    String label,
    double value,
    double max,
    Color color,
    String trailing,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 13.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (value / max).clamp(0.0, 1.0),
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}
