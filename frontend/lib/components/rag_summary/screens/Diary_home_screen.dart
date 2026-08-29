import 'package:flutter/material.dart';

import '../../../core/network/dio_client.dart';
import '../models/Diary_entry.dart';
import '../services/Rag_diary_service.dart';
import '../utils/diary_week_group.dart';
import '../widgets/diary_entry_detail_dialog.dart';
import 'Summary_result_screen.dart';
import '../../temporal_causal_patterns/screens/new_entry_screen.dart';

class DiaryHomeScreen extends StatefulWidget {
  final String userId;
  final RagDiaryService? service;

  const DiaryHomeScreen({
    super.key,
    this.userId = 'demo-user-001',
    this.service,
  });

  @override
  State<DiaryHomeScreen> createState() => _DiaryHomeScreenState();
}

class _DiaryHomeScreenState extends State<DiaryHomeScreen> {
  late final RagDiaryService _service;

  List<DiaryEntry> _entries = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RagDiaryService(DioClient());
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final entries = await _service.getDiaryEntries(
        userId: widget.userId,
        limit: 50,
      );

      if (!mounted) return;

      setState(() {
        _entries = entries;
        _isLoading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = 'Your diary could not be loaded right now. Please try again.';
      });
    }
  }

  Future<void> _openAddEntryScreen() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const NewEntryScreen(),
      ),
    );

    if (!mounted) return;

    await _loadEntries();
  }

  void _openSummaryScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SummaryResultScreen(userId: widget.userId),
      ),
    );
  }

  void _showEntry(DiaryEntry entry) {
    showDialog<void>(
      context: context,
      builder: (_) => DiaryEntryDetailDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final weekGroups = groupDiaryEntriesByWeek(_entries);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B14),
        elevation: 0,
        foregroundColor: const Color(0xFFEDEBFF),
        title: const Text(
          'My Diary',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddEntryScreen,
        backgroundColor: const Color(0xFF7F77DD),
        foregroundColor: const Color(0xFF0B0B14),
        icon: const Icon(Icons.edit_rounded),
        label: const Text(
          'New entry',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadEntries,
          color: const Color(0xFF7F77DD),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
            children: [
              _HeaderCard(
                entryCount: _entries.length,
                weekCount: weekGroups.length,
                onGenerateSummary: _entries.isEmpty ? null : _openSummaryScreen,
              ),
              const SizedBox(height: 22),
              if (_isLoading)
                const _LoadingBlock()
              else if (_error != null)
                _EmptyStateBlock(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not open your diary',
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: _loadEntries,
                )
              else if (_entries.isEmpty)
                _EmptyStateBlock(
                  icon: Icons.auto_stories_outlined,
                  title: 'Your diary starts here',
                  message:
                      'Capture your first activity, mood, or memorable moment. '
                      'Your weekly reflections will grow from there.',
                  actionLabel: 'Write first entry',
                  onAction: _openAddEntryScreen,
                )
              else ...[
                const Text(
                  'Your weeks',
                  style: TextStyle(
                    color: Color(0xFFEDEBFF),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Browse your entries one week at a time.',
                  style: TextStyle(
                    color: Color(0xFFB8B4D8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                ...weekGroups.map(
                  (group) =>
                      _DiaryWeekSection(group: group, onEntryTap: _showEntry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final int entryCount;
  final int weekCount;
  final VoidCallback? onGenerateSummary;

  const _HeaderCard({
    required this.entryCount,
    required this.weekCount,
    required this.onGenerateSummary,
  });

  @override
  Widget build(BuildContext context) {
    final entryLabel = entryCount == 1 ? 'entry' : 'entries';
    final weekLabel = weekCount == 1 ? 'week' : 'weeks';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3C3489), Color(0xFF181728)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF7F77DD)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7F77DD).withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your diary, week by week',
            style: TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            entryCount == 0
                ? 'A quiet space to notice what shaped your days.'
                : '$entryCount $entryLabel across $weekCount $weekLabel.',
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onGenerateSummary,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Reflect on my week'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D9E75),
                disabledBackgroundColor: const Color(0xFF403A78),
                foregroundColor: const Color(0xFF0B0B14),
                disabledForegroundColor: const Color(0xFFB8B4D8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryWeekSection extends StatelessWidget {
  final DiaryWeekGroup group;
  final ValueChanged<DiaryEntry> onEntryTap;

  const _DiaryWeekSection({required this.group, required this.onEntryTap});

  @override
  Widget build(BuildContext context) {
    final entryCount = group.entries.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF12111E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF302C55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 13),
            child: Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3C3489),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.calendar_view_week_rounded,
                    color: Color(0xFFEDEBFF),
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diaryWeekHeading(group),
                        style: const TextStyle(
                          color: Color(0xFFEDEBFF),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        diaryWeekRange(group),
                        style: const TextStyle(
                          color: Color(0xFFB8B4D8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B0B14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
                    style: const TextStyle(
                      color: Color(0xFF87F5D0),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...group.entries.map(
            (entry) =>
                _DiaryEntryCard(entry: entry, onTap: () => onEntryTap(entry)),
          ),
        ],
      ),
    );
  }
}

class _DiaryEntryCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onTap;

  const _DiaryEntryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF181728),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF403A78)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateBadge(entryDate: entry.entryDate),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.activityName,
                      style: const TextStyle(
                        color: Color(0xFFEDEBFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${entry.activityCategory}  •  '
                      '${entry.startTime}-${entry.endTime}  •  '
                      '${_formatDuration(entry.durationMinutes)}',
                      style: const TextStyle(
                        color: Color(0xFFB8B4D8),
                        fontSize: 11,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(
                          Icons.mood_rounded,
                          color: Color(0xFF87F5D0),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${entry.moodBefore} → ${entry.moodAfter}',
                            style: const TextStyle(
                              color: Color(0xFFEDEBFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _EntryTag(
                          icon: Icons.bolt_rounded,
                          label: entry.productivityLevel,
                          color: const Color(0xFF87F5D0),
                        ),
                        _EntryTag(
                          icon: Icons.flag_outlined,
                          label: entry.taskOutcome,
                          color: const Color(0xFFB8B4D8),
                        ),
                      ],
                    ),
                    if (entry.notes != null &&
                        entry.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 11),
                      Text(
                        entry.notes!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB8B4D8),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF7F77DD),
                  size: 21,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final String entryDate;

  const _DateBadge({required this.entryDate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 45,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3C3489),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7F77DD)),
      ),
      child: Column(
        children: [
          Text(
            diaryEntryDayName(entryDate),
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 8,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            diaryEntryDayNumber(entryDate),
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _EntryTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: CircularProgressIndicator(color: Color(0xFF7F77DD)),
      ),
    );
  }
}

class _EmptyStateBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyStateBlock({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF181728),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF403A78)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF7F77DD), size: 42),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB8B4D8),
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7F77DD),
              foregroundColor: const Color(0xFF0B0B14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
}
