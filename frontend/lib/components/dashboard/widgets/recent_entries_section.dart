import 'package:flutter/material.dart';

import '../../rag_summary/models/Diary_entry.dart';
import '../../rag_summary/utils/diary_week_group.dart';
import '../theme/dashboard_colors.dart';
import 'dashboard_formatters.dart';
import 'dashboard_section_card.dart';

class RecentEntriesSection extends StatelessWidget {
  final List<DiaryEntry> entries;
  final VoidCallback? onViewAll;
  final ValueChanged<DiaryEntry>? onEntryTap;

  const RecentEntriesSection({
    super.key,
    required this.entries,
    this.onViewAll,
    this.onEntryTap,
  });

  @override
  Widget build(BuildContext context) {
    final weekGroups = groupDiaryEntriesByWeek(entries);

    return DashboardSectionCard(
      title: 'Recent diary entries',
      subtitle: 'A quick look at your latest weeks',
      icon: Icons.menu_book_rounded,
      trailing: onViewAll == null
          ? null
          : TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                foregroundColor: DashboardColors.accentText,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Open diary',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ),
      child: entries.isEmpty
          ? const DashboardInlineEmpty(
              message: 'Your recent diary entries will appear here.',
            )
          : Column(
              children: weekGroups.asMap().entries.map((groupEntry) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: groupEntry.key == weekGroups.length - 1 ? 0 : 16,
                  ),
                  child: _CompactWeekGroup(
                    group: groupEntry.value,
                    onEntryTap: onEntryTap,
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _CompactWeekGroup extends StatelessWidget {
  final DiaryWeekGroup group;
  final ValueChanged<DiaryEntry>? onEntryTap;

  const _CompactWeekGroup({required this.group, required this.onEntryTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, right: 2, bottom: 9),
          child: Row(
            children: [
              const Icon(
                Icons.calendar_today_rounded,
                color: DashboardColors.primary,
                size: 14,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  diaryWeekHeading(group),
                  style: const TextStyle(
                    color: DashboardColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                diaryWeekRange(group),
                style: const TextStyle(
                  color: DashboardColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...group.entries.asMap().entries.map((entry) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: entry.key == group.entries.length - 1 ? 0 : 10,
            ),
            child: _RecentEntryTile(
              entry: entry.value,
              onTap: onEntryTap == null ? null : () => onEntryTap!(entry.value),
            ),
          );
        }),
      ],
    );
  }
}

class _RecentEntryTile extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback? onTap;

  const _RecentEntryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DashboardColors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 46,
                width: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DashboardColors.primaryDark,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: DashboardColors.primary),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      diaryEntryDayName(entry.entryDate),
                      style: const TextStyle(
                        color: DashboardColors.muted,
                        fontSize: 7,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      diaryEntryDayNumber(entry.entryDate),
                      style: const TextStyle(
                        color: DashboardColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.activityName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DashboardColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.activityCategory}  •  '
                      '${entry.startTime}  •  '
                      '${formatLoggedTime(entry.durationMinutes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DashboardColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _EntryTag(
                          label: entry.productivityLevel,
                          color: DashboardColors.accentText,
                        ),
                        _EntryTag(
                          label: entry.taskOutcome,
                          color: DashboardColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: DashboardColors.muted,
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTag extends StatelessWidget {
  final String label;
  final Color color;

  const _EntryTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
