import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/services/mood_heatmap.dart';

/// The 4 week mood heatmap: one rounded square per day, coloured by that day's
/// facial stress. Tapping a day shows the reason in a small popup above it
/// (below it for the first row, so it never leaves the card).
class MoodHeatmapCard extends StatefulWidget {
  final MoodHeatmap heatmap;
  const MoodHeatmapCard({super.key, required this.heatmap});

  static const good = Color(0xFF5DCAA5);
  static const moderate = Color(0xFFFFCB6B);
  static const low = Color(0xFFEF6B6B);

  @override
  State<MoodHeatmapCard> createState() => _MoodHeatmapCardState();
}

class _MoodHeatmapCardState extends State<MoodHeatmapCard> {
  static const _gap = 6.0;
  static const _headerHeight = 20.0;
  static const _popupWidth = 214.0;

  int? _selected;

  Color _colorOf(StressBand band) {
    switch (band) {
      case StressBand.low:
        return MoodHeatmapCard.good;
      case StressBand.moderate:
        return MoodHeatmapCard.moderate;
      case StressBand.high:
        return MoodHeatmapCard.low;
    }
  }

  String _moodWord(StressBand band) {
    switch (band) {
      case StressBand.low:
        return 'Good';
      case StressBand.moderate:
        return 'Moderate';
      case StressBand.high:
        return 'Low';
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = widget.heatmap;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MOOD HEATMAP',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.4),
                  letterSpacing: 1,
                ),
              ),
              const Text(
                'Last 4 weeks',
                style: TextStyle(fontSize: 12, color: MoodHeatmapCard.good),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _grid(map),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: const [
              _Legend(color: MoodHeatmapCard.good, label: 'Good'),
              _Legend(color: MoodHeatmapCard.moderate, label: 'Moderate'),
              _Legend(color: MoodHeatmapCard.low, label: 'Low'),
              _Legend(color: null, label: 'No scan'),
            ],
          ),
          if (map.isEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Scan today to start your map.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Scans', '${map.scans}'),
              const SizedBox(width: 10),
              _stat('Streak', map.streak == 1 ? '1 day' : '${map.streak} days'),
              const SizedBox(width: 10),
              _stat(
                'Avg stress',
                map.averageStress == null
                    ? '-'
                    : stressLabelShort(map.averageStress!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "Low", "Moderate" or "High", for the average.
  static String stressLabelShort(double stress) {
    switch (stressBand(stress)) {
      case StressBand.low:
        return 'Low';
      case StressBand.moderate:
        return 'Moderate';
      case StressBand.high:
        return 'High';
    }
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(MoodHeatmap map) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final rows = map.cells.length ~/ 7;
    return LayoutBuilder(builder: (context, c) {
      final cell = (c.maxWidth - _gap * 6) / 7;
      final gridHeight = _headerHeight + rows * (cell + _gap) - _gap;

      Widget popup() {
        final i = _selected!;
        final data = map.cells[i];
        final row = i ~/ 7;
        final col = i % 7;
        final centre = col * (cell + _gap) + cell / 2;
        final left = (centre - _popupWidth / 2).clamp(0.0, c.maxWidth - _popupWidth);
        final cellTop = _headerHeight + row * (cell + _gap);
        final above = row > 0;
        final band = data.band;
        final color = band == null ? Colors.white38 : _colorOf(band);
        final body = Container(
          key: const ValueKey('heat-popup'),
          width: _popupWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2430),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2C3847)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: band == null ? null : color,
                      borderRadius: BorderRadius.circular(3),
                      border: band == null
                          ? Border.all(color: Colors.white38)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      band == null
                          ? heatDayLabel(data)
                          : '${heatDayLabel(data)} · ${_moodWord(band)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                band == null ? heatReason(data) : 'Why: ${heatReason(data)}',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFFB7C0CC),
                ),
              ),
              if (band == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'A quick face check takes a few seconds.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFB7C0CC)),
                  ),
                ),
            ],
          ),
        );
        return Positioned(
          left: left,
          top: above ? cellTop - 8 : cellTop + cell + 8,
          child: above
              ? FractionalTranslation(translation: const Offset(0, -1), child: body)
              : body,
        );
      }

      return SizedBox(
        height: gridHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Row(
                    children: [
                      for (var d = 0; d < 7; d++) ...[
                        if (d > 0) const SizedBox(width: _gap),
                        SizedBox(
                          width: cell,
                          child: Center(
                            child: Text(
                              letters[d],
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                for (var r = 0; r < rows; r++) ...[
                  Row(
                    children: [
                      for (var d = 0; d < 7; d++) ...[
                        if (d > 0) const SizedBox(width: _gap),
                        _cell(map.cells[r * 7 + d], r * 7 + d, cell),
                      ],
                    ],
                  ),
                  if (r < rows - 1) const SizedBox(height: _gap),
                ],
              ],
            ),
            if (_selected != null) popup(),
          ],
        ),
      );
    });
  }

  Widget _cell(HeatCell data, int index, double size) {
    final band = data.band;
    final selected = _selected == index;
    return GestureDetector(
      key: ValueKey('heat-cell-$index'),
      behavior: HitTestBehavior.opaque,
      onTap: data.isFuture
          ? null
          : () => setState(() => _selected = selected ? null : index),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: band == null ? Colors.transparent : _colorOf(band),
          borderRadius: BorderRadius.circular(8),
          border: band == null
              ? Border.all(
                  color: Colors.white.withValues(alpha: data.isFuture ? 0.05 : 0.14),
                )
              : selected
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
        ),
        child: data.isToday
            ? Align(
                alignment: const Alignment(0, 0.6),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: band == null ? Colors.white54 : const Color(0xFF06231A),
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color? color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: color == null
                ? Border.all(color: Colors.white.withValues(alpha: 0.3))
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38)),
      ],
    );
  }
}
