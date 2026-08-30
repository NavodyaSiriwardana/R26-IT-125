import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';

class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _recommendations = [];
  String _todayRec = '';
  String _mostCommonBias = '';
  double _avgPas = 0;
  int _avgSocial = 0;
  int _avgSwitches = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/bias/history/${AppState.userId}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['history'] as List? ?? [];

        if (history.isNotEmpty) {
          double totalPas = 0;
          int totalSocial = 0;
          int totalSwitches = 0;
          Map<String, int> biasFreq = {};

          for (var e in history) {
            totalPas += e['pas_score'] ?? 0;
            final comp = e['comparison'] as Map? ?? {};
            totalSocial += (comp['social_media_minutes'] ?? 0) as int;
            totalSwitches += (comp['app_switches'] ?? 0) as int;

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
        }
      }
    } catch (e) {
      print('Error: $e');
    } finally {
      setState(() => _isLoading = false);
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
            'Average ${_avgSwitches} switches per session. Keep only study apps open.',
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
              'AI Recommendations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              'Personalized for you',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B6EFF)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Today's Focus - More Premium Look
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF7B6EFF).withOpacity(0.2),
                          const Color(0xFF12161F),
                        ],
                        begin: Alignment.topLeft,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFF7B6EFF).withOpacity(0.4),
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
                                fontSize: 13,
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
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
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

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 14),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Colors.white.withOpacity(0.55),
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
        border: Border.all(color: color.withOpacity(0.25)),
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
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  rec['priority'],
                  style: TextStyle(
                    fontSize: 11,
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
                color: Colors.white.withOpacity(0.75),
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
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}
