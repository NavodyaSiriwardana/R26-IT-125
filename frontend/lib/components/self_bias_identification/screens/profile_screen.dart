import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/temporal_causal_patterns/screens/login_screen.dart' as team_login;
import 'package:frontend/components/temporal_causal_patterns/services/auth_service.dart';
import 'package:frontend/components/self_bias_identification/screens/weekly_trends_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_details_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/recommendations_screen.dart';
import 'package:frontend/components/self_bias_identification/services/calendar_settings_service.dart';
import 'package:frontend/components/self_bias_identification/screens/consent_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/consent_service.dart';
import 'package:frontend/components/self_bias_identification/services/study_service.dart';
import 'package:frontend/components/self_bias_identification/services/data_refresh.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_history_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/facial_history_screen.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/services/profile_name_service.dart';
import 'package:frontend/components/self_bias_identification/services/profile_photo_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/profile_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _calendarVerificationEnabled = false;
  bool _studyMode = false;
  bool _hasConsent = false;
  int? _entries;
  int? _avgPas;
  int? _scans;

  @override
  void initState() {
    super.initState();
    _loadCalendarSetting();
    _loadResearchState();
    ProfilePhotoService.load();
    ProfileNameService.load();
    _loadStats();
  }

  /// The three numbers under the photo. They are a bonus, so a failed load
  /// just leaves dashes.
  Future<void> _loadStats() async {
    try {
      final rows = (await ApiService.fetchHistory(AppState.userId))
          .map(HistoryEntry.fromJson)
          .toList();
      var faceOnly = 0;
      try {
        faceOnly = (await ApiService.fetchFaceChecks(AppState.userId)).length;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _entries = rows.length;
        _avgPas = rows.isEmpty ? null : averagePas(rows).round();
        _scans = rows.where((e) => e.hasFace).length + faceOnly;
      });
    } catch (_) {
      // Leave the dashes.
    }
  }

  /// Changes the name shown on the dashboard and profile. It is saved to the
  /// student's account in Firestore as well as on this phone.
  Future<void> _editName() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _NameDialog(),
    );
    if (saved == true && mounted) AppToast.success(context, 'Name updated.');
  }

  Future<void> _changePhoto() async {
    final hasPhoto = ProfilePhotoService.photo.value != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111A27),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Profile photo',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Your photo stays on this phone. It is never sent to the server.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 14),
              if (ProfilePhotoService.canUseCamera)
                _photoOption(sheet, 'camera', Icons.photo_camera_rounded,
                    'Take a photo', const Color(0xFF35E47B)),
              _photoOption(sheet, 'gallery', Icons.photo_library_rounded,
                  'Choose from gallery', const Color(0xFF55CFE0)),
              if (hasPhoto)
                _photoOption(sheet, 'remove', Icons.delete_outline_rounded,
                    'Remove photo', const Color(0xFFFF6977)),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'remove') {
        await ProfilePhotoService.remove();
        if (mounted) AppToast.info(context, 'Photo removed.');
        return;
      }
      final saved = await ProfilePhotoService.choose(
        choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
      if (saved && mounted) AppToast.success(context, 'Profile photo updated.');
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Could not use that photo. Please try another.');
      }
    }
  }

  Widget _photoOption(
    BuildContext sheet,
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF0D131D),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.pop(sheet, value),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: value == 'remove' ? color : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return Column(
      children: [
        const SizedBox(height: 6),
        GestureDetector(
          key: const Key('change-photo'),
          onTap: _changePhoto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const ProfileAvatar(size: 104, borderWidth: 2),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF35E47B),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0A0E14), width: 3),
                  ),
                  child: const Icon(Icons.photo_camera_rounded,
                      size: 16, color: Color(0xFF04231A)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ValueListenableBuilder<String>(
          valueListenable: ProfileNameService.name,
          builder: (context, value, child) => InkWell(
            key: const Key('edit-name'),
            borderRadius: BorderRadius.circular(10),
            onTap: _editName,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      ProfileNameService.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_rounded,
                      size: 17, color: Colors.white.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'SLIIT Student • FYP Research',
          style: TextStyle(fontSize: 15, color: Colors.white60),
        ),
      ],
    );
  }

  Widget _statsRow() {
    Widget stat(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D131D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Text(value,
                    style: GoogleFonts.outfit(fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
              ],
            ),
          ),
        );
    return Row(
      children: [
        stat('${_entries ?? '-'}', 'Entries'),
        const SizedBox(width: 10),
        stat('${_avgPas ?? '-'}', 'Avg PAS'),
        const SizedBox(width: 10),
        stat('${_scans ?? '-'}', 'Scans'),
      ],
    );
  }

  Future<void> _loadResearchState() async {
    final study = await StudyService.isStudyMode();
    final consent = await ConsentService.hasConsent();
    if (mounted) {
      setState(() {
        _studyMode = study;
        _hasConsent = consent;
      });
    }
  }

  Future<void> _onStudyToggle(bool value) async {
    if (value && !_hasConsent) {
      // Study participation needs informed consent first.
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const ConsentScreen(studyPreselected: true),
        ),
      );
      await _loadResearchState();
      return;
    }
    setState(() => _studyMode = value);
    await StudyService.setStudyMode(value);
    if (!mounted) return;
    if (value) {
      AppToast.info(context, 'Study mode on. Some resets will be quiet rest.');
    } else {
      AppToast.info(context, 'Study mode off.');
    }
  }

  Future<void> _confirmDeleteData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete my data?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This permanently deletes your analysis results, diary copies, sensor '
          'summaries, Mood Reset results, saved places and consent record stored '
          'by TruthLens, and the profile photo on this phone. Entries in the '
          'shared team diary are not deleted. '
          'This cannot be undone.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await ApiService.deleteMyData(AppState.userId);
      await ConsentService.clearLocal();
      await StudyService.clearLocal();
      await ProfilePhotoService.remove();
      DataRefresh.notify();
      if (!mounted) return;
      final total = (result['deleted'] as Map? ?? {})
          .values
          .fold<int>(0, (a, b) => a + (b as num).toInt());
      setState(() {
        _studyMode = false;
        _hasConsent = false;
      });
      AppToast.success(context, 'Deleted $total stored record(s).');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(
        context,
        'Could not delete your data. Check your connection and try again.',
      );
    }
  }

  Future<void> _loadCalendarSetting() async {
    final enabled = await CalendarSettingsService.isEnabled();
    if (mounted) setState(() => _calendarVerificationEnabled = enabled);
  }

  Future<void> _onCalendarToggle(bool value) async {
    setState(() => _calendarVerificationEnabled = value);
    await CalendarSettingsService.setEnabled(value);
    if (value && mounted) {
      AppToast.info(
        context,
        "You'll be asked for calendar access next time you submit a diary entry.",
      );
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
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile',
          style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _hero(),
            const SizedBox(height: 14),
            _statsRow(),
            const SizedBox(height: 24),

            // History
            _modernMenuCard(
              title: "History",
              children: [
                _modernMenuItem(
                  icon: Icons.balance_rounded,
                  title: 'Bias History',
                  subtitle: 'Every analysis you have run',
                  color: const Color(0xFFB2A8FF),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BiasHistoryScreen()),
                  ),
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.face_retouching_natural_rounded,
                  title: 'Facial History',
                  subtitle: 'Scans, stress and Mood Resets',
                  color: const Color(0xFF34F5C5),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FacialHistoryScreen()),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Main Menu
            _modernMenuCard(
              title: "Analysis & Insights",
              children: [
                _modernMenuItem(
                  icon: Icons.lightbulb_outline,
                  title: 'Recommendations',
                  subtitle: 'Personalized improvement plan',
                  color: const Color(0xFFFFB74D),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecommendationsScreen()),
                  ),
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.menu_book_outlined,
                  title: 'Bias Types Explained',
                  subtitle: 'Learn about each bias',
                  color: const Color(0xFF60A5FA),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BiasDetailsScreen()),
                  ),
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.bar_chart_outlined,
                  title: 'Weekly Trends',
                  subtitle: 'Charts & analysis',
                  color: const Color(0xFF4ADE80),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WeeklyTrendsScreen()),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Privacy & Permissions
            _modernMenuCard(
              title: "Privacy & Permissions",
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF60A5FA).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.event_available_outlined,
                            color: Color(0xFF60A5FA), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Calendar verification',
                              style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Optional: checks if a diary entry matches '
                              'a planned calendar event, for a more '
                              'accurate score.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _calendarVerificationEnabled,
                        onChanged: _onCalendarToggle,
                        activeThumbColor: const Color(0xFF7B6EFF),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Research & Privacy
            _modernMenuCard(
              title: "Research & Privacy",
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34F5C5).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.science_outlined,
                            color: Color(0xFF34F5C5), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Research study mode',
                              style: GoogleFonts.outfit(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Include my Mood Reset results in the study. Some '
                              'resets will be a quiet-rest comparison.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _studyMode,
                        onChanged: _onStudyToggle,
                        activeThumbColor: const Color(0xFF7B6EFF),
                      ),
                    ],
                  ),
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.verified_user_outlined,
                  title: 'Camera consent',
                  subtitle: _hasConsent
                      ? 'You agreed (${ConsentService.currentVersion}). Tap to review.'
                      : 'Not given yet. Tap to review and agree.',
                  color: const Color(0xFF60A5FA),
                  onTap: () async {
                    await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => const ConsentScreen()),
                    );
                    await _loadResearchState();
                  },
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete my data',
                  subtitle: 'Includes your profile photo on this phone',
                  color: const Color(0xFFFF6B6B),
                  onTap: _confirmDeleteData,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Info & Logout
            _modernMenuCard(
              title: "More",
              children: [
                _modernMenuItem(
                  icon: Icons.info_outline,
                  title: 'About TruthLens',
                  subtitle: 'SLIIT FYP Research 2026',
                  color: Colors.white70,
                  onTap: () => _showAbout(context),
                ),
                _divider(),
                _modernMenuItem(
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'Sign out of TruthLens',
                  color: const Color(0xFFFF6B6B),
                  onTap: () => _logout(context),
                ),
              ],
            ),

            const SizedBox(height: 32),
            Text(
              'TruthLens v1.0 • Intelligent Diary',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _modernMenuCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0D131D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _modernMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        color: Colors.white.withValues(alpha: 0.06),
        height: 1,
        indent: 70,
      );

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('About TruthLens', style: TextStyle(color: Colors.white)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TruthLens Engine v1.0',
              style: TextStyle(color: Color(0xFF7B6EFF), fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Self-perception bias detection system for university students.\nPowered by XGBoost classifier with 91% accuracy.',
              style: TextStyle(fontSize: 15, height: 1.5, color: Colors.white70),
            ),
            SizedBox(height: 12),
            Text(
              'SLIIT FYP Research 2026\nComponent 1: Intelligent Diary',
              style: TextStyle(fontSize: 14, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF7B6EFF))),
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          ),
          TextButton(
            onPressed: () async {
              // One sign-in for the whole app: sign out of the team's account
              // and return to its login screen.
              final navigator = Navigator.of(context);
              AppState.userId = '';
              // The next student must not see this student's photo.
              ProfilePhotoService.photo.value = null;
              ProfileNameService.name.value = '';
              await AuthService.logout();
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const team_login.LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Logout', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
  }
}

/// The "Your name" box. It owns its text controller, so the controller lives
/// exactly as long as the box does, including while the box fades out.
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: ProfileNameService.name.value);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = ProfileNameService.validate(_controller.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ProfileNameService.save(_controller.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111A27),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Your name', style: TextStyle(color: Colors.white)),
      content: TextField(
        key: const Key('name-field'),
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        maxLength: ProfileNameService.maxLength,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'How should we call you?',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text('Cancel',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
        ),
        TextButton(
          key: const Key('save-name'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save',
              style: const TextStyle(color: Color(0xFF35E47B))),
        ),
      ],
    );
  }
}
