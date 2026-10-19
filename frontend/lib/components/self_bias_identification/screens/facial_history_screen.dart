import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_result_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/face_check_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/facial_capture_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/data_refresh.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';
import 'package:frontend/components/self_bias_identification/widgets/history_widgets.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';

/// Everything from the camera in one place: how stress moved over time, each
/// scan, and each Mood Reset with its before and after. Photos are never
/// stored, so scans appear as a face emoji and scores only.
class FacialHistoryScreen extends StatefulWidget {
  const FacialHistoryScreen({super.key});

  @override
  State<FacialHistoryScreen> createState() => _FacialHistoryScreenState();
}

class _FacialHistoryScreenState extends State<FacialHistoryScreen> {
  List<HistoryEntry> _entries = [];
  List<ResetRecord> _resets = [];
  bool _loading = true;
  bool _failed = false;

  int _tab = 0; // 0 = Scans, 1 = Resets
  int _range = 1; // 0 = 7 days, 1 = 30 days, 2 = all
  static const _rangeDays = <int?>[7, 30, null];

  @override
  void initState() {
    super.initState();
    DataRefresh.tick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DataRefresh.tick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await ApiService.fetchHistory(AppState.userId);
      var resets = <ResetRecord>[];
      try {
        resets = (await ApiService.fetchMoodResets(AppState.userId))
            .map(ResetRecord.new)
            .toList();
      } catch (_) {
        // The scans are still useful without the resets.
      }
      // Scans taken with no diary entry live in their own collection.
      var faceOnly = <Map<String, dynamic>>[];
      try {
        faceOnly = await ApiService.fetchFaceChecks(AppState.userId);
      } catch (_) {
        // The analysed scans are still useful without them.
      }
      if (!mounted) return;
      setState(() {
        _entries = [...rows, ...faceOnly].map(HistoryEntry.fromJson).toList();
        _resets = resets;
        _failed = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _entries.isEmpty && _resets.isEmpty;
      });
      AppToast.error(context, AppToast.friendlyError(e));
    }
  }

  List<HistoryEntry> get _allScans =>
      _entries.where((e) => e.hasFace).toList();

  List<HistoryEntry> get _scans {
    final now = DateTime.now();
    return sortEntries(
      _allScans
          .where((e) => withinDays(e.time, _rangeDays[_range], now))
          .toList(),
      HistorySort.newest,
    );
  }

  List<ResetRecord> get _rangeResets {
    final now = DateTime.now();
    final list = _resets
        .where((r) => withinDays(r.time, _rangeDays[_range], now))
        .toList();
    list.sort((a, b) {
      if (a.time == null) return 1;
      if (b.time == null) return -1;
      return b.time!.compareTo(a.time!);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
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
              'Facial History',
              style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            Text(
              _loading
                  ? 'Loading…'
                  : _failed
                      ? 'Could not load'
                      : '${_allScans.length} scans · ${_resets.length} resets',
              style: const TextStyle(fontSize: 14, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: _loading
          ? const HistorySkeleton()
          : RefreshIndicator(
              color: MoodPalette.mint,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: _children(),
              ),
            ),
    );
  }

  List<Widget> _children() {
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

    return [
      HistorySegments(
        labels: const ['Scans', 'Resets'],
        selected: _tab,
        mint: true,
        onChanged: (i) => setState(() => _tab = i),
      ),
      const SizedBox(height: 10),
      HistorySegments(
        labels: const ['7 days', '30 days', 'All'],
        selected: _range,
        onChanged: (i) => setState(() => _range = i),
      ),
      const SizedBox(height: 14),
      _tiles(),
      const SizedBox(height: 14),
      if (_tab == 0) ..._scansTab() else ..._resetsTab(),
    ];
  }

  // ---------------------------------------------------------------- tiles

  Widget _tiles() {
    final scans = _scans;
    final summary = summarizeResets(_rangeResets);
    final stresses = scans.map((e) => e.stress).whereType<double>().toList();
    final avgStress = stresses.isEmpty
        ? null
        : stresses.reduce((a, b) => a + b) / stresses.length;
    final delta = summary.averageDelta;

    Widget tile(String value, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile('${scans.length}', 'Scans', Colors.white),
        const SizedBox(width: 7),
        tile(
          avgStress == null ? '—' : '${(avgStress * 100).round()}%',
          'Avg stress',
          avgStress == null ? Colors.white54 : stressColor(avgStress),
        ),
        const SizedBox(width: 7),
        tile('${summary.count}', 'Resets', MoodPalette.violetSoft),
        const SizedBox(width: 7),
        tile(
          delta == null
              ? '—'
              : delta >= 0
                  ? '−${delta.round()}'
                  : '+${delta.abs().round()}',
          'Avg change',
          delta == null
              ? Colors.white54
              : delta >= 0
                  ? MoodPalette.mint
                  : MoodPalette.coral,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- scans

  List<Widget> _scansTab() {
    final scans = _scans;
    if (_allScans.isEmpty) {
      return [
        HistoryMessage(
          icon: Icons.face_retouching_natural_rounded,
          title: 'No scans yet',
          detail:
              'Take your first Expression Scan and your stress timeline will start here.',
          actionLabel: 'Start a scan',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FacialCaptureScreen()),
          ),
        ),
      ];
    }
    final resetByEntry = latestResetByEntry(_resets);
    final rangeNames = const ['the last 7 days', 'the last 30 days', 'all time'];
    return [
      HistoryCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'FACIAL STRESS OVER TIME',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  'Reset ▮',
                  style: TextStyle(fontSize: 12, color: MoodPalette.mint.withValues(alpha: 0.9)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (scans.length >= 2)
              StressTimeline(scans: scans, resets: _rangeResets)
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    scans.isEmpty
                        ? 'No scans in ${rangeNames[_range]}'
                        : 'One scan so far. A timeline needs two.',
                    style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.45)),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      if (scans.isNotEmpty) const HistoryGroupHeader(label: 'Scans, newest first'),
      for (final e in scans) _scanCard(e, resetByEntry[e.entryId]),
    ];
  }

  Widget _scanCard(HistoryEntry e, ResetRecord? reset) {
    final stress = e.stress ?? 0;
    final color = stressColor(stress);
    final emotion = e.dominantEmotion.isEmpty
        ? ''
        : e.dominantEmotion[0].toUpperCase() + e.dominantEmotion.substring(1);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HistoryCard(
        onTap: () => _showScan(e, reset),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(faceEmoji(stress, e.dominantEmotion),
                  style: const TextStyle(fontSize: 21)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stressLabel(stress)} · ${(stress * 100).round()}%',
                    style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (emotion.isNotEmpty) emotion,
                      dayGroup(e.time, DateTime.now()) == 'Today' ||
                              dayGroup(e.time, DateTime.now()) == 'Yesterday'
                          ? '${dayGroup(e.time, DateTime.now())} ${shortTime(e.time, DateTime.now())}'
                          : shortTime(e.time, DateTime.now()),
                    ].where((p) => p.trim().isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
            if (e.faceOnly || reset != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (e.faceOnly)
                    const HistoryPill(label: 'Face only', color: MoodPalette.violetSoft),
                  if (e.faceOnly && reset != null) const SizedBox(height: 4),
                  if (reset != null)
                    HistoryPill(label: resetBadge(reset), color: _outcomeColor(reset)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _outcomeColor(ResetRecord r) {
    switch (r.outcome) {
      case 'improved':
        return MoodPalette.mint;
      case 'worse':
        return MoodPalette.coral;
      case 'no_change':
        return MoodPalette.amber;
      default:
        return Colors.white54;
    }
  }

  void _showScan(HistoryEntry e, ResetRecord? reset) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF11161F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _ScanSheet(
        entry: e,
        reset: reset,
        onOpenAnalysis: () {
          Navigator.pop(sheetContext);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => e.faceOnly
                  ? FaceCheckScreen(
                      facial: e.facial ?? const {},
                      moodSupport: e.raw['mood_support'] is Map
                          ? Map<String, dynamic>.from(e.raw['mood_support'] as Map)
                          : const {},
                      entryId: e.entryId,
                      fromHistory: true,
                    )
                  : BiasResultScreen(result: e.raw),
            ),
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------- resets

  List<Widget> _resetsTab() {
    final resets = _rangeResets;
    if (_resets.isEmpty) {
      return const [
        HistoryMessage(
          icon: Icons.air_rounded,
          title: 'No resets yet',
          detail:
              'Start a Mood Reset from the Mood Support card on a stressed result. Your before and after will be kept here.',
        ),
      ];
    }
    final summary = summarizeResets(resets);
    return [
      if (summary.hasComparison) ...[_comparisonCard(summary), const SizedBox(height: 6)],
      if (resets.isEmpty)
        const HistoryMessage(
          icon: Icons.date_range_rounded,
          title: 'No resets in this range',
          detail: 'Try 30 days or All.',
        )
      else ...[
        const HistoryGroupHeader(label: 'Your resets, newest first'),
        for (final r in resets) _resetCard(r),
      ],
    ];
  }

  Widget _comparisonCard(ResetSummary s) {
    final b = s.breathingDelta ?? 0;
    final q = s.restDelta ?? 0;
    final top = [b.abs(), q.abs(), 1.0].reduce((a, c) => a > c ? a : c);

    Widget row(String label, double value, int n, Color color) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                child: Text(label,
                    style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.6))),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (value.abs() / top).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 62,
                child: Text(
                  value >= 0 ? '−${value.round()} pts' : '+${value.abs().round()} pts',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );

    return HistoryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AVERAGE CHANGE BY TYPE',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          row('Breathing', b, s.breathingCount ?? 0, MoodPalette.mint),
          row('Quiet rest', q, s.restCount ?? 0, MoodPalette.violetSoft),
          const SizedBox(height: 10),
          Text(
            'Your own ${s.count} resets (${s.breathingCount} breathing, ${s.restCount} quiet rest). A small sample, so treat it as a guide.',
            style: TextStyle(fontSize: 13, height: 1.45, color: Colors.white.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  Widget _resetCard(ResetRecord r) {
    final now = DateTime.now();
    final group = dayGroup(r.time, now);
    final when = group == 'Today' || group == 'Yesterday'
        ? '$group · ${shortTime(r.time, now)}'
        : shortTime(r.time, now);
    final delta = r.deltaPoints;
    final color = _outcomeColor(r);
    final deltaLabel = delta == null
        ? 'Not compared'
        : delta > 0
            ? '−$delta pts'
            : delta < 0
                ? '+${delta.abs()} pts'
                : '±0 pts';

    Widget pct(double? v) => Text(
          v == null ? '—' : '${(v * 100).round()}%',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: v == null ? Colors.white38 : stressColor(v),
          ),
        );

    final footer = <String>[
      if (r.selfBefore != null || r.selfAfter != null)
        'You rated ${r.selfBefore ?? '—'} → ${r.selfAfter ?? '—'}',
      if (r.rounds > 0) '${r.rounds} rounds',
      if (r.durationSeconds > 0)
        '${r.durationSeconds ~/ 60}:${(r.durationSeconds % 60).toString().padLeft(2, '0')}',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: HistoryCard(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(when, style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.55))),
                HistoryPill(
                  label: r.isQuietRest ? 'Quiet rest' : 'Breathing',
                  color: r.isQuietRest ? MoodPalette.violetSoft : MoodPalette.mint,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                pct(r.before),
                Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.35), size: 20),
                pct(r.after),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                HistoryPill(label: deltaLabel, color: color),
                Flexible(
                  child: Text(
                    footer.join(' · '),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Details of one scan, over the list.
class _ScanSheet extends StatelessWidget {
  final HistoryEntry entry;
  final ResetRecord? reset;
  final VoidCallback onOpenAnalysis;
  const _ScanSheet({
    required this.entry,
    required this.reset,
    required this.onOpenAnalysis,
  });

  @override
  Widget build(BuildContext context) {
    final stress = entry.stress ?? 0;
    final color = stressColor(stress);
    final now = DateTime.now();
    final scores = <String, double>{};
    final raw = entry.facial?['emotion_scores'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) scores[k.toString()] = v.toDouble();
      });
    }
    final top = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    const emotionColors = {
      'sad': MoodPalette.blue,
      'angry': MoodPalette.coral,
      'fear': MoodPalette.amber,
      'disgust': MoodPalette.pink,
      'neutral': MoodPalette.violetSoft,
      'happy': MoodPalette.mint,
      'surprise': MoodPalette.cyan,
    };
    final group = dayGroup(entry.time, now);
    final when = group == 'Today' || group == 'Yesterday'
        ? '$group, ${shortTime(entry.time, now)}'
        : shortTime(entry.time, now);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(faceEmoji(stress, entry.dominantEmotion),
                      style: const TextStyle(fontSize: 27)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${stressLabel(stress)} · ${(stress * 100).round()}%',
                        style: GoogleFonts.outfit(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      Text(
                        [if (when.isNotEmpty) when, if (entry.category.isNotEmpty) '${entry.category} entry']
                            .join(' · '),
                        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final e in top.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 62,
                      child: Text(
                        e.key[0].toUpperCase() + e.key.substring(1),
                        style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: e.value.clamp(0.0, 1.0),
                          minHeight: 7,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(
                            emotionColors[e.key] ?? MoodPalette.violet,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${(e.value * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if (reset != null) ...[
              const SizedBox(height: 4),
              HistoryPill(label: resetBadge(reset!), color: MoodPalette.mint),
            ],
            const SizedBox(height: 10),
            Text(
              'Your photo was not saved. Only these scores are kept.',
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onOpenAnalysis,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(colors: [MoodPalette.mint, MoodPalette.cyan]),
                ),
                child: Text(
                  entry.faceOnly ? 'View face check' : 'View full analysis',
                  style: GoogleFonts.outfit(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0A0E14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
