import 'package:flutter/material.dart';

import '../models/Compare_summary_response.dart';

class SummaryGenerationDetailsScreen extends StatelessWidget {
  final CompareSummaryResponse summary;

  const SummaryGenerationDetailsScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final conditions = [
      _ConditionSpec(
        keyName: 'plain_slm',
        title: 'Condition A: Plain summary',
        description:
            'The model receives every activity from the selected week as ordinary plain text and a standard summarization prompt.',
        result: summary.plainSlm,
      ),
      _ConditionSpec(
        keyName: 'rag',
        title: 'Condition B: Grounded RAG summary',
        description:
            'Whole-week requests retrieve all activities from the selected week, while focused questions use relevance. The model is instructed to use only retrieved evidence and omit unsupported details.',
        result: summary.rag,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B14),
        elevation: 0,
        foregroundColor: const Color(0xFFEDEBFF),
        title: const Text(
          'How the summary was generated',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          const _IntroCard(),
          const SizedBox(height: 16),
          // _HallucinationComparisonCard(summary: summary),
          const SizedBox(height: 16),
          for (final condition in conditions) ...[
            _ConditionPanel(spec: condition),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _ConditionSpec {
  final String keyName;
  final String title;
  final String description;
  final SummaryConditionResult result;

  const _ConditionSpec({
    required this.keyName,
    required this.title,
    required this.description,
    required this.result,
  });
}

class _ConditionPanel extends StatelessWidget {
  final _ConditionSpec spec;

  const _ConditionPanel({required this.spec});

  @override
  Widget build(BuildContext context) {
    final result = spec.result;
    final provenance = _generationProvenance(result);

    return Container(
      key: ValueKey('condition-${spec.keyName}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181728),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF403A78)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  spec.title,
                  style: const TextStyle(
                    color: Color(0xFFEDEBFF),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StatusChip(
                status: result.displayStatus,
                successful: result.isSuccessful,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            spec.description,
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'MODEL OUTPUT',
            style: TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            result.summaryText.isEmpty
                ? 'No model output was returned for this condition.'
                : result.summaryText,
            style: TextStyle(
              color: result.summaryText.isEmpty
                  ? const Color(0xFFFFD180)
                  : const Color(0xFFEDEBFF),
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _MetricGrid(result: result),
          if (provenance.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              provenance,
              style: const TextStyle(
                color: Color(0xFF9894BB),
                fontSize: 10,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HallucinationComparisonCard extends StatelessWidget {
  final CompareSummaryResponse summary;

  const _HallucinationComparisonCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final plain = summary.plainSlm.metric('unsupported_claim_rate');
    final rag = summary.rag.metric('unsupported_claim_rate');
    final available = plain != null && rag != null;
    final improvement = available ? plain - rag : null;
    final favorsRag = improvement != null && improvement > 0.00005;
    final tied = improvement != null && improvement.abs() <= 0.00005;
    final color = !available
        ? const Color(0xFFFFD180)
        : favorsRag
        ? const Color(0xFF87F5D0)
        : const Color(0xFFFFD180);

    final headline = !available
        ? 'The grounding estimate is unavailable for this run'
        : favorsRag
        ? 'RAG had ${(improvement * 100).toStringAsFixed(1)} points fewer unsupported statements'
        : tied
        ? 'Both summaries had the same estimated unsupported rate'
        : 'RAG did not reduce unsupported statements in this run';

    return Container(
      key: const ValueKey('hallucination-comparison-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181728),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: color, size: 21),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Estimated grounding comparison',
                  style: TextStyle(
                    color: Color(0xFFEDEBFF),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            headline,
            style: TextStyle(
              color: color,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (available) ...[
            const SizedBox(height: 15),
            _RateRow(label: 'Plain', value: plain),
            const SizedBox(height: 10),
            _RateRow(label: 'RAG', value: rag),
          ],
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              iconColor: const Color(0xFFB8B4D8),
              collapsedIconColor: const Color(0xFFB8B4D8),
              title: const Text(
                'How this estimate works',
                style: TextStyle(
                  color: Color(0xFFB8B4D8),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              children: const [
                Text(
                  'A local NLI model checks each generated factual claim against short, relevant canonical diary evidence; RAG claims are checked against their cited records. Claim counts are separate from diary-entry coverage, and non-entailed results remain estimates rather than proven hallucinations.',
                  style: TextStyle(
                    color: Color(0xFF9894BB),
                    fontSize: 10,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
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

class _RateRow extends StatelessWidget {
  final String label;
  final double value;

  const _RateRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(0.0, 1.0).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: safeValue,
              backgroundColor: const Color(0xFF302C55),
              valueColor: AlwaysStoppedAnimation<Color>(
                label == 'RAG'
                    ? const Color(0xFF87F5D0)
                    : const Color(0xFF7F77DD),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          child: Text(
            '${(safeValue * 100).toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final SummaryConditionResult result;

  const _MetricGrid({required this.result});

  @override
  Widget build(BuildContext context) {
    final totalClaims = result.metric('total_factual_claims');
    final metrics = <_MetricValue>[
      _MetricValue(
        label: 'Claim support',
        secondaryText: _fractionDetails(
          result.metric('entailed_claim_count'),
          totalClaims,
          'factual claims supported',
        ),
        value: result.metric('grounded_claim_rate'),
        kind: _MetricKind.rate,
      ),
      _MetricValue(
        label: 'Unsupported claims',
        secondaryText: _countDetails(
          result.metric('unsupported_claim_count'),
          'unsupported claims',
        ),
        value: result.metric('unsupported_claim_rate'),
        kind: _MetricKind.rate,
      ),
      _MetricValue(
        label: 'Generation time',
        value: result.metric('generation_latency_ms'),
        kind: _MetricKind.milliseconds,
      ),
    ];
    final retrievalCoverage = result.metric('retrieval_coverage');
    final answerCoverage = result.metric('answer_coverage');
    final weeklyEntryCount = result.metric('weekly_entry_count');

    if (retrievalCoverage != null) {
      metrics.add(
        _MetricValue(
          label: 'Entries retrieved',
          secondaryText: _fractionDetails(
            result.metric('retrieved_evidence_count'),
            weeklyEntryCount,
            'diary entries',
          ),
          value: retrievalCoverage,
          kind: _MetricKind.rate,
        ),
      );
    }
    if (answerCoverage != null) {
      metrics.add(
        _MetricValue(
          label: 'Entry coverage',
          secondaryText: _fractionDetails(
            result.metric('represented_entry_count'),
            weeklyEntryCount,
            'diary entries represented',
          ),
          value: answerCoverage,
          kind: _MetricKind.rate,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: metrics.map((metric) => _MetricTile(metric: metric)).toList(),
    );
  }
}

enum _MetricKind { rate, milliseconds }

class _MetricValue {
  final String label;
  final double? value;
  final _MetricKind kind;
  final String? secondaryText;

  const _MetricValue({
    required this.label,
    required this.value,
    required this.kind,
    this.secondaryText,
  });
}

class _MetricTile extends StatelessWidget {
  final _MetricValue metric;

  const _MetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B14).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF302C55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 9,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _formatMetric(metric),
            style: TextStyle(
              color: metric.value == null
                  ? const Color(0xFFFFD180)
                  : const Color(0xFF87F5D0),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (metric.secondaryText != null) ...[
            const SizedBox(height: 4),
            Text(
              metric.secondaryText!,
              style: const TextStyle(
                color: Color(0xFF9894BB),
                fontSize: 9,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool successful;

  const _StatusChip({required this.status, required this.successful});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final unavailable =
        normalized.contains('unavailable') ||
        normalized.contains('failed') ||
        normalized.contains('error');
    final color = successful
        ? const Color(0xFF87F5D0)
        : unavailable
        ? const Color(0xFFFFB4A8)
        : const Color(0xFFFFD180);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        _displayValue(status),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181728),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7F77DD)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plain text compared with grounded RAG',
            style: TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Both conditions use the same local model, week, query, and decoding settings. Their input method and prompt differ. Claim support is calculated from generated factual claims; retrieval and entry coverage are calculated from diary entries.',
            style: TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String? _fractionDetails(
  double? count,
  double? total,
  String description,
) {
  if (count == null || total == null) return null;
  return '${count.round()} of ${total.round()} $description';
}

String? _countDetails(double? count, String description) {
  if (count == null) return null;
  return '${count.round()} $description';
}

String _formatMetric(_MetricValue metric) {
  final value = metric.value;
  if (value == null) return 'N/A';
  switch (metric.kind) {
    case _MetricKind.rate:
      return '${(value * 100).clamp(0, 100).toStringAsFixed(1)}%';
    case _MetricKind.milliseconds:
      return '${value.round()} ms';
  }
}

String _generationProvenance(SummaryConditionResult result) {
  final generation = result.generation;
  final model = generation['model_name'] ?? generation['model'];
  final revision = generation['model_revision'] ?? generation['revision'];
  final promptVersion = generation['prompt_version'];
  final seed = generation['random_seed'] ?? generation['seed'];
  final parts = <String>[];

  void addPart(String label, dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) parts.add('$label: $text');
  }

  addPart('Model', model);
  addPart('Revision', revision);
  addPart('Prompt', promptVersion);
  addPart('Seed', seed);
  return parts.join(' | ');
}

String _displayValue(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return 'Not reported';
  return normalized
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
