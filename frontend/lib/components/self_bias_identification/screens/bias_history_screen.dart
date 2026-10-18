import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_result_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/facial_capture_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/data_refresh.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';
import 'package:frontend/components/self_bias_identification/widgets/history_widgets.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';

/// Every analysis the student has run, grouped by day, searchable and
/// filterable. Replaces the plain "All Entries" list.
class BiasHistoryScreen extends StatefulWidget {
  const BiasHistoryScreen({super.key});

  @override
  State<BiasHistoryScreen> createState() => _BiasHistoryScreenState();
}

class _BiasHistoryScreenState extends State<BiasHistoryScreen> {
  List<HistoryEntry> _entries = [];
  Map<String, ResetRecord> _resets = {};
  bool _loading = true;
  bool _failed = false;

  final _search = TextEditingController();
  HistoryFilter _filter = HistoryFilter.all;
  HistorySort _sort = HistorySort.newest;

  @override
  void initState() {
    super.initState();
    DataRefresh.tick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DataRefresh.tick.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await ApiService.fetchHistory(AppState.userId);
      // Resets only add a badge to each card, so failing to load them is fine.
      var resets = <ResetRecord>[];
      try {
        resets = (await ApiService.fetchMoodResets(AppState.userId))
            .map(ResetRecord.new)
            .toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _entries = rows.map(HistoryEntry.fromJson).toList();
        _resets = latestResetByEntry(resets);
        _failed = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Keep what is already on screen; only a first load becomes a failure page.
        _failed = _entries.isEmpty;
      });
      AppToast.error(context, AppToast.friendlyError(e));
    }
  }

  List<HistoryEntry> get _shown => sortEntries(
        filterEntries(_entries, filter: _filter, query: _search.text),
        _sort,
      );

  bool get _filtering =>
      _filter != HistoryFilter.all || _search.text.trim().isNotEmpty;

  void _openEntry(HistoryEntry e) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BiasResultScreen(result: e.raw)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _loading || _failed ? <HistoryEntry>[] : _shown;
    final subtitle = _loading
        ? 'Loading…'
        : _failed
            ? 'Could not load'
            : _filtering
                ? '${shown.length} of ${_entries.length} entries'
                : '${_entries.length} entries · Avg PAS ${averagePas(_entries).round()}';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bias History',
              style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 14, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: _loading
          ? const HistorySkeleton()
          : RefreshIndicator(
              color: MoodPalette.violet,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: _children(shown),
              ),
            ),
    );
  }

  List<Widget> _children(List<HistoryEntry> shown) {
    if (_failed) {
      return const [
        PullHint(),
        HistoryMessage(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load your history',
          detail:
              'Check your connection. We will try again when you pull down, or the next time you open this page.',
        ),
      ];
    }
    if (_entries.isEmpty) {
      return [
        HistoryMessage(
          icon: Icons.history_rounded,
          title: 'No entries yet',
          detail: 'Run your first analysis and it will appear here.',
          actionLabel: 'Start your first entry',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FacialCaptureScreen()),
          ),
        ),
      ];
    }

    final counts = filterCounts(_entries);
    String label(String name, HistoryFilter f) => '$name ${counts[f]}';

    return [
      _searchField(),
      const SizedBox(height: 12),
      HistoryChips<HistoryFilter>(
        selected: _filter,
        onChanged: (f) => setState(() => _filter = f),
        items: [
          (HistoryFilter.all, label('All', HistoryFilter.all)),
          (HistoryFilter.accurate, label('Accurate', HistoryFilter.accurate)),
          (HistoryFilter.biased, label('Biased', HistoryFilter.biased)),
          (HistoryFilter.stress, label('Stress', HistoryFilter.stress)),
          (HistoryFilter.focus, label('Focus', HistoryFilter.focus)),
          (HistoryFilter.productivity, label('Productivity', HistoryFilter.productivity)),
          (HistoryFilter.context, label('Context', HistoryFilter.context)),
        ],
      ),
      const SizedBox(height: 10),
      _sortRow(shown),
      if (shown.isEmpty)
        HistoryMessage(
          icon: Icons.search_off_rounded,
          title: 'No matches',
          detail: 'Nothing fits this search and filter.',
          actionLabel: 'Clear filters',
          onAction: () => setState(() {
            _search.clear();
            _filter = HistoryFilter.all;
          }),
        )
      else if (_sort == HistorySort.newest)
        ..._grouped(shown)
      else ...[
        const SizedBox(height: 6),
        for (final e in shown) _card(e),
      ],
    ];
  }

  Widget _searchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: Colors.white.withValues(alpha: 0.4)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14, color: Colors.white),
              cursorColor: MoodPalette.violetSoft,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Search bias type or activity category',
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          if (_search.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(_search.clear),
              child: Icon(Icons.close_rounded, size: 18, color: Colors.white.withValues(alpha: 0.5)),
            ),
        ],
      ),
    );
  }

  Widget _sortRow(List<HistoryEntry> shown) {
    const labels = {
      HistorySort.newest: 'Newest first',
      HistorySort.lowestPas: 'Lowest PAS first',
      HistorySort.highestPas: 'Highest PAS first',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        PopupMenuButton<HistorySort>(
          tooltip: 'Sort',
          color: const Color(0xFF151B26),
          initialValue: _sort,
          onSelected: (s) => setState(() => _sort = s),
          itemBuilder: (_) => [
            for (final e in labels.entries)
              PopupMenuItem(
                value: e.key,
                child: Text(e.value, style: const TextStyle(color: Colors.white)),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '${labels[_sort]} ▾',
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ),
        if (shown.isNotEmpty)
          Text(
            'Avg PAS ${averagePas(shown).round()}',
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45)),
          ),
      ],
    );
  }

  List<Widget> _grouped(List<HistoryEntry> shown) {
    final now = DateTime.now();
    return [
      for (final g in groupByDay(shown, now)) ...[
        HistoryGroupHeader(
          label: g.key,
          trailing: '${g.value.length} ${g.value.length == 1 ? 'entry' : 'entries'}',
        ),
        for (final e in g.value) _card(e),
      ],
    ];
  }

  Widget _card(HistoryEntry e) {
    final now = DateTime.now();
    final reset = _resets[e.entryId];
    final resetColor = reset == null
        ? MoodPalette.mint
        : reset.outcome == 'improved'
            ? MoodPalette.mint
            : reset.outcome == 'worse'
                ? MoodPalette.coral
                : MoodPalette.amber;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HistoryCard(
        onTap: () => _openEntry(e),
        child: Row(
          children: [
            PasRing(score: e.pas),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    style: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  if (e.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      e.subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.55)),
                    ),
                  ],
                  if (reset != null) ...[
                    const SizedBox(height: 6),
                    HistoryPill(label: resetBadge(reset), color: resetColor),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (e.hasFace)
                  Text(faceEmoji(e.stress ?? 0, e.dominantEmotion),
                      style: const TextStyle(fontSize: 18, height: 1.1))
                else
                  Text('no scan',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.3))),
                const SizedBox(height: 6),
                Text(
                  shortTime(e.time, now),
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
