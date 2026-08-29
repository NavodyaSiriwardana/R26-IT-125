import 'package:flutter/material.dart';

import '../../../core/network/dio_client.dart';
import '../models/Citation.dart';
import '../models/Compare_summary_response.dart';
import '../models/Diary_entry.dart';
import '../models/Rag_summary_point.dart';
import '../services/Rag_summary_service.dart';
import '../utils/diary_week_group.dart';
import '../widgets/Citation_chip.dart';
import '../widgets/Feedback_card.dart';
import 'Summary_generation_details_screen.dart';

String _cleanSummaryText(String text) {
  return text
      .trim()
      .replaceAll(
        RegExp(
          r'\b(?:this week|earlier in your diary|weekly highlight|diary reflection)\s*:\s*',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _SummaryParagraphSegment {
  final String text;
  final List<int> sourceNumbers;

  const _SummaryParagraphSegment({
    required this.text,
    required this.sourceNumbers,
  });
}

class _SummaryParagraphData {
  final List<_SummaryParagraphSegment> segments;
  final List<Citation> sources;

  const _SummaryParagraphData({
    required this.segments,
    required this.sources,
  });
}

List<RagSummaryPoint> _supportedRagPoints(CompareSummaryResponse summary) {
  final rag = summary.rag;
  final rawClaims = rag.evaluation['per_claim'];
  if (rawClaims is! List) return const <RagSummaryPoint>[];

  final claimsById = <String, List<Map>>{};
  for (final rawClaim in rawClaims) {
    if (rawClaim is! Map) continue;
    final claimId = rawClaim['claim_id']?.toString().trim() ?? '';
    if (claimId.isNotEmpty) {
      claimsById.putIfAbsent(claimId, () => <Map>[]).add(rawClaim);
    }
  }

  final supported = <RagSummaryPoint>[];
  for (final entry in rag.summaryPoints.asMap().entries) {
    final claimId = entry.value.claimId;
    final matchingClaims = claimId == null ? null : claimsById[claimId];
    final isSupportedById = matchingClaims != null &&
        matchingClaims.isNotEmpty &&
        matchingClaims.every(_isEntailedClaim);
    final hasSafeIndexFallback = rawClaims.length == rag.summaryPoints.length;
    final isSupportedByIndex = hasSafeIndexFallback &&
        entry.key < rawClaims.length &&
        _isEntailedClaim(rawClaims[entry.key]);
    if (isSupportedById || (matchingClaims == null && isSupportedByIndex)) {
      supported.add(entry.value);
    }
  }
  return supported;
}

bool _isEntailedClaim(dynamic rawClaim) {
  if (rawClaim is! Map) return false;
  return rawClaim['classification']?.toString().trim().toLowerCase() ==
      'entailed';
}

_SummaryParagraphData _summaryParagraph(
  List<RagSummaryPoint> summaryPoints,
) {
  final segments = <_SummaryParagraphSegment>[];
  final sources = <Citation>[];
  final sourceNumberByEvidenceId = <String, int>{};

  for (final point in summaryPoints) {
    final text = _cleanSummaryText(point.text);
    if (text.isEmpty) continue;

    final sourceNumbers = <int>[];
    for (final citation in point.citations) {
      final evidenceId = citation.evidenceId.trim();
      if (evidenceId.isEmpty || !citation.canOpenEvidence) continue;

      var sourceNumber = sourceNumberByEvidenceId[evidenceId];
      if (sourceNumber == null) {
        sources.add(citation);
        sourceNumber = sources.length;
        sourceNumberByEvidenceId[evidenceId] = sourceNumber;
      } else if (!sources[sourceNumber - 1].canOpenEvidence &&
          citation.canOpenEvidence) {
        sources[sourceNumber - 1] = citation;
      }

      if (!sourceNumbers.contains(sourceNumber)) {
        sourceNumbers.add(sourceNumber);
      }
    }

    segments.add(
      _SummaryParagraphSegment(text: text, sourceNumbers: sourceNumbers),
    );
  }

  return _SummaryParagraphData(segments: segments, sources: sources);
}

class SummaryResultScreen extends StatefulWidget {
  final String userId;
  final String? weekStart;
  final String? weekEnd;
  final CompareSummaryResponse? preloadedSummary;

  const SummaryResultScreen({
    super.key,
    required this.userId,
    this.weekStart,
    this.weekEnd,
    this.preloadedSummary,
  });

  @override
  State<SummaryResultScreen> createState() => _SummaryResultScreenState();
}

class _SummaryResultScreenState extends State<SummaryResultScreen> {
  late final RagSummaryService _service;

  CompareSummaryResponse? _summary;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = RagSummaryService(DioClient());
    _summary = widget.preloadedSummary;
    _isLoading = _summary == null;

    if (_summary == null) {
      _loadSummary();
    }
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = widget.preloadedSummary == null
          ? await _service.generateWeeklySummary(
              userId: widget.userId,
              query:
                  'Summarize my activity, productivity and mood for this week and give feedback',
              weekStart: widget.weekStart,
              weekEnd: widget.weekEnd,
              topK: 8,
              retrievalMode: 'auto',
            )
          : await _service.getLatestWeeklySummary(
              userId: widget.userId,
              weekStart: widget.weekStart,
              weekEnd: widget.weekEnd,
            );

      if (!mounted) return;

      setState(() {
        _summary = result;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Your weekly reflection could not be loaded.';
        _isLoading = false;
      });
    }
  }

  Future<void> _openEvidence(Citation citation) async {
    try {
      final evidence = await _service.getEvidenceById(
        userId: widget.userId,
        evidenceId: citation.evidenceId,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _EvidenceDialog(evidence: evidence),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('That diary entry could not be opened.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B14),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7F77DD)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0B14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B14),
          elevation: 0,
          foregroundColor: const Color(0xFFEDEBFF),
          title: const Text(
            'Weekly Summary',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: SafeArea(
          child: _EmptyStateCard(
            icon: Icons.cloud_off,
            title: 'Could not create your reflection',
            message:
                'Something went wrong while looking back at this week. Please try again.',
            actionLabel: 'Try Again',
            onAction: _loadSummary,
          ),
        ),
      );
    }

    final summary = _summary!;

    final supportedPoints = _supportedRagPoints(summary);

    if (supportedPoints.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0B14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B14),
          elevation: 0,
          foregroundColor: const Color(0xFFEDEBFF),
          title: const Text(
            'Weekly Summary',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: SafeArea(
          child: _EmptyStateCard(
            icon: Icons.notes_outlined,
            title: 'No supported RAG summary is available',
            message:
                'No generated sentence was supported by its cited diary evidence in this run. You can review how it was generated for more information.',
            actionLabel: 'How it was generated',
            onAction: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SummaryGenerationDetailsScreen(summary: summary),
                ),
              );
            },
          ),
        ),
      );
    }

    final paragraph = _summaryParagraph(supportedPoints);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B14),
        elevation: 0,
        foregroundColor: const Color(0xFFEDEBFF),
        title: const Text(
          'Weekly Summary',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadSummary,
          color: const Color(0xFF7F77DD),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
            children: [
              _HeroCard(summary: summary),
              const SizedBox(height: 18),

              _SectionTitle(
                title: 'Your week in review',
                subtitle: 'Key moments and patterns from your diary entries.',
              ),
              const SizedBox(height: 12),

              _SummaryParagraphCard(
                paragraph: paragraph,
                onCitationTap: _openEvidence,
              ),

              const SizedBox(height: 10),

              FeedbackCard(feedback: summary.feedback),

              const SizedBox(height: 18),

              _GenerationDetailsButton(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SummaryGenerationDetailsScreen(summary: summary),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final CompareSummaryResponse summary;

  const _HeroCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final weekText = summary.weekStart != null && summary.weekEnd != null
        ? diaryWeekRangeFromValues(summary.weekStart, summary.weekEnd)
        : 'Current week';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3C3489), Color(0xFF181728)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Color(0xFF7F77DD)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7F77DD).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WEEKLY REFLECTION',
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 11,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Your weekly diary reflection is ready',
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            weekText,
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFEDEBFF),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFFB8B4D8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SummaryParagraphCard extends StatelessWidget {
  final _SummaryParagraphData paragraph;
  final void Function(Citation citation) onCitationTap;

  const _SummaryParagraphCard({
    required this.paragraph,
    required this.onCitationTap,
  });

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (final entry in paragraph.segments.asMap().entries) {
      final segment = entry.value;
      final separator = entry.key == 0 ? '' : ' ';
      final punctuationMatch = RegExp(r'([.!?])$').firstMatch(segment.text);
      final punctuation = punctuationMatch?.group(1) ?? '';
      final sentence = punctuation.isEmpty
          ? segment.text
          : segment.text.substring(0, segment.text.length - 1);
      spans.add(
        TextSpan(text: '$separator$sentence'),
      );
      if (segment.sourceNumbers.isNotEmpty) {
        spans.add(
          TextSpan(
            text: ' [${segment.sourceNumbers.join(', ')}]',
            style: const TextStyle(
              color: Color(0xFF87F5D0),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
      }
      if (punctuation.isNotEmpty) {
        spans.add(TextSpan(text: punctuation));
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF181728),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF514A96)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: spans),
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 15,
              height: 1.65,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (paragraph.sources.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'SOURCES',
              style: TextStyle(
                color: Color(0xFFB8B4D8),
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: paragraph.sources
                  .asMap()
                  .entries
                  .map(
                    (entry) => CitationChip(
                      citation: entry.value,
                      sourceNumber: entry.key + 1,
                      onTap: entry.value.canOpenEvidence
                          ? () => onCitationTap(entry.value)
                          : null,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _GenerationDetailsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _GenerationDetailsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF181728),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF403A78)),
        ),
        child: const Row(
          children: [
            Icon(Icons.insights, color: Color(0xFF7F77DD)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'How this summary was generated',
                style: TextStyle(
                  color: Color(0xFFEDEBFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Color(0xFFB8B4D8), size: 16),
          ],
        ),
      ),
    );
  }
}

class _EvidenceDialog extends StatelessWidget {
  final DiaryEntry evidence;

  const _EvidenceDialog({required this.evidence});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF181728),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFF7F77DD)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Diary entry',
                style: const TextStyle(
                  color: Color(0xFFEDEBFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                evidence.activityName,
                style: const TextStyle(
                  color: Color(0xFF87F5D0),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              _EvidenceRow(label: 'Category', value: evidence.activityCategory),
              _EvidenceRow(
                label: 'Date',
                value: diaryEntryFriendlyDate(evidence.entryDate),
              ),
              _EvidenceRow(
                label: 'Time',
                value:
                    '${evidence.startTime} - ${evidence.endTime} (${evidence.durationMinutes} min)',
              ),
              _EvidenceRow(
                label: 'Productivity',
                value: evidence.productivityLevel,
              ),
              _EvidenceRow(
                label: 'Mood',
                value: '${evidence.moodBefore} → ${evidence.moodAfter}',
              ),
              _EvidenceRow(label: 'Outcome', value: evidence.taskOutcome),
              _EvidenceRow(label: 'Health', value: evidence.healthStatus),
              _EvidenceRow(label: 'Location', value: evidence.location),
              _EvidenceRow(label: 'With whom', value: evidence.withWhom),
              if (evidence.notes != null && evidence.notes!.isNotEmpty)
                _EvidenceRow(label: 'Notes', value: evidence.notes!),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F77DD),
                    foregroundColor: const Color(0xFF0B0B14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  final String label;
  final String value;

  const _EvidenceRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF181728),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF403A78)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7F77DD).withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFF3C3489),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF7F77DD)),
                ),
                child: Icon(icon, color: const Color(0xFFEDEBFF), size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFEDEBFF),
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFB8B4D8),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F77DD),
                    foregroundColor: const Color(0xFF0B0B14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onAction,
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
