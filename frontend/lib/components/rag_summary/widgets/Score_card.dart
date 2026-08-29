import 'package:flutter/material.dart';

class ScoreCard extends StatelessWidget {
  final String title;
  final double? score;
  final String caption;
  final bool? isBetter;

  const ScoreCard({
    super.key,
    required this.title,
    required this.score,
    required this.caption,
    required this.isBetter,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = score == null ? null : (score! * 100).round();
    final borderColor = isBetter == null
        ? const Color(0xFF403A78)
        : isBetter!
        ? const Color(0xFF1D9E75)
        : const Color(0xFFFFB4A8);
    final valueColor = isBetter == null
        ? const Color(0xFFB8B4D8)
        : isBetter!
        ? const Color(0xFF87F5D0)
        : const Color(0xFFFFB4A8);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181728),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            percentage == null ? 'N/A' : '$percentage%',
            style: TextStyle(
              color: valueColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
