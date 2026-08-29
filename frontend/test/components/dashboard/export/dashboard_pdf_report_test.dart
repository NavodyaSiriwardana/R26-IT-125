import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/dashboard/export/dashboard_pdf_report.dart';
import 'package:frontend/components/dashboard/models/dashboard_data.dart';
import 'package:frontend/components/dashboard/screens/dashboard_screen.dart';
import 'package:frontend/components/dashboard/services/dashboard_service.dart';
import 'package:frontend/components/rag_summary/models/Diary_entry.dart';
import 'package:frontend/core/network/dio_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DashboardPdfReport', () {
    test('builds a valid PDF from all dashboard sections', () async {
      final report = DashboardPdfReport();

      final bytes = await report.build(
        _dashboardFixture(),
        exportedAt: DateTime(2026, 8, 25, 9, 30),
      );

      expect(bytes.length, greaterThan(1000));
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    });

    test('creates a stable filename without exposing the user id', () {
      final dashboard = _dashboardFixture();

      final fileStem = DashboardPdfReport().fileStem(dashboard);

      expect(fileStem, 'smart-diary-dashboard-2026-08-24-to-2026-08-30');
      expect(fileStem, isNot(contains(dashboard.userId)));
    });

    testWidgets('download button exports the loaded dashboard', (tester) async {
      final dashboard = _dashboardFixture();
      final pdfReport = _RecordingPdfReport();

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            userId: dashboard.userId,
            service: _FakeDashboardService(dashboard),
            pdfReport: pdfReport,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final downloadButton = find.byTooltip('Download dashboard PDF');
      expect(downloadButton, findsOneWidget);

      await tester.tap(downloadButton);
      await tester.pumpAndSettle();

      expect(pdfReport.downloadedDashboard, same(dashboard));
      expect(
        find.text(
          'Downloaded smart-diary-dashboard-2026-08-24-to-2026-08-30.pdf',
        ),
        findsOneWidget,
      );
    });
  });
}

class _FakeDashboardService extends DashboardService {
  final DashboardData dashboard;

  _FakeDashboardService(this.dashboard) : super(DioClient());

  @override
  Future<DashboardData> getWeeklyDashboard({
    required String userId,
    String? weekStart,
    String? weekEnd,
  }) async {
    return dashboard;
  }
}

class _RecordingPdfReport extends DashboardPdfReport {
  DashboardData? downloadedDashboard;

  @override
  Future<void> download(DashboardData dashboard) async {
    downloadedDashboard = dashboard;
  }
}

DashboardData _dashboardFixture() {
  return DashboardData(
    userId: 'demo-user-001',
    weekStart: '2026-08-24',
    weekEnd: '2026-08-30',
    evidenceEntryCount: 3,
    overview: const DashboardOverview(
      activityCount: 3,
      loggedMinutes: 180,
      completionRate: 66.7,
      moodImprovedRate: 66.7,
    ),
    dailyActivity: const [
      DailyActivityData(
        date: '2026-08-24',
        dayLabel: 'Mon',
        totalMinutes: 120,
        entryCount: 2,
      ),
      DailyActivityData(
        date: '2026-08-25',
        dayLabel: 'Tue',
        totalMinutes: 60,
        entryCount: 1,
      ),
    ],
    categoryBreakdown: const [
      CategoryBreakdownItem(
        category: 'Focused work',
        totalMinutes: 120,
        entryCount: 2,
        percentage: 66.7,
      ),
      CategoryBreakdownItem(
        category: 'Exercise',
        totalMinutes: 60,
        entryCount: 1,
        percentage: 33.3,
      ),
    ],
    productivityBreakdown: const [
      BreakdownItem(label: 'High', count: 2, percentage: 66.7),
      BreakdownItem(label: 'Medium', count: 1, percentage: 33.3),
    ],
    moodBreakdown: const MoodBreakdown(
      improvedCount: 2,
      stableCount: 1,
      declinedCount: 0,
      improvedPercentage: 66.7,
    ),
    outcomeBreakdown: const [
      BreakdownItem(label: 'Completed', count: 2, percentage: 66.7),
      BreakdownItem(label: 'Partially completed', count: 1, percentage: 33.3),
    ],
    insights: const [
      DashboardInsight(
        title: 'Focused mornings were productive',
        message: 'Both morning focus sessions were marked highly productive.',
        evidenceIds: ['EV-001', 'EV-002'],
        sampleSize: 2,
      ),
    ],
    recentEntries: [
      DiaryEntry(
        id: 1,
        userId: 'demo-user-001',
        evidenceId: 'EV-003',
        activityName: 'Evening walk',
        activityCategory: 'Exercise',
        startTime: '18:00',
        endTime: '19:00',
        durationMinutes: 60,
        productivityLevel: 'Medium',
        moodBefore: 'Neutral',
        moodAfter: 'Happy',
        taskOutcome: 'Completed',
        personNames: null,
        healthStatus: 'Good',
        location: 'Park',
        withWhom: 'Alone',
        notes: null,
        entryDate: '2026-08-25',
        weekStart: '2026-08-24',
        weekEnd: '2026-08-30',
        createdAt: '2026-08-25T19:00:00Z',
        updatedAt: '2026-08-25T19:00:00Z',
      ),
    ],
    latestSummary: const DashboardLatestSummary(
      summaryId: 'SUM-001',
      generatedAt: '2026-08-25T20:00:00Z',
      summaryText: 'You completed two of three activities this week.',
      feedbackMessage: 'Protect your productive morning focus block.',
      groundedClaimRate: 0.92,
      unsupportedClaimRate: 0.08,
      citationPrecision: 1,
      citationCompleteness: 0.92,
      retrievalCoverage: 1,
      bertscore: 0.81,
      rougeL: 0.74,
      generationLatencyMs: 1240,
      evaluationStatus: 'success',
    ),
  );
}
