import 'package:flutter/material.dart';

import '../models/dashboard_data.dart';
import '../theme/dashboard_colors.dart';
import 'dashboard_formatters.dart';
import 'dashboard_section_card.dart';

class CategoryBreakdownCard extends StatelessWidget {
  final List<CategoryBreakdownItem> items;

  const CategoryBreakdownCard({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: 'Time by category',
      subtitle: 'Where your recorded time went',
      icon: Icons.donut_large_rounded,
      child: items.isEmpty
          ? const DashboardInlineEmpty(
              message: 'Category totals will appear here.',
            )
          : Column(
              children: items.asMap().entries.map((entry) {
                final color =
                    DashboardColors.chartColors[entry.key %
                        DashboardColors.chartColors.length];
                final item = entry.value;

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == items.length - 1 ? 0 : 16,
                  ),
                  child: _CategoryRow(item: item, color: color),
                );
              }).toList(),
            ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final CategoryBreakdownItem item;
  final Color color;

  const _CategoryRow({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              height: 9,
              width: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: DashboardColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              formatLoggedTime(item.totalMinutes),
              style: const TextStyle(
                color: DashboardColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: Text(
                formatPercentage(item.percentage),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: DashboardColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: percentageFraction(item.percentage),
            backgroundColor: DashboardColors.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class ProductivityBreakdownCard extends StatelessWidget {
  final List<BreakdownItem> items;

  const ProductivityBreakdownCard({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return _DistributionCard(
      title: 'Productivity breakdown',
      subtitle: 'Your own rating of recorded activities',
      icon: Icons.bolt_rounded,
      items: items,
      emptyMessage: 'Productivity ratings will appear here.',
      preferredColors: const [
        DashboardColors.accentText,
        DashboardColors.warning,
        DashboardColors.negative,
      ],
    );
  }
}

class OutcomeBreakdownCard extends StatelessWidget {
  final List<BreakdownItem> items;

  const OutcomeBreakdownCard({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return _DistributionCard(
      title: 'Task outcomes',
      subtitle: 'How your recorded activities finished',
      icon: Icons.flag_outlined,
      items: items,
      emptyMessage: 'Task outcomes will appear here.',
      preferredColors: DashboardColors.chartColors,
    );
  }
}

class _DistributionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<BreakdownItem> items;
  final String emptyMessage;
  final List<Color> preferredColors;

  const _DistributionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.items,
    required this.emptyMessage,
    required this.preferredColors,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      child: items.isEmpty
          ? DashboardInlineEmpty(message: emptyMessage)
          : Column(
              children: items.asMap().entries.map((entry) {
                final item = entry.value;
                final color =
                    preferredColors[entry.key % preferredColors.length];

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == items.length - 1 ? 0 : 15,
                  ),
                  child: _DistributionRow(item: item, color: color),
                );
              }).toList(),
            ),
    );
  }
}

class _DistributionRow extends StatelessWidget {
  final BreakdownItem item;
  final Color color;

  const _DistributionRow({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 34,
          width: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            item.count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DashboardColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    formatPercentage(item.percentage),
                    style: const TextStyle(
                      color: DashboardColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: percentageFraction(item.percentage),
                  backgroundColor: DashboardColors.surfaceElevated,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MoodJourneyCard extends StatelessWidget {
  final MoodBreakdown mood;

  const MoodJourneyCard({super.key, required this.mood});

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      title: 'Mood journey',
      subtitle: 'How you felt after recorded activities',
      icon: Icons.sentiment_satisfied_alt_rounded,
      trailing: mood.totalCount == 0
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: DashboardColors.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${formatPercentage(mood.improvedPercentage)} improved',
                style: const TextStyle(
                  color: DashboardColors.accentText,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
      child: mood.totalCount == 0
          ? const DashboardInlineEmpty(
              message: 'Mood changes will appear here.',
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MoodMetric(
                        label: 'Improved',
                        count: mood.improvedCount,
                        icon: Icons.trending_up_rounded,
                        color: DashboardColors.accentText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MoodMetric(
                        label: 'Stable',
                        count: mood.stableCount,
                        icon: Icons.trending_flat_rounded,
                        color: DashboardColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MoodMetric(
                        label: 'Lower',
                        count: mood.declinedCount,
                        icon: Icons.trending_down_rounded,
                        color: DashboardColors.negative,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 9,
                    child: Row(children: _moodSegments(mood)),
                  ),
                ),
              ],
            ),
    );
  }

  List<Widget> _moodSegments(MoodBreakdown mood) {
    final segments = <Widget>[];

    if (mood.improvedCount > 0) {
      segments.add(
        Expanded(
          flex: mood.improvedCount,
          child: const ColoredBox(color: DashboardColors.accentText),
        ),
      );
    }
    if (mood.stableCount > 0) {
      segments.add(
        Expanded(
          flex: mood.stableCount,
          child: const ColoredBox(color: DashboardColors.primary),
        ),
      );
    }
    if (mood.declinedCount > 0) {
      segments.add(
        Expanded(
          flex: mood.declinedCount,
          child: const ColoredBox(color: DashboardColors.negative),
        ),
      );
    }

    return segments;
  }
}

class _MoodMetric extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _MoodMetric({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: DashboardColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 5),
          Text(
            count.toString(),
            style: const TextStyle(
              color: DashboardColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: DashboardColors.muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
