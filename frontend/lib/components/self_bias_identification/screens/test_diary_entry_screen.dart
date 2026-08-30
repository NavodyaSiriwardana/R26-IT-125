import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/screens/analyzing_screen.dart';

/// TESTING ONLY. Writes a document into the team's shared `diaryEntries`
/// collection using the group leader's exact schema (camelCase field
/// names, "Xh Ym" duration strings) — lets the analyze-from-diary
/// integration be tested end to end without the leader's separate
/// app/codebase installed anywhere. Not part of the real user flow: a
/// real user fills this data in via the leader's own app.
class TestDiaryEntryScreen extends StatefulWidget {
  const TestDiaryEntryScreen({super.key});

  @override
  State<TestDiaryEntryScreen> createState() => _TestDiaryEntryScreenState();
}

class _TestDiaryEntryScreenState extends State<TestDiaryEntryScreen> {
  final _activityController = TextEditingController();
  final _customLocationController = TextEditingController();
  final _specificPersonController = TextEditingController();
  final _notesController = TextEditingController();

  String _category = 'Self-study';
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 30);
  String _location = 'Library';
  String _productivity = 'Medium';
  String _outcome = 'Completed';
  String _withWhom = 'Alone';
  String _moodBefore = 'Normal';
  String _moodAfter = 'Normal';
  String _health = 'Normal';

  bool _submitting = false;

  static const _categories = [
    'Lecture', 'Self-study', 'Group work', 'Meeting', 'Internship',
  ];
  static const _locations = ['Library', 'Lecture Hall', 'Lab', 'Home', 'Cafe', 'Other'];
  static const _productivityLevels = ['Low', 'Medium', 'High'];
  static const _outcomes = ['Completed', 'Partially Done', 'Not Done', 'Postponed'];
  static const _withWhomOptions = ['Alone', 'Friend', 'Group', 'Lecturer'];
  static const _moods = ['Happy', 'Motivated', 'Normal', 'Stressed', 'Tired', 'Bored'];
  static const _healthOptions = ['Normal', 'Headache', 'Sleepy', 'Anxious', 'Tired'];

  String get _entryDate {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String get _timePeriod {
    final h = _startTime.hour;
    if (h >= 5 && h < 12) return 'Morning';
    if (h >= 12 && h < 17) return 'Afternoon';
    if (h >= 17 && h < 21) return 'Evening';
    return 'Night';
  }

  String get _duration {
    var startMin = _startTime.hour * 60 + _startTime.minute;
    var endMin = _endTime.hour * 60 + _endTime.minute;
    if (endMin <= startMin) endMin += 24 * 60;
    final total = endMin - startMin;
    final h = total ~/ 60;
    final m = total % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() => isStart ? _startTime = picked : _endTime = picked);
    }
  }

  Future<void> _submit() async {
    if (_activityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a task/activity name')),
      );
      return;
    }

    setState(() => _submitting = true);

    final entry = {
      'userId': AppState.userId,
      'activityName': _activityController.text.trim(),
      'activityCategory': _category,
      'entryDate': _entryDate,
      'startTime': _fmt(_startTime),
      'endTime': _fmt(_endTime),
      'timePeriod': _timePeriod,
      'duration': _duration,
      'locationType': _location,
      'customLocation': _location == 'Other' ? _customLocationController.text.trim() : '',
      'withWhom': _withWhom,
      'specificPerson': _withWhom != 'Alone' ? _specificPersonController.text.trim() : '',
      'moodBefore': _moodBefore,
      'moodAfter': _moodAfter,
      'healthStatus': _health,
      'productivityLevel': _productivity,
      'taskOutcome': _outcome,
      'notes': _notesController.text.trim(),
    };

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/bias/test-create-diary-entry'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(entry),
      );

      if (!mounted) return;
      setState(() => _submitting = false);

      if (response.statusCode == 200) {
        _showSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection error: $e')),
      );
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80)),
            SizedBox(width: 10),
            Text('Entry saved', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Written to the shared diaryEntries collection. Continue to run '
          'the facial-check + bias analysis on this entry?',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later', style: TextStyle(color: Colors.white38)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const AnalyzingScreen()),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF35E47B),
              foregroundColor: const Color(0xFF04231A),
            ),
            child: const Text('Analyze now', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _activityController.dispose();
    _customLocationController.dispose();
    _specificPersonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
        title: Text(
          'Test Diary Entry',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB74D).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.3)),
              ),
              child: const Text(
                'TEST ONLY — writes directly into the shared diaryEntries '
                'collection, in the same schema the leader\'s real form '
                'produces. A real user fills this in via that app instead.',
                style: TextStyle(color: Color(0xFFFFB74D), fontSize: 11.5, height: 1.4),
              ),
            ),

            _label('Task / activity'),
            _textField(_activityController, 'What did you do?'),
            const SizedBox(height: 16),

            _label('Activity category'),
            _chipRow(_categories, _category, (v) => setState(() => _category = v)),
            const SizedBox(height: 16),

            _label('Start time — End time'),
            Row(
              children: [
                Expanded(child: _timeBox('START', _startTime, () => _pickTime(true))),
                const SizedBox(width: 10),
                Expanded(child: _timeBox('END', _endTime, () => _pickTime(false))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Duration: $_duration  ·  $_timePeriod  (auto)',
                style: const TextStyle(color: Color(0xFF1DB954), fontSize: 11),
              ),
            ),
            const SizedBox(height: 16),

            _label('Location'),
            _chipRow(_locations, _location, (v) => setState(() => _location = v)),
            if (_location == 'Other') ...[
              const SizedBox(height: 8),
              _textField(_customLocationController, 'Enter location name'),
            ],
            const SizedBox(height: 16),

            _label('Productivity level'),
            _chipRow(_productivityLevels, _productivity, (v) => setState(() => _productivity = v)),
            const SizedBox(height: 16),

            _label('Task outcome'),
            _chipRow(_outcomes, _outcome, (v) => setState(() => _outcome = v)),
            const SizedBox(height: 16),

            _label('With whom'),
            _chipRow(_withWhomOptions, _withWhom, (v) => setState(() => _withWhom = v)),
            if (_withWhom != 'Alone') ...[
              const SizedBox(height: 8),
              _textField(_specificPersonController, 'Name'),
            ],
            const SizedBox(height: 16),

            _label('Mood before'),
            _chipRow(_moods, _moodBefore, (v) => setState(() => _moodBefore = v)),
            const SizedBox(height: 16),

            _label('Mood after'),
            _chipRow(_moods, _moodAfter, (v) => setState(() => _moodAfter = v)),
            const SizedBox(height: 16),

            _label('Health status'),
            _chipRow(_healthOptions, _health, (v) => setState(() => _health = v)),
            const SizedBox(height: 16),

            _label('Notes'),
            _textField(_notesController, 'Anything else worth noting...', maxLines: 3),
            const SizedBox(height: 26),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7B61FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Submit test entry', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text, style: const TextStyle(color: Color(0xFFc0c0d8), fontSize: 13)),
      );

  Widget _textField(TextEditingController c, String hint, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF4a4a6a), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF13132A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2a2a3a)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2a2a3a)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF7B61FF)),
        ),
      ),
    );
  }

  Widget _chipRow(List<String> options, String selected, ValueChanged<String> onSelect) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = opt == selected;
        return GestureDetector(
          onTap: () => onSelect(opt),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0x1A7B61FF) : const Color(0xFF13132A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? const Color(0xFF7B61FF) : const Color(0xFF2a2a3a)),
            ),
            child: Text(
              opt,
              style: TextStyle(
                fontSize: 12.5,
                color: isSelected ? const Color(0xFF7B61FF) : const Color(0xFF9999bb),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _timeBox(String label, TimeOfDay time, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF13132A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2a2a3a)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF5a5a7a), fontSize: 10)),
            const SizedBox(height: 4),
            Text(_fmt(time), style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
