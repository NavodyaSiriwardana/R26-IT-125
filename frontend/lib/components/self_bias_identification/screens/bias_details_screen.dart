import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';

class BiasDetailsScreen extends StatefulWidget {
  const BiasDetailsScreen({super.key});

  @override
  State<BiasDetailsScreen> createState() => _BiasDetailsScreenState();
}

class _BiasDetailsScreenState extends State<BiasDetailsScreen> {
  String? _expandedBias;
  Map<String, int> _userBiasFreq = {};
  bool _isLoading = true;

  final List<Map<String, dynamic>> _biasData = [
    {
      'key': 'productivity_overestimation',
      'title': 'Productivity Overestimation',
      'color': const Color(0xFFFF6B6B),
      'meaning': 'You believe you studied more than you actually did. Your claimed duration is significantly higher than verified educational activity.',
      'why': 'Social media, entertainment and frequent app switching reduced actual study time while you perceived being productive.',
      'example': 'You claimed 2 hours of DBMS study but only 18 minutes were verified. 55 minutes went to social media.',
      'improve': 'Track actual study time using a timer. Block social media during study sessions. Use Pomodoro 25-minute focus blocks.',
      'action': 'Try one 25-minute Pomodoro session today with phone on airplane mode.',
    },
    {
      'key': 'focus_mismatch',
      'title': 'Focus Mismatch',
      'color': const Color(0xFFFFB74D),
      'meaning': 'You were physically present for study but mentally distracted. High app switching indicates fragmented attention.',
      'why': 'Constant notifications and app switching breaks deep focus. Each switch costs 15-20 minutes of recovery time.',
      'example': 'You were at the library for 90 minutes but switched apps 47 times, reducing effective study to under 30 minutes.',
      'improve': 'Enable Do Not Disturb mode during study. Keep only one study app open at a time. Set a goal before each session.',
      'action': 'Next session: close all non-study apps before starting.',
    },
    {
      'key': 'context_mismatch',
      'title': 'Context Mismatch',
      'color': const Color(0xFFFFB74D),
      'meaning': 'You claimed to study in one location but were detected elsewhere. Your study environment did not match your plan.',
      'why': 'Environment changes affect study quality. Home distractions often reduce productivity compared to library settings.',
      'example': 'You planned to study at the library but were detected at home, where distractions were higher.',
      'improve': 'Study where you plan to study. If plans change, update your diary entry. Create a dedicated study space at home.',
      'action': 'Next time you plan Library — actually go to the Library.',
    },
    {
      'key': 'stress_underestimation',
      'title': 'Stress Underestimation',
      'color': const Color(0xFFFFB74D),
      'meaning': 'You reported feeling normal or motivated but behavioral and physiological signals indicate stress or fatigue.',
      'why': 'Students often suppress or ignore stress signals, leading to burnout. Mood deterioration after sessions is a key indicator.',
      'example': 'You reported feeling Normal but your heart rate was 108 bpm and mood shifted to Stressed after studying.',
      'improve': 'Take regular breaks. Practice mindfulness before study sessions. Acknowledge stress rather than suppressing it.',
      'action': 'Take a 10-minute walk before your next study session.',
    },
    {
      'key': 'accurate_perception',
      'title': 'Accurate Perception',
      'color': const Color(0xFF4ADE80),
      'meaning': 'Your self-reported study habits closely match verified behavioral data. You have good self-awareness.',
      'why': 'Consistent study location, minimal distractions and stable mood patterns contribute to accurate self-perception.',
      'example': 'You claimed 90 minutes of study and verified data showed 80 minutes of educational activity. Excellent match!',
      'improve': 'Maintain your current study habits. Share your techniques with peers. Aim for consistent PAS scores above 70.',
      'action': 'Keep up the great work! Try to maintain this consistency.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/bias/history/${AppState.userId}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['history'] as List? ?? [];
        Map<String, int> freq = {};
        for (var e in history) {
          final bias = e['primary_bias']?['bias_type'] ?? '';
          if (bias.isNotEmpty) {
            freq[bias] = (freq[bias] ?? 0) + 1;
          }
        }
        setState(() => _userBiasFreq = freq);
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
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bias Types Explained', style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700)),
            const Text('TruthLens Knowledge Base', style: TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.8, -1.1),
            radius: 1.3,
            colors: [const Color(0xFF7B6EFF).withOpacity(0.16), Colors.transparent],
            stops: const [0.0, 0.58],
          ),
        ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7B6EFF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tap any bias to learn more',
                    style: TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                  const SizedBox(height: 16),
                  ..._biasData.map((bias) => _modernBiasItem(bias)),
                ],
              ),
            ),
      ),
    );
  }

  Widget _modernBiasItem(Map<String, dynamic> bias) {
    final key = bias['key'] as String;
    final color = bias['color'] as Color;
    final isExpanded = _expandedBias == key;
    final userCount = _userBiasFreq[key] ?? 0;

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _expandedBias = isExpanded ? null : key),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isExpanded
                    ? [color.withOpacity(0.10), Colors.white.withOpacity(0.02)]
                    : [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.015)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isExpanded ? color.withOpacity(0.6) : Colors.white.withOpacity(0.08),
                width: isExpanded ? 1.5 : 1,
              ),
              boxShadow: isExpanded
                  ? [BoxShadow(color: color.withOpacity(0.16), blurRadius: 20, offset: const Offset(0, 8))]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bias['title'],
                          style: GoogleFonts.outfit(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: isExpanded ? color : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userCount > 0 ? '$userCount times detected' : 'Not detected yet',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: userCount > 0 ? color.withOpacity(0.85) : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: isExpanded ? color : Colors.white54,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Expanded Section
        if (isExpanded)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.015)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withOpacity(0.4)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              children: [
                _expandSection(Icons.info_outline, 'What it means', bias['meaning'], Colors.white70),
                _divider(),
                _expandSection(Icons.psychology_outlined, 'Why it happens', bias['why'], const Color(0xFFFFB74D)),
                _divider(),
                _expandSection(Icons.article_outlined, 'Example', bias['example'], const Color(0xFFFF6B6B)),
                _divider(),
                _expandSection(Icons.lightbulb_outline, 'How to improve', bias['improve'], const Color(0xFF4ADE80)),
                _divider(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt, color: color, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          bias['action'],
                          style: TextStyle(fontSize: 13.5, color: color, fontWeight: FontWeight.w500, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _expandSection(IconData icon, String label, String content, Color textColor) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: textColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: textColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: const TextStyle(fontSize: 13.5, height: 1.55, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(color: Colors.white.withOpacity(0.06), height: 1, thickness: 1);
}