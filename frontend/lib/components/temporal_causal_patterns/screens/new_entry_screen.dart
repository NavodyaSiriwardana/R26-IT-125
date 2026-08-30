import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/diary_entry_model.dart';
import '../services/local_storage.dart';
import '../services/diary_service.dart';
import '../services/time_utils.dart';
import '../widgets/section_header.dart';
import '../widgets/category_chips.dart';
import '../widgets/with_whom_chips.dart';
import '../widgets/specific_person_field.dart';
import '../widgets/mood_selector.dart';
import '../widgets/health_status_chips.dart';
import '../widgets/productivity_chips.dart';
import '../widgets/task_outcome_chips.dart';
import 'my_patterns_screen.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import '../../rag_summary/screens/Activity_dashboard_screen.dart';
import 'package:frontend/app_state.dart';
import '../../self_bias_identification/screens/home_screen.dart';

class NewEntryScreen extends StatefulWidget {
  const NewEntryScreen({super.key});

  @override
  State<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends State<NewEntryScreen> {
  final _activityNameController = TextEditingController();
  final _specificPersonController = TextEditingController();
  final _notesController = TextEditingController();
  final _customLocationController = TextEditingController();

  String _activityCategory = '';
  String _entryDate = TimeUtils.todayDate();
  String _startTime = '';
  String _endTime = '';
  String _timePeriod = '';
  String _duration = '';
  String _locationType = '';
  String _withWhom = '';
  String _moodBefore = '';
  String _moodAfter = '';
  String _healthStatus = '';
  String _productivityLevel = '';
  String _taskOutcome = '';

  bool _loading = false;
  String _message = '';
  bool _success = false;

  // ─────────────────────────────────────────
  // TIME PICKER
  // ─────────────────────────────────────────

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF7B61FF),
              surface: Color(0xFF13132A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final timeStr =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _startTime = timeStr;
          _timePeriod = TimeUtils.calculateTimePeriod(timeStr);
        } else {
          _endTime = timeStr;
        }
        if (_startTime.isNotEmpty && _endTime.isNotEmpty) {
          _duration = TimeUtils.calculateDuration(_startTime, _endTime);
        }
      });
    }
  }

  // ─────────────────────────────────────────
  // DATE PICKER
  // ─────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF7B61FF),
              surface: Color(0xFF13132A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _entryDate =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  // ─────────────────────────────────────────
  // SUBMIT
  // ─────────────────────────────────────────

  Future<void> _submit() async {
    if (_activityNameController.text.isEmpty) {
      setState(() {
        _message = 'Please enter task / activity name';
        _success = false;
      });
      return;
    }
    if (_activityCategory.isEmpty) {
      setState(() {
        _message = 'Please select activity category';
        _success = false;
      });
      return;
    }
    if (_startTime.isEmpty) {
      setState(() {
        _message = 'Please select start time';
        _success = false;
      });
      return;
    }
    if (_locationType.isEmpty) {
      setState(() {
        _message = 'Please select location';
        _success = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = '';
    });

    final userId = await LocalStorage.getUserId();

    final entry = DiaryEntryModel(
      userId: userId,
      activityName: _activityNameController.text.trim(),
      activityCategory: _activityCategory,
      entryDate: _entryDate,
      startTime: _startTime,
      endTime: _endTime,
      timePeriod: _timePeriod,
      duration: _duration,
      locationType: _locationType,
      customLocation: _locationType == 'Other'
          ? _customLocationController.text.trim()
          : '',
      withWhom: _withWhom,
      specificPerson: _withWhom != 'Alone'
          ? _specificPersonController.text.trim()
          : '',
      moodBefore: _moodBefore,
      moodAfter: _moodAfter,
      healthStatus: _healthStatus,
      productivityLevel: _productivityLevel,
      taskOutcome: _taskOutcome,
      notes: _notesController.text.trim(),
    );

    final success = await DiaryService.submitEntry(entry);

    setState(() {
      _loading = false;
      _success = success;
      _message = success
          ? 'Entry saved successfully'
          : 'Failed to save entry. Check connection.';
    });

    if (success) {
      _resetForm();
    }
  }

  void _resetForm() {
    _activityNameController.clear();
    _specificPersonController.clear();
    _notesController.clear();
    _customLocationController.clear();
    setState(() {
      _activityCategory = '';
      _entryDate = TimeUtils.todayDate();
      _startTime = '';
      _endTime = '';
      _timePeriod = '';
      _duration = '';
      _locationType = '';
      _withWhom = '';
      _moodBefore = '';
      _moodAfter = '';
      _healthStatus = '';
      _productivityLevel = '';
      _taskOutcome = '';
      _message = '';
    });
  }

  // ─────────────────────────────────────────
  // LOGOUT DIALOG
  // ─────────────────────────────────────────

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF13132A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Log out?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        content: const Text(
          'You will need to sign in again '
          'to access your diary entries.',
          style: TextStyle(
            color: Color(0xFF9999bb),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
            

          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Color(0xFF5a5a7a),
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await AuthService.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text(
              'Log out',
              style: TextStyle(
                color: Color(0xFFE24B4A),
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A16),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'New session entry',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined,
                color: Color(0xFF5a5a7a), size: 20),
            tooltip: 'Log out',
            onPressed: () => _showLogoutDialog(context),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(53),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _NavPill(
                        icon: Icons.dashboard_outlined,
                        label: 'Dashboard',
                        color: const Color(0xFF1DB954),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ActivityDashboard(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _NavPill(
                        icon: Icons.auto_graph,
                        label: 'My Patterns',
                        color: const Color(0xFF7B61FF),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => MyPatternsScreen()),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _NavPill(
                        icon: Icons.visibility_rounded,
                        label: 'Bias Insights',
                        color: const Color(0xFF2DD9BE),
                        onTap: () async {
                          AppState.userId = await LocalStorage.getUserId();
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const HomeScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 0.5,
                color: const Color(0xFF1e1e2e),
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── SECTION 1 ──────────────────────────
            SectionHeader(
              title: 'SECTION 1 — THE BASICS',
              dotColor: const Color(0xFF1DB954),
            ),

            _field(
              label: 'Task / activity',
              required: true,
              child: TextField(
                controller: _activityNameController,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13),
                decoration: _inputDecoration(
                    'What did you do?'),
              ),
            ),

            _field(
              label: 'Activity category',
              child: CategoryChips(
                selected: _activityCategory,
                onSelected: (val) =>
                    setState(() => _activityCategory = val),
              ),
            ),

            _field(
              label: 'Date',
              required: true,
              child: GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF16162E), Color(0xFF0F0F22)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF2a2a3a)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B61FF).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_today_rounded,
                            size: 14, color: Color(0xFF9784FF)),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        TimeUtils.formatDisplayDate(_entryDate),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            _field(
              label: 'Start time — End time',
              required: true,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _pickTime(true),
                          child: _timeBox('START', _startTime),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _pickTime(false),
                          child: _timeBox('END', _endTime),
                        ),
                      ),
                    ],
                  ),
                  if (_timePeriod.isNotEmpty ||
                      _duration.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (_timePeriod.isNotEmpty)
                          Expanded(
                            child: _autoBox(
                                'TIME PERIOD', _timePeriod),
                          ),
                        if (_timePeriod.isNotEmpty &&
                            _duration.isNotEmpty)
                          const SizedBox(width: 10),
                        if (_duration.isNotEmpty)
                          Expanded(
                            child:
                                _autoBox('DURATION', _duration),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            _field(
              label: 'Location',
              required: true,
              child: Column(
                children: [
                  _locationGrid(),
                  if (_locationType == 'Other') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customLocationController,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration(
                          'Enter location name'),
                    ),
                  ],
                ],
              ),
            ),

            // ── SECTION 2 ──────────────────────────
            _divider(),
            SectionHeader(
              title: 'SECTION 2 — PERFORMANCE',
              dotColor: const Color(0xFFF5A623),
            ),

            _field(
              label: 'Productivity level',
              child: ProductivityChips(
                selected: _productivityLevel,
                onSelected: (val) =>
                    setState(() => _productivityLevel = val),
              ),
            ),

            _field(
              label: 'Task outcome',
              child: TaskOutcomeChips(
                selected: _taskOutcome,
                onSelected: (val) =>
                    setState(() => _taskOutcome = val),
              ),
            ),

            _field(
              label: 'With whom',
              child: WithWhomChips(
                selected: _withWhom,
                onSelected: (val) =>
                    setState(() => _withWhom = val),
              ),
            ),

            if (_withWhom.isNotEmpty && _withWhom != 'Alone')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: SpecificPersonField(
                  controller: _specificPersonController,
                  visible: true,
                ),
              ),

            // ── SECTION 3 ──────────────────────────
            _divider(),
            SectionHeader(
              title: 'SECTION 3 — WELL-BEING',
              dotColor: const Color(0xFFE24B4A),
            ),

            _field(
              label: 'Mood before activity',
              child: MoodSelector(
                selected: _moodBefore,
                onSelected: (val) =>
                    setState(() => _moodBefore = val),
              ),
            ),

            _field(
              label: 'Mood after activity',
              child: MoodSelector(
                selected: _moodAfter,
                onSelected: (val) =>
                    setState(() => _moodAfter = val),
              ),
            ),

            _field(
              label: 'Current health status',
              child: HealthStatusChips(
                selected: _healthStatus,
                onSelected: (val) =>
                    setState(() => _healthStatus = val),
              ),
            ),

            // ── SECTION 4 ──────────────────────────
            _divider(),
            SectionHeader(
              title: 'SECTION 4 — FINAL DETAILS',
              dotColor: const Color(0xFF7B61FF),
            ),

            _field(
              label: 'Additional context',
              child: TextField(
                controller: _notesController,
                maxLines: 3,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13),
                decoration: _inputDecoration(
                    'Anything else worth noting...'),
              ),
            ),

            // ── AUTO USER ID ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF13132A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF1e1e2e)),
                ),
                child: FutureBuilder<String>(
                  future: LocalStorage.getUserId(),
                  builder: (context, snapshot) {
                    return Text(
                      'Auto: userId = ${snapshot.data ?? 'loading...'}',
                      style: const TextStyle(
                        color: Color(0xFF4a4a6a),
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── MESSAGE ────────────────────────────
            if (_message.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _message,
                  style: TextStyle(
                    color: _success
                        ? const Color(0xFF1DB954)
                        : const Color(0xFFE24B4A),
                    fontSize: 13,
                  ),
                ),
              ),

            // ── SUBMIT ─────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(27),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7B61FF).withValues(alpha: 0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(27),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(27),
                      onTap: _loading ? null : _submit,
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(27),
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF2DD9BE)
                                  .withValues(alpha: _loading ? 0.6 : 1),
                              const Color(0xFF7B61FF)
                                  .withValues(alpha: _loading ? 0.6 : 1),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Submit entry',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded,
                                        color: Colors.white, size: 18),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // HELPER WIDGETS
  // ─────────────────────────────────────────

  Widget _field({
    required String label,
    required Widget child,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFc0c0d8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (required) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE24B4A).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFFE24B4A).withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    'required',
                    style: TextStyle(
                      color: Color(0xFFFF8A98),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  Widget _timeBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16162E), Color(0xFF0F0F22)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2a2a3a)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5a5a7a),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '--:--' : value,
            style: TextStyle(
              color: value.isEmpty
                  ? const Color(0xFF4a4a6a)
                  : Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1DB95415),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1DB95430)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1DB954).withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label • auto',
            style: const TextStyle(
              color: Color(0xFF1DB954),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1DB954),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationGrid() {
    const locations = [
      {'icon': Icons.menu_book, 'label': 'Library'},
      {'icon': Icons.school, 'label': 'Lecture Hall'},
      {'icon': Icons.science, 'label': 'Lab'},
      {'icon': Icons.home, 'label': 'Home'},
      {'icon': Icons.coffee, 'label': 'Cafe'},
      {'icon': Icons.location_on, 'label': 'Other'},
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 3,
      children: locations.map((loc) {
        final label = loc['label'] as String;
        final icon = loc['icon'] as IconData;
        final isSelected = _locationType == label;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _locationType = label),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF8A73FF), Color(0xFF6E56E8)],
                      )
                    : null,
                color: isSelected ? null : const Color(0xFF13132A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF9784FF)
                      : const Color(0xFF2a2a3a),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF7B61FF).withValues(alpha: 0.32),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(icon,
                      size: 14,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF9999bb)),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF9999bb),
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          color: Color(0xFF4a4a6a), fontSize: 13),
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
    );
  }

  Widget _divider() {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF1e1e2e),
    );
  }
}

class _NavPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NavPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final darkColor = Color.lerp(color, Colors.black, 0.4)!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, darkColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}