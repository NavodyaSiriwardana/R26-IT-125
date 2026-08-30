import 'package:flutter/material.dart';
import '../models/pattern_model.dart';

class PatternCard extends StatelessWidget {
  final PatternModel pattern;
  final VoidCallback onSeeEvidence;
  final VoidCallback onDismiss;

  const PatternCard({
    super.key,
    required this.pattern,
    required this.onSeeEvidence,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isStrong = pattern.patternLevel == 'Strong';
    final badgeColor = isStrong
        ? const Color(0xFF1DB954)
        : const Color(0xFFF5A623);
    final borderColor = isStrong
        ? const Color(0xFF1DB95430)
        : const Color(0xFFF5A62330);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF13132A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      pattern.patternLevel.toUpperCase(),
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (pattern.dfsScore > 0 &&
                      pattern.analysisVersion
                          .contains('cross'))
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B61FF20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'cross-day',
                        style: TextStyle(
                          color: Color(0xFF7B61FF),
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                '${pattern.confidencePercentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pattern.shortInsight,
            style: const TextStyle(
              color: Color(0xFFd0d0e8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${pattern.matchedCount} out of '
            '${pattern.totalTriggerCount} times',
            style: const TextStyle(
              color: Color(0xFF7B61FF),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.calendar_today,
                  size: 11, color: Color(0xFF5a5a7a)),
              const SizedBox(width: 4),
              Text(
                '${pattern.evidenceDates.length} diary entries',
                style: const TextStyle(
                  color: Color(0xFF5a5a7a),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onSeeEvidence,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF7B61FF)),
                    ),
                    child: const Center(
                      child: Text(
                        'See dates',
                        style: TextStyle(
                          color: Color(0xFF7B61FF),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Text(
                    'Dismiss',
                    style: TextStyle(
                      color: Color(0xFF5a5a7a),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}