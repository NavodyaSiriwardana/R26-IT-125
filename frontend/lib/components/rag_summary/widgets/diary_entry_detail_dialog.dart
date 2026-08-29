import 'package:flutter/material.dart';

import '../models/Diary_entry.dart';
import '../utils/diary_week_group.dart';

class DiaryEntryDetailDialog extends StatelessWidget {
  final DiaryEntry entry;

  const DiaryEntryDetailDialog({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF181728),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      title: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF3C3489),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF7F77DD)),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Color(0xFFEDEBFF),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Diary entry',
                  style: TextStyle(
                    color: Color(0xFFB8B4D8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.activityName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEDEBFF),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow(label: 'Category', value: entry.activityCategory),
              _DetailRow(
                label: 'Date',
                value: diaryEntryFriendlyDate(entry.entryDate),
              ),
              _DetailRow(
                label: 'Time',
                value:
                    '${entry.startTime} - ${entry.endTime} (${entry.durationMinutes} min)',
              ),
              _DetailRow(label: 'Productivity', value: entry.productivityLevel),
              _DetailRow(
                label: 'Mood',
                value: '${entry.moodBefore} → ${entry.moodAfter}',
              ),
              _DetailRow(label: 'Outcome', value: entry.taskOutcome),
              _DetailRow(label: 'Health', value: entry.healthStatus),
              _DetailRow(label: 'Location', value: entry.location),
              _DetailRow(label: 'With whom', value: entry.withWhom),
              if (entry.personNames != null && entry.personNames!.isNotEmpty)
                _DetailRow(label: 'People', value: entry.personNames!),
              if (entry.notes != null && entry.notes!.isNotEmpty)
                _DetailRow(label: 'Notes', value: entry.notes!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF87F5D0)),
          child: const Text(
            'Close',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFB8B4D8),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFFEDEBFF),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
