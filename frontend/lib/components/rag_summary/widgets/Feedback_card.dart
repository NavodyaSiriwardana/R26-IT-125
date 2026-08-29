import 'package:flutter/material.dart';

import '../models/Feedback_result.dart';

class FeedbackCard extends StatelessWidget {
  final FeedbackResult feedback;

  const FeedbackCard({super.key, required this.feedback});

  @override
  Widget build(BuildContext context) {
    final message = feedback.message.trim().isEmpty
        ? feedback.abstained
              ? 'Keep adding diary entries and a useful suggestion will appear here.'
              : 'There is no suggestion for this week yet.'
        : feedback.message.trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF10231E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1D9E75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFF1D9E75),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                feedback.abstained
                    ? 'Keep reflecting'
                    : 'A suggestion for next week',
                style: const TextStyle(
                  color: Color(0xFFEDEBFF),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (feedback.action.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0B14).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TRY THIS',
                    style: TextStyle(
                      color: Color(0xFF87F5D0),
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    feedback.action.trim(),
                    style: const TextStyle(
                      color: Color(0xFFEDEBFF),
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (feedback.moodSignal.trim().isNotEmpty ||
              feedback.productivitySignal.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (feedback.moodSignal.trim().isNotEmpty)
                  _Tag(label: 'Mood: ${_displayValue(feedback.moodSignal)}'),
                if (feedback.productivitySignal.trim().isNotEmpty)
                  _Tag(
                    label:
                        'Productivity: ${_displayValue(feedback.productivitySignal)}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1D9E75).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF87F5D0),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _displayValue(String value) {
  return value
      .trim()
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
