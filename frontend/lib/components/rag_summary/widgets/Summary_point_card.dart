import 'package:flutter/material.dart';

import '../models/Citation.dart';
import '../models/Rag_summary_point.dart';
import 'Citation_chip.dart';

class SummaryPointCard extends StatelessWidget {
  final int index;
  final RagSummaryPoint point;
  final void Function(Citation citation) onCitationTap;

  const SummaryPointCard({
    super.key,
    required this.index,
    required this.point,
    required this.onCitationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181728),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF403A78)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7F77DD).withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF7F77DD),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: Color(0xFF0B0B14),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'WEEKLY HIGHLIGHT',
                style: TextStyle(
                  color: Color(0xFFB8B4D8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            point.text,
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (point.citations.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: point.citations
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
