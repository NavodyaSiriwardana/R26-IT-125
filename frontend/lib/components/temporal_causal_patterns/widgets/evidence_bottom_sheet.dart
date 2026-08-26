import 'package:flutter/material.dart';
import '../models/pattern_model.dart';

class EvidenceBottomSheet extends StatelessWidget {
  final PatternModel pattern;

  const EvidenceBottomSheet({
    super.key,
    required this.pattern,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF13132A),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a3a),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Evidence dates',
            style: TextStyle(
              color: Color(0xFF7b7b9a),
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pattern.insightText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          ...pattern.evidenceDates.map((date) => Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 10),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Color(0xFF1e1e2e),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        size: 12,
                        color: Color(0xFF7B61FF)),
                    const SizedBox(width: 10),
                    Text(
                      date,
                      style: const TextStyle(
                        color: Color(0xFFc0c0d8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward,
                        size: 12,
                        color: Color(0xFF7B61FF)),
                    const SizedBox(width: 6),
                    Text(
                      pattern.outcome
                          .replaceAll('moodAfter = ', '')
                          .replaceAll(
                              'healthStatus = ', '')
                          .replaceAll(
                              'productivityLevel = ', '')
                          .replaceAll(
                              'taskOutcome = ', ''),
                      style: const TextStyle(
                        color: Color(0xFFF5A623),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1e1e2e),
                padding: const EdgeInsets.symmetric(
                    vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}