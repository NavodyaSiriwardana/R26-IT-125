import 'package:flutter/material.dart';

import '../models/dashboard_data.dart';
import '../theme/dashboard_colors.dart';
import 'dashboard_formatters.dart';

class WeeklySummaryPanel extends StatelessWidget {
  final DashboardLatestSummary? latestSummary;
  final int evidenceEntryCount;
  final VoidCallback? onGenerateSummary;
  final VoidCallback? onViewLatest;

  const WeeklySummaryPanel({
    super.key,
    required this.latestSummary,
    required this.evidenceEntryCount,
    this.onGenerateSummary,
    this.onViewLatest,
  });

  @override
  Widget build(BuildContext context) {
    final latest = latestSummary;
    final entryLabel = evidenceEntryCount == 1 ? 'entry' : 'entries';

    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [DashboardColors.primaryDark, DashboardColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: DashboardColors.primary),
        boxShadow: [
          BoxShadow(
            color: DashboardColors.primary.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: DashboardColors.accent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: DashboardColors.background,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly reflection',
                      style: TextStyle(
                        color: DashboardColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'A thoughtful look back at your diary',
                      style: TextStyle(
                        color: DashboardColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: DashboardColors.background.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$evidenceEntryCount $entryLabel',
                  style: const TextStyle(
                    color: DashboardColors.accentText,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (latest == null)
            const Text(
              'Turn this week’s activities into a clear reflection with useful '
              'mood and productivity suggestions.',
              style: TextStyle(
                color: DashboardColors.muted,
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            )
          else ...[
            const Text(
              'LATEST REFLECTION',
              style: TextStyle(
                color: DashboardColors.muted,
                fontSize: 9,
                letterSpacing: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (latest.summaryText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                latest.summaryText,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: DashboardColors.text,
                  fontSize: 12,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (latest.feedbackMessage.isNotEmpty) ...[
              const SizedBox(height: 11),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: DashboardColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  latest.feedbackMessage,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DashboardColors.accentText,
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (latest.generatedAt.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                'Created ${formatGeneratedAt(latest.generatedAt)}',
                style: const TextStyle(
                  color: DashboardColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
          const SizedBox(height: 17),
          Row(
            children: [
              if (latest != null && onViewLatest != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onViewLatest,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DashboardColors.text,
                      side: const BorderSide(color: DashboardColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text(
                      'Read reflection',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: evidenceEntryCount == 0 ? null : onGenerateSummary,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                  label: Text(
                    latest == null ? 'Create reflection' : 'Create new',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DashboardColors.accent,
                    disabledBackgroundColor: DashboardColors.border,
                    foregroundColor: DashboardColors.background,
                    disabledForegroundColor: DashboardColors.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
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
