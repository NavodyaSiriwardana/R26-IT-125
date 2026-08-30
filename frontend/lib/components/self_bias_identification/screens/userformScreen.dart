import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:frontend/components/self_bias_identification/screens/bias_result_screen.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/sensor_data_service.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class BiasFormScreen extends StatefulWidget {
  final Map<String, dynamic>? facialResult;
  const BiasFormScreen({super.key, this.facialResult});

  @override
  State<BiasFormScreen> createState() => _BiasFormScreenState();
}

class _BiasFormScreenState extends State<BiasFormScreen> {
  bool _isDarkMode = true;
   Map<String, dynamic>? _facialEmotionResult;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _contextTextBeforeListening = '';

  final _activityController = TextEditingController();
  final _contextController = TextEditingController();
  final _otherLocationController = TextEditingController();
  final _withWhomDetailController = TextEditingController();

  String? _selectedCategory;
  String? _selectedLocation;
  String? _selectedProductivity;
  String? _selectedOutcome;
  String? _selectedMoodBefore;
  String? _selectedMoodAfter;
  String? _selectedHealth;
  String _withWhom = 'Alone';
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 30);

  final _categories = [
    'Lecture',
    'Self-study',
    'Group work',
    'Assignment',
    'Meeting',
    'Internship',
    'Play',
    'Trips',
    'Entertainment',
  ];
  final _healthOptions = ['Normal', 'Headache', 'Sleepy', 'Anxious', 'Tired'];

  Color get background =>
      _isDarkMode ? const Color(0xFF070B12) : const Color(0xFFF8FAFC);
  Color get surface => _isDarkMode ? const Color(0xFF12161F) : Colors.white;
  Color get primary => const Color(0xFF6366F1);
  Color get textPrimary => _isDarkMode ? Colors.white : const Color(0xFF1E2937);
  Color get textSecondary =>
      _isDarkMode ? Colors.white70 : const Color(0xFF64748B);
  Color get borderColor => _isDarkMode
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.grey[200]!;

  BoxDecoration _glassCardDecoration({double radius = 14}) {
    if (!_isDarkMode) {
      return BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.015)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  int get _durationMinutes {
    final startMin = _startTime.hour * 60 + _startTime.minute;
    final endMin = _endTime.hour * 60 + _endTime.minute;
    return endMin - startMin > 0 ? endMin - startMin : 0;
  }

  String get _durationText {
    final h = _durationMinutes ~/ 60;
    final m = _durationMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  double get _formProgress {
    int filled = 0;
    if (_activityController.text.isNotEmpty) filled++;
    if (_selectedLocation != null) filled++;
    if (_selectedProductivity != null) filled++;
    if (_selectedMoodAfter != null) filled++;
    if (_selectedOutcome != null) filled++;
    return filled / 5;
  }
  @override
void initState() {
  super.initState();
  _facialEmotionResult = widget.facialResult;
  _initSpeech();
}

void _initSpeech() async {
  _speechEnabled = await _speech.initialize(
    onStatus: (status) {
      if (status == 'notListening' || status == 'done') {
        if (mounted) setState(() => _isListening = false);
      }
    },
    onError: (error) {
      if (mounted) setState(() => _isListening = false);
    },
  );
  if (mounted) setState(() {});
}

Future<void> _toggleListening() async {
  if (_isListening) {
    await _speech.stop();
    setState(() => _isListening = false);
    return;
  }

  if (!_speechEnabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Speech recognition is not available on this device'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  final micStatus = await Permission.microphone.request();
  if (!micStatus.isGranted) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is required for voice input'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return;
  }

  _contextTextBeforeListening = _contextController.text;
  setState(() => _isListening = true);

  await _speech.listen(
    onResult: (result) {
      final spoken = result.recognizedWords;
      final combined = _contextTextBeforeListening.isEmpty
          ? spoken
          : '$_contextTextBeforeListening $spoken';
      _contextController.text = combined;
      _contextController.selection = TextSelection.fromPosition(
        TextPosition(offset: _contextController.text.length),
      );
      setState(() {});
    },
  );
}


  @override
  void dispose() {
    _speech.stop();
    _activityController.dispose();
    _contextController.dispose();
    _otherLocationController.dispose();
    _withWhomDetailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'New Session Entry',
          style: GoogleFonts.outfit(
            color: textPrimary,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
            icon: Icon(
              _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: textPrimary,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: _formProgress,
            backgroundColor: _isDarkMode ? Colors.white12 : Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation(Color(0xFF6366F1)),
            minHeight: 4,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _isDarkMode
              ? const RadialGradient(
                  center: Alignment(-0.6, -1.1),
                  radius: 1.4,
                  colors: [Color(0x2214B8A6), Colors.transparent],
                  stops: [0.0, 0.6],
                )
              : null,
        ),
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(
                        'Section 1 — The Basics',
                        const Color(0xFF14B8A6),
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('Task / Activity', required: true),
                      _textInput(
                        _activityController,
                        'e.g. MTIT Lecture, Thesis Research',
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('Activity Category'),
                      _chipRow(
                        _categories,
                        _selectedCategory,
                        (val) => setState(() => _selectedCategory = val),
                      ),
                      const SizedBox(height: 24),
                      _fieldLabel('Start Time — End Time'),
                      Row(
                        children: [
                          Expanded(child: _timeBox('START', _startTime, true)),
                          const SizedBox(width: 12),
                          Expanded(child: _timeBox('END', _endTime, false)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _durationBadge(),
                      const SizedBox(height: 24),
                      _fieldLabel('Location', required: true),
                      _locationGrid(),
                      if (_selectedLocation == 'Other') ...[
                        const SizedBox(height: 12),
                        _textInput(
                          _otherLocationController,
                          'Type your location...',
                        ),
                      ],
                      const SizedBox(height: 32),
                      _sectionLabel(
                        'Section 2 — Performance',
                        const Color(0xFFF59E0B),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Productivity Level'),
                      _productivityRow(),
                      const SizedBox(height: 20),
                      _fieldLabel('Task Outcome'),
                      _outcomeGrid(),
                      const SizedBox(height: 20),
                      _fieldLabel('With Whom'),
                      _chipRow(
                        ['Alone', 'Friend', 'Group', 'Lecturer'],
                        _withWhom,
                        (val) {
                          setState(() {
                            _withWhom = val!;
                            _withWhomDetailController.clear();
                          });
                        },
                      ),
                      if (_withWhom != 'Alone') ...[
                        const SizedBox(height: 12),
                        _textInput(
                          _withWhomDetailController,
                          _withWhom == 'Friend'
                              ? "Friend's name"
                              : _withWhom == 'Group'
                              ? "Group name"
                              : "Lecturer name",
                        ),
                      ],
                      const SizedBox(height: 32),
                      _sectionLabel(
                        'Section 3 — Well-being',
                        const Color(0xFFEC4899),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Mood Before Activity'),
                      _moodRow('before'),
                      const SizedBox(height: 20),
                      _fieldLabel('Mood After Activity'),
                      _moodRow('after'),
                      const SizedBox(height: 20),
                     _fieldLabel('Current Health Status'),
_chipRow(
  _healthOptions,
  _selectedHealth,
  (val) => setState(() => _selectedHealth = val),
),

if (_facialEmotionResult != null) ...[
  const SizedBox(height: 20),
  Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF14B8A6).withValues(alpha: 0.14),
          const Color(0xFF6366F1).withValues(alpha: 0.08),
        ],
      ),
      border: _isDarkMode
          ? Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.25))
          : null,
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF14B8A6),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.face, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Facial scan captured',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text.rich(
                TextSpan(
                  text: 'Mood detected: ',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                  children: [
                    TextSpan(
                      text: _facialEmotionResult!['dominant_emotion'] ?? '',
                      style: const TextStyle(
                        color: Color(0xFF14B8A6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF14B8A6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${(((_facialEmotionResult!['confidence'] ?? 0) as num) * 100).round()}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  ),
],

const SizedBox(height: 32),
_sectionLabel('Section 4 — Final Details', primary),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _fieldLabel('Additional Context'),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'AI extracts insights',
                              style: TextStyle(
                                color: primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _contextInput(),
                      const SizedBox(height: 24),
                      _autoCaptureCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _isDarkMode
                    ? surface.withValues(alpha: 0.9)
                    : surface,
                border: _isDarkMode
                    ? Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08)))
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isDarkMode ? 0.4 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: GestureDetector(
                onTap: _submitForm,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _isDarkMode
                        ? const LinearGradient(
                            colors: [Color(0xFF14B8A6), Color(0xFF6366F1)],
                          )
                        : null,
                    color: _isDarkMode ? null : primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _isDarkMode
                        ? [
                            BoxShadow(
                              color: primary.withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      'Submit Entry',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _sectionLabel(String text, Color accent) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: _isDarkMode
                ? [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 2)]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          text.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textSecondary,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: textPrimary,
            ),
          ),
          if (required)
            const Text(' *', style: TextStyle(color: Colors.red, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _textInput(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: _isDarkMode ? Colors.white38 : Colors.grey[400],
        ),
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _chipRow(
    List<String> items,
    String? selected,
    Function(String?) onTap,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: items.map((item) {
        final isActive = selected == item;
        return GestureDetector(
          onTap: () => onTap(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? primary.withOpacity(0.12) : surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: isActive ? primary : borderColor),
            ),
            child: Text(
              item,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? primary : textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _timeBox(String label, TimeOfDay time, bool isStart) {
    return GestureDetector(
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: time);
        if (t != null) setState(() => isStart ? _startTime = t : _endTime = t);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: textSecondary)),
            const SizedBox(height: 4),
            Text(
              time.format(context),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _durationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF14B8A6).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Duration: $_durationText (auto)',
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF14B8A6),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _locationGrid() {
    final locations = [
      ['Library', Icons.menu_book],
      ['Lecture Hall', Icons.school],
      ['Lab', Icons.science],
      ['Home', Icons.home],
      ['Canteen', Icons.restaurant],
      ['Other', Icons.add_location],
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3.2,
      ),
      itemCount: locations.length,
      itemBuilder: (_, i) {
        final loc = locations[i][0] as String;
        final icon = locations[i][1] as IconData;
        final isActive = _selectedLocation == loc;

        return GestureDetector(
          onTap: () => setState(() => _selectedLocation = loc),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isActive ? primary.withOpacity(0.12) : surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isActive ? primary : borderColor),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isActive ? primary : textSecondary),
                const SizedBox(width: 10),
                Text(
                  loc,
                  style: TextStyle(
                    fontSize: 14,
                    color: isActive ? primary : textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _productivityRow() {
    final levels = ['Low', 'Medium', 'High'];
    final colors = [Colors.red, Colors.orange, Colors.green];

    return Row(
      children: List.generate(3, (i) {
        final level = levels[i];
        final color = colors[i];
        final isActive = _selectedProductivity == level;

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedProductivity = level),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isActive ? color.withOpacity(0.12) : surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isActive ? color : borderColor),
              ),
              child: Column(
                children: [
                  Icon(Icons.bolt, color: isActive ? color : textSecondary),
                  const SizedBox(height: 4),
                  Text(
                    level,
                    style: TextStyle(
                      fontSize: 13,
                      color: isActive ? color : textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _outcomeGrid() {
    final outcomes = [
      ['Completed', Icons.check_circle_outline, Colors.green],
      ['Partially Done', Icons.pending_outlined, Colors.orange],
      ['Not Done', Icons.cancel_outlined, Colors.red],
      ['Postponed', Icons.update, Colors.blue],
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 3.2,
      ),
      itemCount: outcomes.length,
      itemBuilder: (_, i) {
        final text = outcomes[i][0] as String;
        final icon = outcomes[i][1] as IconData;
        final color = outcomes[i][2] as Color;
        final isActive = _selectedOutcome == text;

        return GestureDetector(
          onTap: () => setState(() => _selectedOutcome = text),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isActive ? color.withOpacity(0.1) : surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isActive ? color : borderColor),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: isActive ? color : textSecondary),
                const SizedBox(width: 8),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive ? color : textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _moodRow(String type) {
    final moods = [
      ['Happy', '😊'],
      ['Motivated', '⚡'],
      ['Normal', '😐'],
      ['Stressed', '😰'],
      ['Tired', '😩'],
      ['Bored', '😑'],
    ];

    final selected = type == 'before'
        ? _selectedMoodBefore
        : _selectedMoodAfter;

    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: moods.map((m) {
        final mood = m[0];
        final emoji = m[1];
        final isActive = selected == mood;

        return GestureDetector(
          onTap: () => setState(() {
            if (type == 'before') {
              _selectedMoodBefore = mood;
            } else {
              _selectedMoodAfter = mood;
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isActive ? primary.withOpacity(0.12) : surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isActive ? primary : borderColor),
            ),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text(
                  mood,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? primary : textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _contextInput() {
    return TextField(
      controller: _contextController,
      maxLines: 5,
      maxLength: 300,
      style: TextStyle(color: textPrimary),
      decoration: InputDecoration(
        hintText: _isListening
            ? 'Listening... speak now'
            : 'What did you actually achieve? Identify any cognitive biases...',
        hintStyle: TextStyle(
          color: _isListening
              ? primary
              : (_isDarkMode ? Colors.white38 : Colors.grey[400]),
        ),
        filled: true,
        fillColor: surface,
        suffixIcon: IconButton(
          onPressed: _toggleListening,
          tooltip: _isListening ? 'Stop recording' : 'Speak to type',
          icon: Icon(
            _isListening ? Icons.mic : Icons.mic_none_rounded,
            color: _isListening ? Colors.red : primary,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _isListening ? primary : borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
      ),
    );
  }

  Widget _autoCaptureCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _glassCardDecoration(radius: 14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF14B8A6)),
                  SizedBox(width: 6),
                  Text('Auto Captured'),
                ],
              ),
              const Text(
                'Live',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '📅 May 9, 2026',
                  style: TextStyle(color: textSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  '⏱ $_durationText',
                  style: TextStyle(color: textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submitForm() async {
    if (_activityController.text.isEmpty || _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Analyzing your entry...'),
        backgroundColor: Color(0xFF534AB7),
        duration: Duration(seconds: 3),
      ),
    );

    final entryId = 'ENT_${DateTime.now().millisecondsSinceEpoch}';
    final location = _selectedLocation == 'Other'
        ? _otherLocationController.text
        : _selectedLocation!;

    final now = DateTime.now();
    final claimedStart = DateTime(
        now.year, now.month, now.day, _startTime.hour, _startTime.minute);
    final claimedEnd = DateTime(
        now.year, now.month, now.day, _endTime.hour, _endTime.minute);

    try {
      final autoSensorData = await SensorDataService.collectAll(
        userId: AppState.userId,
        claimedStart: claimedStart,
        claimedEnd: claimedEnd,
      );
      
      


      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/bias/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'diary_entry': {
            'entry_id': entryId,
            'user_id': AppState.userId,
            'claimed_activity': _activityController.text,
            'activity_category': _selectedCategory ?? '',
            'claimed_start_time': claimedStart.toIso8601String(),
            'claimed_end_time': claimedEnd.toIso8601String(),
            'claimed_duration_minutes': _durationMinutes,
            'claimed_location': location,
            'productivity_level': _selectedProductivity ?? '',
            'completion_status': _selectedOutcome ?? '',
            'with_whom': _withWhom,
            'mood_before': _selectedMoodBefore ?? '',
            'mood_after': _selectedMoodAfter ?? '',
            'health_status': _selectedHealth ?? '',
            'diary_text': _contextController.text,
          },
          'sensor_data': {
            'entry_id': entryId,
            'user_id': AppState.userId,
            'verified_educational_minutes':
                autoSensorData['verified_educational_minutes'],
            'social_media_minutes': autoSensorData['social_media_minutes'],
            'entertainment_minutes': autoSensorData['entertainment_minutes'],
            'distraction_duration': autoSensorData['distraction_duration'],
            'app_switch_count': autoSensorData['app_switch_count'],
            'gps_location': autoSensorData['gps_location'],
            'calendar_match': autoSensorData['calendar_match'],
            'educational_breakdown': autoSensorData['educational_breakdown'],
            'entertainment_breakdown': autoSensorData['entertainment_breakdown'],
            'social_media_breakdown': autoSensorData['social_media_breakdown'],
            'facial_emotion': _facialEmotionResult,
          },
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (mounted) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BiasResultScreen(result: result)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
