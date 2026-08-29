import 'package:flutter/material.dart';

import '../models/Citation.dart';

class CitationChip extends StatelessWidget {
  final Citation citation;
  final int sourceNumber;
  final VoidCallback? onTap;

  const CitationChip({
    super.key,
    required this.citation,
    required this.sourceNumber,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final available = citation.canOpenEvidence;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: available ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: available ? const Color(0xFF3C3489) : const Color(0xFF2A2838),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: available
                ? const Color(0xFF7F77DD)
                : const Color(0xFF57536E),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              available ? Icons.menu_book_outlined : Icons.link_off_rounded,
              color: available
                  ? const Color(0xFFEDEBFF)
                  : const Color(0xFFB8B4D8),
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              available
                  ? 'View diary entry $sourceNumber'
                  : 'Source unavailable',
              style: TextStyle(
                color: available
                    ? const Color(0xFFEDEBFF)
                    : const Color(0xFFB8B4D8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
