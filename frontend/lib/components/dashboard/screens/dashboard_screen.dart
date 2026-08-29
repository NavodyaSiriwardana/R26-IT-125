import 'package:flutter/material.dart';

import '../../../core/network/dio_client.dart';
import '../../rag_summary/models/Diary_entry.dart';
import '../export/dashboard_pdf_report.dart';
import '../models/dashboard_data.dart';
import '../services/dashboard_service.dart';
import '../theme/dashboard_colors.dart';
import '../widgets/breakdown_cards.dart';
import '../widgets/daily_activity_chart.dart';
import '../widgets/dashboard_formatters.dart';
import '../widgets/insights_card.dart';
import '../widgets/overview_cards.dart';
import '../widgets/recent_entries_section.dart';
import '../widgets/weekly_summary_panel.dart';

class DashboardScreen extends StatefulWidget {
  final String userId;
  final String? weekStart;
  final String? weekEnd;
  final VoidCallback? onViewDiary;
  final VoidCallback? onAddEntry;
  final VoidCallback? onGenerateSummary;
  final VoidCallback? onViewLatestSummary;
  final ValueChanged<DiaryEntry>? onEntryTap;
  final ValueChanged<String>? onEvidenceTap;
  final DashboardService? service;
  final DashboardPdfReport? pdfReport;

  const DashboardScreen({
    super.key,
    required this.userId,
    this.weekStart,
    this.weekEnd,
    this.onViewDiary,
    this.onAddEntry,
    this.onGenerateSummary,
    this.onViewLatestSummary,
    this.onEntryTap,
    this.onEvidenceTap,
    this.service,
    this.pdfReport,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  late final DashboardService _service;
  late final DashboardPdfReport _pdfReport;

  DashboardData? _dashboard;
  bool _isLoading = true;
  bool _isExporting = false;
  Future<void>? _activeLoad;
  bool _reloadRequested = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DashboardService(DioClient());
    _pdfReport = widget.pdfReport ?? DashboardPdfReport();
    _loadDashboard(showLoader: true);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.userId != widget.userId ||
        oldWidget.weekStart != widget.weekStart ||
        oldWidget.weekEnd != widget.weekEnd) {
      _loadDashboard(showLoader: true);
    }
  }

  Future<void> refreshDashboard() => _loadDashboard(showLoader: false);

  Future<void> _downloadDashboard() async {
    final dashboard = _dashboard;
    if (dashboard == null || dashboard.isEmpty || _isExporting) return;

    setState(() => _isExporting = true);

    try {
      await _pdfReport.download(dashboard);
      if (!mounted) return;

      final fileName = '${_pdfReport.fileStem(dashboard)}.pdf';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded $fileName'),
          backgroundColor: DashboardColors.accent,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the PDF report. Please try again.'),
          backgroundColor: DashboardColors.negative,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _loadDashboard({required bool showLoader}) async {
    _reloadRequested = true;

    final activeLoad = _activeLoad;
    if (activeLoad != null) {
      return activeLoad;
    }

    final load = _drainDashboardLoads(showLoader: showLoader);
    _activeLoad = load;
    return load;
  }

  Future<void> _drainDashboardLoads({required bool showLoader}) async {
    var shouldShowLoader = showLoader;

    try {
      while (_reloadRequested) {
        _reloadRequested = false;
        await _performDashboardLoad(showLoader: shouldShowLoader);
        shouldShowLoader = false;
      }
    } finally {
      _activeLoad = null;
    }
  }

  Future<void> _performDashboardLoad({required bool showLoader}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final dashboard = await _service.getWeeklyDashboard(
        userId: widget.userId,
        weekStart: widget.weekStart,
        weekEnd: widget.weekEnd,
      );

      if (!mounted) return;

      setState(() {
        _dashboard = dashboard;
        _isLoading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;

      if (_dashboard != null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh the dashboard. Please try again.'),
            backgroundColor: DashboardColors.primaryDark,
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Your weekly dashboard could not be loaded right now.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashboardColors.background,
      appBar: AppBar(
        backgroundColor: DashboardColors.background,
        elevation: 0,
        foregroundColor: DashboardColors.text,
        title: const Text(
          'Dashboard',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 13),
              child: Center(
                child: SizedBox(
                  height: 19,
                  width: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: DashboardColors.accentText,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Download dashboard PDF',
              onPressed: _dashboard == null || _dashboard!.isEmpty
                  ? null
                  : _downloadDashboard,
              icon: const Icon(Icons.download_rounded),
            ),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: _isLoading || _isExporting ? null : refreshDashboard,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _dashboard == null) {
      return const _DashboardLoadingState();
    }

    if (_error != null && _dashboard == null) {
      return _DashboardErrorState(
        message: _error!,
        onRetry: () => _loadDashboard(showLoader: true),
      );
    }

    final dashboard = _dashboard!;

    return RefreshIndicator(
      onRefresh: refreshDashboard,
      color: DashboardColors.primary,
      backgroundColor: DashboardColors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
        children: [
          _DashboardHeader(data: dashboard),
          const SizedBox(height: 16),
          if (dashboard.isEmpty)
            _DashboardEmptyState(
              onAddEntry: widget.onAddEntry,
              onViewDiary: widget.onViewDiary,
            )
          else ...[
            OverviewCards(overview: dashboard.overview),
            const SizedBox(height: 16),
            DailyActivityChart(days: dashboard.dailyActivity),
            const SizedBox(height: 16),
            CategoryBreakdownCard(items: dashboard.categoryBreakdown),
            const SizedBox(height: 16),
            ProductivityBreakdownCard(items: dashboard.productivityBreakdown),
            const SizedBox(height: 16),
            MoodJourneyCard(mood: dashboard.moodBreakdown),
            const SizedBox(height: 16),
            OutcomeBreakdownCard(items: dashboard.outcomeBreakdown),
            const SizedBox(height: 16),
            InsightsCard(
              insights: dashboard.insights,
              onEvidenceTap: widget.onEvidenceTap,
            ),
            const SizedBox(height: 16),
            WeeklySummaryPanel(
              latestSummary: dashboard.latestSummary,
              evidenceEntryCount: dashboard.evidenceEntryCount,
              onGenerateSummary: widget.onGenerateSummary,
              onViewLatest: dashboard.latestSummary == null
                  ? null
                  : widget.onViewLatestSummary,
            ),
            const SizedBox(height: 16),
            RecentEntriesSection(
              entries: dashboard.recentEntries,
              onViewAll: widget.onViewDiary,
              onEntryTap: widget.onEntryTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final DashboardData data;

  const _DashboardHeader({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [DashboardColors.primaryDark, DashboardColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DashboardColors.primary),
        boxShadow: [
          BoxShadow(
            color: DashboardColors.primary.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR WEEK AT A GLANCE',
                  style: TextStyle(
                    color: DashboardColors.muted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'See what shaped your week',
                  style: TextStyle(
                    color: DashboardColors.text,
                    fontSize: 21,
                    height: 1.16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  formatWeekRange(data.weekStart, data.weekEnd),
                  style: const TextStyle(
                    color: DashboardColors.accentText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 66,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: DashboardColors.background.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: DashboardColors.border),
            ),
            child: Column(
              children: [
                Text(
                  data.evidenceEntryCount.toString(),
                  style: const TextStyle(
                    color: DashboardColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'DIARY\nENTRIES',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DashboardColors.muted,
                    fontSize: 7,
                    height: 1.3,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingState extends StatelessWidget {
  const _DashboardLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: DashboardColors.primary),
          SizedBox(height: 16),
          Text(
            'Building your weekly view…',
            style: TextStyle(
              color: DashboardColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DashboardErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(22),
      children: [
        const SizedBox(height: 70),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: DashboardColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: DashboardColors.border),
          ),
          child: Column(
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: DashboardColors.primaryDark,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  color: DashboardColors.text,
                  size: 29,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Could not load the dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DashboardColors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DashboardColors.muted,
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DashboardColors.primary,
                  foregroundColor: DashboardColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 13,
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  final VoidCallback? onAddEntry;
  final VoidCallback? onViewDiary;

  const _DashboardEmptyState({
    required this.onAddEntry,
    required this.onViewDiary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: DashboardColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: DashboardColors.border),
      ),
      child: Column(
        children: [
          Container(
            height: 62,
            width: 62,
            decoration: BoxDecoration(
              color: DashboardColors.primaryDark,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: DashboardColors.primary),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: DashboardColors.text,
              size: 31,
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            'Your week is ready to begin',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DashboardColors.text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Add a diary entry to see how your time, productivity, mood, and '
            'outcomes changed throughout the week.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DashboardColors.muted,
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onAddEntry != null || onViewDiary != null) ...[
            const SizedBox(height: 19),
            Row(
              children: [
                if (onViewDiary != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onViewDiary,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DashboardColors.text,
                        side: const BorderSide(color: DashboardColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Open diary',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  if (onAddEntry != null) const SizedBox(width: 10),
                ],
                if (onAddEntry != null)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onAddEntry,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add entry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DashboardColors.accent,
                        foregroundColor: DashboardColors.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
