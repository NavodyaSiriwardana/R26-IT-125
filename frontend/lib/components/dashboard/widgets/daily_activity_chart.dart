import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/dashboard_data.dart';
import '../theme/dashboard_colors.dart';
import 'dashboard_formatters.dart';
import 'dashboard_section_card.dart';

class DailyActivityChart extends StatelessWidget {
  final List<DailyActivityData> days;

  const DailyActivityChart({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final maximumMinutes = days.fold<int>(
      0,
      (maximum, day) => math.max(maximum, day.totalMinutes),
    );

    return DashboardSectionCard(
      title: 'Daily activity trend',
      subtitle: 'Logged time across your week',
      icon: Icons.bar_chart_rounded,
      child: days.isEmpty
          ? const DashboardInlineEmpty(
              message: 'Daily activity will appear after you add an entry.',
            )
          : SizedBox(
              height: 196,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: days
                    .map(
                      (day) => Expanded(
                        child: _DayBar(
                          day: day,
                          maximumMinutes: maximumMinutes,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final DailyActivityData day;
  final int maximumMinutes;

  const _DayBar({required this.day, required this.maximumMinutes});

  @override
  Widget build(BuildContext context) {
    final fraction = maximumMinutes == 0
        ? 0.0
        : (day.totalMinutes / maximumMinutes).clamp(0.0, 1.0).toDouble();
    final dayLabel = day.dayLabel.isEmpty ? '—' : day.dayLabel;

    return Tooltip(
      message:
          '${day.entryCount} ${day.entryCount == 1 ? 'activity' : 'activities'} · '
          '${formatLoggedTime(day.totalMinutes)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  day.totalMinutes == 0
                      ? '–'
                      : formatCompactMinutes(day.totalMinutes),
                  style: TextStyle(
                    color: day.totalMinutes == 0
                        ? DashboardColors.muted
                        : DashboardColors.text,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Container(
                width: 24,
                decoration: BoxDecoration(
                  color: DashboardColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: fraction,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            DashboardColors.primary,
                            DashboardColors.accent,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              dayLabel.length > 3 ? dayLabel.substring(0, 3) : dayLabel,
              style: const TextStyle(
                color: DashboardColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
