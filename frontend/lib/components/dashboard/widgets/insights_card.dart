import 'package:flutter/material.dart';

import '../models/dashboard_data.dart';
import '../theme/dashboard_colors.dart';
import 'dashboard_section_card.dart';

class InsightsCard extends StatelessWidget {
  final List<DashboardInsight> insights;
  final ValueChanged<String>? onEvidenceTap;

  const InsightsCard({super.key, required this.insights, this.onEvidenceTap});

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: 'Weekly insights',
      subtitle: 'Patterns noticed in the activities you logged',
      icon: Icons.lightbulb_outline_rounded,
      child: insights.isEmpty
          ? const DashboardInlineEmpty(
              message:
                  'Keep logging activities to reveal useful weekly patterns.',
            )
          : Column(
              children: insights.asMap().entries.map((entry) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == insights.length - 1 ? 0 : 12,
                  ),
                  child: _InsightTile(
                    insight: entry.value,
                    onEvidenceTap: onEvidenceTap,
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  final DashboardInsight insight;
  final ValueChanged<String>? onEvidenceTap;

  const _InsightTile({required this.insight, required this.onEvidenceTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            DashboardColors.primaryDark.withValues(alpha: 0.62),
            DashboardColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DashboardColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: DashboardColors.accentText,
                size: 18,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  insight.title,
                  style: const TextStyle(
                    color: DashboardColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (insight.sampleSize > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: DashboardColors.background.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Based on ${insight.sampleSize} ${insight.sampleSize == 1 ? 'entry' : 'entries'}',
                    style: const TextStyle(
                      color: DashboardColors.muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            insight.message,
            style: const TextStyle(
              color: DashboardColors.muted,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (insight.evidenceIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: insight.evidenceIds.asMap().entries.map((entry) {
                final evidenceId = entry.value;
                return ActionChip(
                  onPressed: onEvidenceTap == null
                      ? null
                      : () => onEvidenceTap!(evidenceId),
                  visualDensity: VisualDensity.compact,
                  side: const BorderSide(color: DashboardColors.primary),
                  backgroundColor: DashboardColors.primaryDark,
                  disabledColor: DashboardColors.primaryDark,
                  label: Text(
                    'View entry ${entry.key + 1}',
                    style: const TextStyle(
                      color: DashboardColors.text,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  avatar: const Icon(
                    Icons.link_rounded,
                    color: DashboardColors.accentText,
                    size: 14,
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
