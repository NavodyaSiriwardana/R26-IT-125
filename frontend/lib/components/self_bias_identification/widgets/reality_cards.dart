import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/reality_data.dart';

/// The "Claimed vs reality" cards: one card for each thing the student claimed,
/// with the verdict, the two values side by side, a plain sentence saying why
/// and, for some cards, a small picture and a "Why this result" section.
class RealityCardsSection extends StatelessWidget {
  final Map<String, dynamic> comparison;
  const RealityCardsSection({super.key, required this.comparison});

  @override
  Widget build(BuildContext context) {
    final cards = realityCards(comparison);
    return Column(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          RealityCard(data: cards[i]),
        ],
      ],
    );
  }
}

const _green = Color(0xFF5DCAA5);
const _red = Color(0xFFEF6B6B);
const _amber = Color(0xFFF2B84B);
const _cyan = Color(0xFF38C6E0);
const _cardBg = Color(0xFF0D131D);
const _inner = Color(0xFF121A26);

Color statusColor(RealityStatus s) {
  switch (s) {
    case RealityStatus.matches:
      return _green;
    case RealityStatus.differs:
      return _red;
    case RealityStatus.notChecked:
      return _amber;
  }
}

String statusText(RealityStatus s) {
  switch (s) {
    case RealityStatus.matches:
      return 'Matches';
    case RealityStatus.differs:
      return 'Differs';
    case RealityStatus.notChecked:
      return 'Not checked';
  }
}

IconData _iconFor(String key) {
  switch (key) {
    case 'location':
      return Icons.place_rounded;
    case 'duration':
      return Icons.timer_rounded;
    case 'calendar':
      return Icons.event_rounded;
    default:
      return Icons.mood_rounded;
  }
}

class RealityCard extends StatefulWidget {
  final RealityCardData data;
  const RealityCard({super.key, required this.data});

  /// Draw the real Google map when there is a position and the platform has
  /// one. Tests switch this off (no platform view there); everything else
  /// falls back to the painted map.
  static bool useRealMap = true;

  static bool get _platformHasMap =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<RealityCard> createState() => _RealityCardState();
}

class _RealityCardState extends State<RealityCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final color = statusColor(d.status);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        key: Key('reality-${d.key}'),
        decoration: BoxDecoration(
          color: _cardBg,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            // The coloured edge is a separate bar: a rounded box cannot have a
            // different colour on one side.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: color),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(d, color),
                  if (d.visual != RealityVisual.none) ...[
                    const SizedBox(height: 12),
                    _visual(d, color),
                  ],
                  if (d.hitChips.isNotEmpty || d.chips.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in d.chips) _chip(c, d.hitChips.contains(c)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _values(d, color),
                  const SizedBox(height: 12),
                  Text(
                    d.why,
                    key: Key('reality-why-${d.key}'),
                    style: const TextStyle(
                      color: Color(0xFFC5CED9),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  if (d.details.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      key: Key('reality-more-${d.key}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _open = !_open),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Why this result',
                              style: TextStyle(
                                color: _cyan,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(
                              _open
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: _cyan,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_open) _details(d),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(RealityCardData d, Color color) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(_iconFor(d.key), size: 19, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.title,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                d.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          key: Key('reality-pill-${d.key}'),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            statusText(d.status),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _visual(RealityCardData d, Color color) {
    switch (d.visual) {
      case RealityVisual.map:
        return _mapFor(d, color);
      case RealityVisual.lateTimeline:
        return _lateTimeline(d.lateHours);
      case RealityVisual.bars:
        return _bars(d);
      case RealityVisual.none:
        return const SizedBox.shrink();
    }
  }

  Widget _mapFor(RealityCardData d, Color color) {
    final lat = d.lat, lng = d.lng;
    if (RealityCard.useRealMap &&
        RealityCard._platformHasMap &&
        lat != null &&
        lng != null) {
      return _realMap(lat, lng, color);
    }
    return _miniMap(color);
  }

  /// A small, still Google map: the position, the 100 m check radius and
  /// nothing to tap, so scrolling the page is never caught by the map.
  Widget _realMap(double lat, double lng, Color color) {
    final target = LatLng(lat, lng);
    return Container(
      key: const Key('reality-real-map'),
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            IgnorePointer(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: target, zoom: 16.3),
                liteModeEnabled: true,
                style: _darkMapStyle,
                zoomControlsEnabled: false,
                zoomGesturesEnabled: false,
                scrollGesturesEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
                compassEnabled: false,
                circles: {
                  Circle(
                    circleId: const CircleId('check-radius'),
                    center: target,
                    radius: 100,
                    fillColor: color.withValues(alpha: 0.16),
                    strokeColor: color,
                    strokeWidth: 2,
                  ),
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('phone'),
                    position: target,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      color == _green
                          ? BitmapDescriptor.hueGreen
                          : (color == _red
                              ? BitmapDescriptor.hueRed
                              : BitmapDescriptor.hueOrange),
                    ),
                  ),
                },
              ),
            ),
            const Positioned(
              left: 10,
              bottom: 8,
              child: Text(
                '100 m check radius',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniMap(Color color) {
    return Container(
      height: 118,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1018),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CustomPaint(
          key: const Key('reality-map'),
          painter: _MiniMapPainter(color),
          child: const Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '100 m check radius',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lateTimeline(double? hours) {
    final late = hours == null ? 'later' : '${hours.round()} h later';
    return SizedBox(
      key: const Key('reality-late-timeline'),
      height: 50,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 22,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            Positioned(
              left: w * 0.05,
              top: 22,
              child: Container(
                width: w * 0.28,
                height: 6,
                decoration: BoxDecoration(
                  color: _cyan,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            _dot(w * 0.33, _cyan),
            _dot(w * 0.86, _amber),
            Positioned(
              left: w * 0.05,
              top: 0,
              child: const Text('Activity',
                  style: TextStyle(color: Colors.white54, fontSize: 10)),
            ),
            Positioned(
              left: w * 0.33 - 24,
              top: 34,
              child: const Text('Activity ended',
                  style: TextStyle(color: Colors.white54, fontSize: 10)),
            ),
            Positioned(
              right: 0,
              top: 34,
              child: Text('Entry written $late',
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ),
          ],
        );
      }),
    );
  }

  Widget _dot(double x, Color color) => Positioned(
        left: x - 9,
        top: 16,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF070B12), width: 3),
          ),
        ),
      );

  Widget _bars(RealityCardData d) {
    final max = d.bars.fold<int>(1, (m, b) => b.minutes > m ? b.minutes : m);
    return Column(
      key: const Key('reality-bars'),
      children: [
        for (final b in d.bars)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(b.label,
                        style: const TextStyle(
                            color: Color(0xFFB7C0CC), fontSize: 12.5)),
                    Text(formatMinutes(b.minutes),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: LinearProgressIndicator(
                    value: (b.minutes / max).clamp(0.0, 1.0),
                    minHeight: 9,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(
                      b.kind == 'claimed'
                          ? _cyan
                          : (b.kind == 'social' ? _amber : statusColor(d.status)),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chip(String text, bool hit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: hit ? _green.withValues(alpha: 0.14) : _inner,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hit ? _green.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: hit ? _green : const Color(0xFFB7C0CC),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _values(RealityCardData d, Color color) {
    Widget box(String title, String value, Color valueColor) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _inner,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? 'Unknown' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: valueColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        box(d.claimedTitle, d.claimed, _cyan),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('→', style: TextStyle(color: Colors.white38, fontSize: 18)),
        ),
        box(d.verifiedTitle, d.verified, color),
      ],
    );
  }

  Widget _details(RealityCardData d) {
    return Container(
      key: Key('reality-details-${d.key}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        children: [
          for (final r in d.details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(r.label,
                        style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                  ),
                  Expanded(
                    child: Text(r.value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: Color(0xFFD7DEE7), fontSize: 12.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const _darkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#0f1722"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a97a8"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0f1722"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1d2a3b"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0a1a2b"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#142030"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#10281f"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]}
]''';

/// A quiet street map: grid, a road, the check radius and a pin.
class _MiniMapPainter extends CustomPainter {
  final Color color;
  const _MiniMapPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF16202D)
      ..strokeWidth = 1;
    for (var x = size.width * 0.18; x < size.width; x += size.width * 0.2) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = size.height * 0.25; y < size.height; y += size.height * 0.28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final road = Path()
      ..moveTo(0, size.height * 0.75)
      ..cubicTo(size.width * 0.2, size.height * 0.6, size.width * 0.38,
          size.height * 0.82, size.width * 0.6, size.height * 0.52)
      ..cubicTo(size.width * 0.78, size.height * 0.3, size.width * 0.9,
          size.height * 0.45, size.width, size.height * 0.4);
    canvas.drawPath(
      road,
      Paint()
        ..color = const Color(0xFF1B2A3B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );

    final c = Offset(size.width / 2, size.height * 0.5);
    canvas.drawCircle(c, size.height * 0.4,
        Paint()..color = color.withValues(alpha: 0.1));
    final ring = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    // A dashed ring for the radius.
    const dashes = 36;
    final r = size.height * 0.4;
    for (var i = 0; i < dashes; i += 2) {
      final a0 = i / dashes * 6.2831853;
      final a1 = (i + 1) / dashes * 6.2831853;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, a1 - a0, false, ring);
    }
    canvas.drawCircle(c, 12, Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawCircle(c, 6.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter old) => old.color != color;
}
