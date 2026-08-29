import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/dashboard_data.dart';
import '../widgets/dashboard_formatters.dart';

class DashboardPdfReport {
  static final PdfColor _ink = PdfColor.fromInt(0xFF181728);
  static final PdfColor _muted = PdfColor.fromInt(0xFF686579);
  static final PdfColor _primary = PdfColor.fromInt(0xFF655BC4);
  static final PdfColor _primarySoft = PdfColor.fromInt(0xFFF0EEFF);
  static final PdfColor _accent = PdfColor.fromInt(0xFF14805F);
  static final PdfColor _accentSoft = PdfColor.fromInt(0xFFE8F7F1);
  static final PdfColor _border = PdfColor.fromInt(0xFFD9D6E8);
  static final PdfColor _paperTint = PdfColor.fromInt(0xFFF8F7FC);

  Future<Uint8List> build(
    DashboardData dashboard, {
    DateTime? exportedAt,
  }) async {
    final generatedAt = exportedAt ?? DateTime.now();
    final document = pw.Document(
      title: 'Smart Diary weekly dashboard report',
      author: 'Smart Diary',
      subject: _weekRange(dashboard.weekStart, dashboard.weekEnd),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
      ),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 34, 36, 34),
        header: (context) =>
            context.pageNumber == 1 ? pw.SizedBox() : _pageHeader(dashboard),
        footer: _pageFooter,
        build: (context) => [
          _reportHeader(dashboard, generatedAt),
          ..._overviewSection(dashboard),
          ..._dailyActivitySection(dashboard),
          ..._categorySection(dashboard),
          ..._productivitySection(dashboard),
          ..._moodSection(dashboard),
          ..._outcomeSection(dashboard),
          ..._insightsSection(dashboard),
          ..._summarySection(dashboard),
          ..._recentEntriesSection(dashboard),
          pw.SizedBox(height: 10),
          pw.Divider(color: _border),
          pw.Text(
            'Methodology: completion counts fully completed activities. Mood '
            'movement compares the before and after values recorded with each '
            'activity. Percentages may not total exactly 100% after rounding.',
            style: pw.TextStyle(fontSize: 7.5, color: _muted, height: 1.35),
          ),
        ],
      ),
    );

    return document.save();
  }

  Future<void> download(DashboardData dashboard) async {
    final bytes = await build(dashboard);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${fileStem(dashboard)}.pdf',
    );
  }

  String fileStem(DashboardData dashboard) {
    final start = _safeFilePart(dashboard.weekStart, fallback: 'week-start');
    final end = _safeFilePart(dashboard.weekEnd, fallback: 'week-end');
    return 'smart-diary-dashboard-$start-to-$end';
  }

  pw.Widget _reportHeader(DashboardData dashboard, DateTime exportedAt) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: _ink,
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SMART DIARY',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Weekly dashboard report',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 23,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 7),
                pw.Text(
                  _weekRange(dashboard.weekStart, dashboard.weekEnd),
                  style: pw.TextStyle(
                    color: PdfColor.fromInt(0xFFD6D2FF),
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Exported ${_dateTime(exportedAt)}',
                  style: pw.TextStyle(color: PdfColors.grey400, fontSize: 8),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Container(
            width: 86,
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 13,
            ),
            decoration: pw.BoxDecoration(
              color: _primary,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  dashboard.evidenceEntryCount.toString(),
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'EVIDENCE ENTRIES',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _overviewSection(DashboardData dashboard) {
    final overview = dashboard.overview;
    return [
      _sectionHeading(1, 'Overview', 'The main signals from the selected week'),
      pw.Row(
        children: [
          pw.Expanded(
            child: _metricCard(
              'Activities',
              overview.activityCount.toString(),
              'recorded this week',
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _metricCard(
              'Logged time',
              formatLoggedTime(overview.loggedMinutes),
              'across all activities',
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _metricCard(
              'Completed',
              formatPercentage(overview.completionRate),
              'of recorded activities',
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _metricCard(
              'Mood improved',
              formatPercentage(overview.moodImprovedRate),
              'after activities',
            ),
          ),
        ],
      ),
    ];
  }

  List<pw.Widget> _dailyActivitySection(DashboardData dashboard) {
    return [
      _sectionHeading(
        2,
        'Daily activity',
        'Logged time and evidence entries by day',
      ),
      _table(
        headers: const ['Day', 'Date', 'Logged time', 'Entries'],
        rows: dashboard.dailyActivity
            .map(
              (day) => [
                day.dayLabel,
                _dateOnly(day.date),
                formatLoggedTime(day.totalMinutes),
                day.entryCount.toString(),
              ],
            )
            .toList(),
        emptyMessage: 'No daily activity was recorded for this week.',
        columnWidths: const {
          0: pw.FlexColumnWidth(1.2),
          1: pw.FlexColumnWidth(1.7),
          2: pw.FlexColumnWidth(1.3),
          3: pw.FlexColumnWidth(1),
        },
      ),
    ];
  }

  List<pw.Widget> _categorySection(DashboardData dashboard) {
    return [
      _sectionHeading(
        3,
        'Time by category',
        'Percentages are based on total logged minutes',
      ),
      _table(
        headers: const ['Category', 'Logged time', 'Entries', 'Share'],
        rows: dashboard.categoryBreakdown
            .map(
              (item) => [
                item.category,
                formatLoggedTime(item.totalMinutes),
                item.entryCount.toString(),
                formatPercentage(item.percentage),
              ],
            )
            .toList(),
        emptyMessage: 'No category totals are available for this week.',
        columnWidths: const {
          0: pw.FlexColumnWidth(2.4),
          1: pw.FlexColumnWidth(1.3),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(1),
        },
      ),
    ];
  }

  List<pw.Widget> _productivitySection(DashboardData dashboard) {
    return [
      _sectionHeading(
        4,
        'Productivity breakdown',
        'Self-rated productivity across recorded activities',
      ),
      _breakdownTable(
        dashboard.productivityBreakdown,
        emptyMessage: 'No productivity ratings are available for this week.',
      ),
    ];
  }

  List<pw.Widget> _moodSection(DashboardData dashboard) {
    final mood = dashboard.moodBreakdown;
    return [
      _sectionHeading(
        5,
        'Mood journey',
        'How mood changed after recorded activities',
      ),
      pw.Row(
        children: [
          pw.Expanded(
            child: _metricCard(
              'Improved',
              mood.improvedCount.toString(),
              '${formatPercentage(mood.improvedPercentage)} of entries',
              accent: _accent,
              background: _accentSoft,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _metricCard(
              'Stable',
              mood.stableCount.toString(),
              'no recorded change',
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _metricCard(
              'Lower',
              mood.declinedCount.toString(),
              'declined after activity',
              accent: PdfColors.red700,
              background: PdfColors.red50,
            ),
          ),
        ],
      ),
    ];
  }

  List<pw.Widget> _outcomeSection(DashboardData dashboard) {
    return [
      _sectionHeading(6, 'Task outcomes', 'How recorded activities finished'),
      _breakdownTable(
        dashboard.outcomeBreakdown,
        emptyMessage: 'No task outcomes are available for this week.',
      ),
    ];
  }

  List<pw.Widget> _insightsSection(DashboardData dashboard) {
    final widgets = <pw.Widget>[
      _sectionHeading(
        7,
        'Evidence-grounded insights',
        'Patterns calculated from the selected week',
      ),
    ];

    if (dashboard.insights.isEmpty) {
      widgets.add(_emptyMessage('No insights are available for this week.'));
      return widgets;
    }

    for (final insight in dashboard.insights) {
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.all(11),
          decoration: pw.BoxDecoration(
            color: _primarySoft,
            border: pw.Border.all(color: _border),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      insight.title,
                      style: pw.TextStyle(
                        color: _ink,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  if (insight.sampleSize > 0)
                    pw.Text(
                      'Sample: ${insight.sampleSize}',
                      style: pw.TextStyle(color: _muted, fontSize: 7.5),
                    ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                insight.message,
                style: pw.TextStyle(color: _ink, fontSize: 9, height: 1.35),
              ),
              if (insight.evidenceIds.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  'Evidence: ${insight.evidenceIds.join(', ')}',
                  style: pw.TextStyle(
                    color: _primary,
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  List<pw.Widget> _summarySection(DashboardData dashboard) {
    final latest = dashboard.latestSummary;
    final widgets = <pw.Widget>[
      _sectionHeading(
        8,
        'Weekly AI summary',
        'Latest saved weekly reflection',
      ),
    ];

    if (latest == null) {
      widgets.add(_emptyMessage('No weekly summary has been generated yet.'));
      return widgets;
    }

    final details = <String>[];
    if (latest.generatedAt.isNotEmpty) {
      details.add('Generated ${_dateTimeFromString(latest.generatedAt)}');
    }

    if (details.isNotEmpty) {
      widgets.add(
        pw.Text(
          details.join(' | '),
          style: pw.TextStyle(
            color: _accent,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
      widgets.add(pw.SizedBox(height: 7));
    }

    if (latest.summaryText.isNotEmpty) {
      widgets.add(
        pw.Paragraph(
          text: latest.summaryText,
          style: pw.TextStyle(color: _ink, fontSize: 9.5, height: 1.4),
        ),
      );
    }
    if (latest.feedbackMessage.isNotEmpty) {
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 3),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _accentSoft,
            borderRadius: pw.BorderRadius.circular(7),
          ),
          child: pw.Text(
            latest.feedbackMessage,
            style: pw.TextStyle(color: _ink, fontSize: 9, height: 1.35),
          ),
        ),
      );
    }

    return widgets;
  }

  List<pw.Widget> _recentEntriesSection(DashboardData dashboard) {
    final widgets = <pw.Widget>[
      _sectionHeading(
        9,
        'Recent diary entries',
        'Latest saved evidence across all weeks',
      ),
    ];

    if (dashboard.recentEntries.isEmpty) {
      widgets.add(_emptyMessage('No recent diary entries are available.'));
      return widgets;
    }

    for (final entry in dashboard.recentEntries) {
      final metadata = <String>[
        if (entry.activityCategory.isNotEmpty) entry.activityCategory,
        if (entry.entryDate.isNotEmpty) _dateOnly(entry.entryDate),
        formatLoggedTime(entry.durationMinutes),
      ];
      final tags = <String>[
        if (entry.productivityLevel.isNotEmpty) entry.productivityLevel,
        if (entry.taskOutcome.isNotEmpty) entry.taskOutcome,
      ];

      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 7),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _paperTint,
            border: pw.Border.all(color: _border),
            borderRadius: pw.BorderRadius.circular(7),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 52,
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                decoration: pw.BoxDecoration(
                  color: _primarySoft,
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Text(
                  entry.evidenceId.isEmpty ? '-' : entry.evidenceId,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    color: _primary,
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 9),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      entry.activityName.isEmpty
                          ? 'Untitled activity'
                          : entry.activityName,
                      style: pw.TextStyle(
                        color: _ink,
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      metadata.join(' | '),
                      style: pw.TextStyle(color: _muted, fontSize: 7.5),
                    ),
                    if (tags.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        tags.join(' | '),
                        style: pw.TextStyle(color: _accent, fontSize: 7.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  pw.Widget _sectionHeading(int number, String title, String subtitle) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 18, bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 0.8)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Container(
            height: 22,
            width: 22,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: _primary,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              number.toString(),
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  subtitle,
                  style: pw.TextStyle(color: _muted, fontSize: 7.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _metricCard(
    String label,
    String value,
    String helper, {
    PdfColor? accent,
    PdfColor? background,
  }) {
    final cardAccent = accent ?? _primary;
    return pw.Container(
      height: 72,
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: background ?? _paperTint,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              color: cardAccent,
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            label,
            style: pw.TextStyle(
              color: _ink,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(helper, style: pw.TextStyle(color: _muted, fontSize: 6.5)),
        ],
      ),
    );
  }

  pw.Widget _breakdownTable(
    List<BreakdownItem> items, {
    required String emptyMessage,
  }) {
    return _table(
      headers: const ['Rating / outcome', 'Count', 'Share'],
      rows: items
          .map(
            (item) => [
              item.label,
              item.count.toString(),
              formatPercentage(item.percentage),
            ],
          )
          .toList(),
      emptyMessage: emptyMessage,
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
      },
    );
  }

  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    required String emptyMessage,
    required Map<int, pw.TableColumnWidth> columnWidths,
  }) {
    if (rows.isEmpty) return _emptyMessage(emptyMessage);

    return pw.Table(
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: _border, width: 0.6),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _primarySoft),
          children: headers.map(_headerCell).toList(),
        ),
        ...rows.map(
          (row) => pw.TableRow(children: row.map(_bodyCell).toList()),
        ),
      ],
    );
  }

  pw.Widget _headerCell(String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          color: _ink,
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _bodyCell(String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      child: pw.Text(
        value.isEmpty ? '-' : value,
        style: pw.TextStyle(color: _ink, fontSize: 8),
      ),
    );
  }

  pw.Widget _emptyMessage(String message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: _paperTint,
        border: pw.Border.all(color: _border),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Text(
        message,
        style: pw.TextStyle(
          color: _muted,
          fontSize: 8.5,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
    );
  }

  pw.Widget _pageHeader(DashboardData dashboard) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 0.6)),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'SMART DIARY',
            style: pw.TextStyle(
              color: _primary,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            _weekRange(dashboard.weekStart, dashboard.weekEnd),
            style: pw.TextStyle(color: _muted, fontSize: 7.5),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pageFooter(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Page ${context.pageNumber} of ${context.pagesCount}',
        style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 7),
      ),
    );
  }

  String _safeFilePart(String value, {required String fallback}) {
    final safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
    return safe.isEmpty ? fallback : safe;
  }

  String _weekRange(String start, String end) {
    final formattedStart = _dateOnly(start);
    final formattedEnd = _dateOnly(end);
    if (formattedStart == '-' && formattedEnd == '-') return 'Selected week';
    return '$formattedStart to $formattedEnd';
  }

  String _dateOnly(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value.isEmpty ? '-' : value;
    return '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _dateTimeFromString(String value) {
    final date = DateTime.tryParse(value);
    return date == null ? value : _dateTime(date.toLocal());
  }

  String _dateTime(DateTime value) {
    final minute = value.minute.toString().padLeft(2, '0');
    return '${_months[value.month - 1]} ${value.day}, ${value.year} '
        '${value.hour.toString().padLeft(2, '0')}:$minute';
  }
}

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
