import 'package:flutter/material.dart';

import '../../dashboard/screens/dashboard_screen.dart';
import '../../dashboard/theme/dashboard_colors.dart';
import '../../temporal_causal_patterns/services/local_storage.dart';
import '../models/Compare_summary_response.dart';
import '../models/Diary_entry.dart';
import 'Diary_home_screen.dart';
import 'Summary_result_screen.dart';
import '../services/Rag_summary_service.dart';
import '../widgets/diary_entry_detail_dialog.dart';
import '../../../core/network/dio_client.dart';
import '../../temporal_causal_patterns/screens/new_entry_screen.dart';

class ActivityDashboard extends StatefulWidget {
  const ActivityDashboard({super.key});

  @override
  State<ActivityDashboard> createState() => _ActivityDashboardState();
}

class _ActivityDashboardState extends State<ActivityDashboard> {
  final GlobalKey<DashboardScreenState> _dashboardKey = GlobalKey();

  late final RagSummaryService _summaryService;

  String? _userId;
  bool _loadingUser = true;

  int _selectedIndex = 0;
  int _diaryRevision = 0;
  bool _summaryRequestInFlight = false;

  @override
  void initState() {
    super.initState();

    _summaryService = RagSummaryService(DioClient());

    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final userId = await LocalStorage.getUserId();

      if (!mounted) return;

      setState(() {
        _userId = userId;
        _loadingUser = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingUser = false;
      });

      _showMessage('Unable to load user information.');
    }
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);

    if (index == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dashboardKey.currentState?.refreshDashboard();
      });
    }
  }

  Future<void> _addEntry() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const NewEntryScreen(),
      ),
    );

    if (!mounted) return;

    // Refresh dashboard after returning from NewEntryScreen.
    await _dashboardKey.currentState?.refreshDashboard();

    // Refresh diary tab as well.
    setState(() {
      _diaryRevision++;
    });
  }

  Future<void> _generateSummary() async {
    final userId = _userId;

    if (userId == null) {
      _showMessage('User information is not available.');
      return;
    }

    if (_summaryRequestInFlight) return;

    _summaryRequestInFlight = true;

    _showProgressDialog(
      'Creating your weekly reflection…',
    );

    try {
      final summary = await _summaryService.generateWeeklySummary(
        userId: userId,
      );

      if (!mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();

      final dashboardRefresh =
          _dashboardKey.currentState?.refreshDashboard();

      await _openSummary(summary);

      await dashboardRefresh;
    } catch (e) {
      if (!mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();

      _showMessage(
        'Your weekly reflection could not be created. Try again.',
      );
    } finally {
      _summaryRequestInFlight = false;
    }
  }

  Future<void> _viewLatestSummary() async {
    final userId = _userId;

    if (userId == null) {
      _showMessage('User information is not available.');
      return;
    }

    if (_summaryRequestInFlight) return;

    _summaryRequestInFlight = true;

    _showProgressDialog(
      'Loading the latest saved summary…',
    );

    try {
      final summary = await _summaryService.getLatestWeeklySummary(
        userId: userId,
      );

      if (!mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();

      await _openSummary(summary);
    } catch (e) {
      if (!mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();

      _showMessage(
        'The latest saved summary could not be loaded.',
      );
    } finally {
      _summaryRequestInFlight = false;
    }
  }

  Future<void> _openSummary(
    CompareSummaryResponse summary,
  ) async {
    final userId = _userId;

    if (userId == null) {
      _showMessage('User information is not available.');
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryResultScreen(
          userId: userId,
          weekStart: summary.weekStart,
          weekEnd: summary.weekEnd,
          preloadedSummary: summary,
        ),
      ),
    );
  }

  Future<void> _loadEvidence(
    String evidenceId,
  ) async {
    final userId = _userId;

    if (userId == null) {
      _showMessage('User information is not available.');
      return;
    }

    _showProgressDialog(
      'Opening diary entry…',
    );

    try {
      final entry = await _summaryService.getEvidenceById(
        userId: userId,
        evidenceId: evidenceId,
      );

      if (!mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();

      _showEntry(entry);
    } catch (e) {
      if (!mounted) return;

      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();

      _showMessage(
        'The selected diary entry could not be opened.',
      );
    }
  }

  void _showEntry(DiaryEntry entry) {
    showDialog<void>(
      context: context,
      builder: (_) => DiaryEntryDetailDialog(
        entry: entry,
      ),
    );
  }

  void _showProgressDialog(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: DashboardColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Row(
            children: [
              const CircularProgressIndicator(
                color: DashboardColors.primary,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: DashboardColors.text,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DashboardColors.primaryDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wait until LocalStorage has returned the user ID.
    if (_loadingUser) {
      return const Scaffold(
        backgroundColor: DashboardColors.background,
        body: Center(
          child: CircularProgressIndicator(
            color: DashboardColors.primary,
          ),
        ),
      );
    }

    // User ID could not be loaded.
    if (_userId == null || _userId!.isEmpty) {
      return const Scaffold(
        backgroundColor: DashboardColors.background,
        body: Center(
          child: Text(
            'Unable to load user.',
            style: TextStyle(
              color: DashboardColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    final userId = _userId!;

    return Scaffold(
      backgroundColor: DashboardColors.background,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardScreen(
            key: _dashboardKey,
            userId: userId,
            onViewDiary: () => _selectTab(1),
            onAddEntry: _addEntry,
            onGenerateSummary: _generateSummary,
            onViewLatestSummary: _viewLatestSummary,
            onEntryTap: _showEntry,
            onEvidenceTap: _loadEvidence,
          ),
          DiaryHomeScreen(
            key: ValueKey(_diaryRevision),
            userId: userId,
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _addEntry,
              tooltip: 'Add diary entry',
              backgroundColor: DashboardColors.primary,
              foregroundColor: DashboardColors.background,
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        height: 68,
        backgroundColor: DashboardColors.surface,
        indicatorColor: DashboardColors.primaryDark,
        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons.dashboard_outlined,
              color: DashboardColors.muted,
            ),
            selectedIcon: Icon(
              Icons.dashboard_rounded,
              color: DashboardColors.text,
            ),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.menu_book_outlined,
              color: DashboardColors.muted,
            ),
            selectedIcon: Icon(
              Icons.menu_book_rounded,
              color: DashboardColors.text,
            ),
            label: 'Diary',
          ),
        ],
      ),
    );
  }
}
