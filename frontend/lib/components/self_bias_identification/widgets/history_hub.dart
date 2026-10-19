import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_history_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/facial_history_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/data_refresh.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';

/// Two buttons that open the history pages, each with a one-line summary so
/// the student sees something before tapping. If the summary cannot be loaded
/// the buttons still work and simply show no numbers.
class HistoryHub extends StatefulWidget {
  const HistoryHub({super.key});

  @override
  State<HistoryHub> createState() => _HistoryHubState();
}

class _HistoryHubState extends State<HistoryHub> {
  List<HistoryEntry>? _entries;
  List<ResetRecord> _resets = [];
  List<HistoryEntry> _faceOnly = [];
  bool _loaded = false;

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
    List<HistoryEntry>? entries;
    var resets = <ResetRecord>[];
    try {
      entries = (await ApiService.fetchHistory(AppState.userId))
          .map(HistoryEntry.fromJson)
          .toList();
      resets = (await ApiService.fetchMoodResets(AppState.userId))
          .map(ResetRecord.new)
          .toList();
      // Face-only scans count as scans, but not as bias entries.
      _faceOnly = (await ApiService.fetchFaceChecks(AppState.userId))
          .map(HistoryEntry.fromJson)
          .toList();
    } catch (_) {
      // Numbers are a bonus; the buttons work without them.
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _resets = resets;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    String biasLine1 = '…';
    String biasLine2 = '';
    String faceLine1 = '…';
    String faceLine2 = '';
    if (_loaded) {
      if (entries == null) {
        biasLine1 = faceLine1 = 'Tap to open';
      } else {
        biasLine1 = entries.isEmpty
            ? 'No entries yet'
            : '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'}';
        biasLine2 = entries.isEmpty ? '' : 'Avg PAS ${averagePas(entries).round()}';

        final scans = [...entries.where((e) => e.hasFace), ..._faceOnly];
        final stresses = scans.map((e) => e.stress).whereType<double>().toList();
        faceLine1 = scans.isEmpty && _resets.isEmpty
            ? 'No scans yet'
            : '${scans.length} ${scans.length == 1 ? 'scan' : 'scans'} · ${_resets.length} ${_resets.length == 1 ? 'reset' : 'resets'}';
        faceLine2 = stresses.isEmpty
            ? ''
            : 'Avg stress ${(stresses.reduce((a, b) => a + b) / stresses.length * 100).round()}%';
      }
    }

    // No CrossAxisAlignment.stretch: this sits inside a scrolling list, where
    // the height is unbounded and a stretched Row cannot lay out. Both tiles
    // have the same three lines, so they come out the same height anyway.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _tile(
            key: const Key('history-hub-bias'),
            icon: Icons.balance_rounded,
            color: MoodPalette.violetSoft,
            title: 'Bias History',
            line1: biasLine1,
            line2: biasLine2,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BiasHistoryScreen()),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tile(
            key: const Key('history-hub-facial'),
            icon: Icons.face_retouching_natural_rounded,
            color: MoodPalette.mint,
            title: 'Facial History',
            line1: faceLine1,
            line2: faceLine2,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FacialHistoryScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required Key key,
    required IconData icon,
    required Color color,
    required String title,
    required String line1,
    required String line2,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.045),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                line1,
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
              ),
              Text(
                line2.isEmpty ? ' ' : line2,
                style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.45)),
              ),
              const SizedBox(height: 8),
              Text(
                'Open ›',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
