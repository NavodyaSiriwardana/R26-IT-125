import 'package:flutter/material.dart';

import '../models/dashboard_data.dart';
import '../theme/dashboard_colors.dart';
import 'dashboard_formatters.dart';

class OverviewCards extends StatelessWidget {
  final DashboardOverview overview;

  const OverviewCards({super.key, required this.overview});

  @override
  Widget build(BuildContext context) {
    final items = <_OverviewItem>[
      _OverviewItem(
        label: 'Activities',
        value: overview.activityCount.toString(),
        helper: 'recorded this week',
        icon: Icons.checklist_rounded,
        color: DashboardColors.primary,
      ),
      _OverviewItem(
        label: 'Logged time',
        value: formatLoggedTime(overview.loggedMinutes),
        helper: 'across all activities',
        icon: Icons.schedule_rounded,
        color: const Color(0xFF5CB8E6),
      ),
      _OverviewItem(
        label: 'Completed',
        value: formatPercentage(overview.completionRate),
        helper: 'of recorded activities',
        icon: Icons.task_alt_rounded,
        color: DashboardColors.accentText,
      ),
      _OverviewItem(
        label: 'Mood improved',
        value: formatPercentage(overview.moodImprovedRate),
        helper: 'after activities',
        icon: Icons.sentiment_satisfied_alt_rounded,
        color: DashboardColors.warning,
      ),
    ];

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _OverviewCard(item: items[0])),
            const SizedBox(width: 12),
            Expanded(child: _OverviewCard(item: items[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _OverviewCard(item: items[2])),
            const SizedBox(width: 12),
            Expanded(child: _OverviewCard(item: items[3])),
          ],
        ),
      ],
    );
  }
}

class _OverviewItem {
  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;

  const _OverviewItem({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
  });
}

class _OverviewCard extends StatelessWidget {
  final _OverviewItem item;

  const _OverviewCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 138),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: DashboardColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DashboardColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(item.icon, color: item.color, size: 19),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              item.value,
              style: const TextStyle(
                color: DashboardColors.text,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: const TextStyle(
              color: DashboardColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.helper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: DashboardColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
