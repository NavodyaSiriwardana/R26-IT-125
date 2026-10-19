// Pure data for the "Claimed vs reality" cards on the home screen: what each
// card says, which colour it gets and the plain sentence that explains why.
// No widgets and no network, so every rule here is unit-tested.

enum RealityStatus { matches, differs, notChecked }

enum RealityVisual { none, map, lateTimeline, bars }

class RealityDetail {
  final String label;
  final String value;
  const RealityDetail(this.label, this.value);
}

class RealityCardData {
  final String key;
  final String title;
  final String subtitle;
  final RealityStatus status;
  final String claimedTitle;
  final String claimed;
  final String verifiedTitle;
  final String verified;
  final String why;
  final RealityVisual visual;
  final List<String> chips;
  final List<String> hitChips;
  final List<RealityDetail> details;

  /// Duration bars: label, minutes, maximum (the claimed minutes).
  final List<RealityBar> bars;

  /// For the late-entry timeline: hours between the activity and the entry.
  final double? lateHours;

  /// Where the phone was, for the real map. Null when there is no position.
  final double? lat;
  final double? lng;

  const RealityCardData({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.claimedTitle,
    required this.claimed,
    required this.verifiedTitle,
    required this.verified,
    required this.why,
    this.visual = RealityVisual.none,
    this.chips = const [],
    this.hitChips = const [],
    this.details = const [],
    this.bars = const [],
    this.lateHours,
    this.lat,
    this.lng,
  });
}

class RealityBar {
  final String label;
  final int minutes;
  final String kind; // claimed | verified | social
  const RealityBar(this.label, this.minutes, this.kind);
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String _str(Object? v) => (v ?? '').toString().trim();

int _int(Object? v) => (v as num?)?.round() ?? 0;

bool _isUnknown(String v) =>
    v.trim().isEmpty || v.trim().toLowerCase() == 'unknown';

const _campusTypes = {
  'university', 'school', 'secondary_school', 'primary_school',
};

const _typeLabels = {
  'university': 'University',
  'school': 'School',
  'library': 'Library nearby',
  'cafe': 'Cafe',
  'restaurant': 'Restaurant',
  'bakery': 'Bakery',
  'food': 'Food',
  'meal_takeaway': 'Takeaway',
  'store': 'Shop',
};

String _typeLabel(String t) =>
    _typeLabels[t] ??
    t.split('_').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

String _hours(double h) {
  if (h < 1) return '${(h * 60).round()} min';
  final whole = h.round();
  return whole == 1 ? '1 hour' : '$whole hours';
}

/// "10:35" from an ISO time, in the phone's own time zone. Empty when unknown.
String clockOf(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------------

RealityCardData locationCard(Map<String, dynamic> comparison) {
  final claimed = _str(comparison['claimed_location']);
  final detail = comparison['location_detail'];

  if (detail is! Map) {
    // Older results, and entries analysed from the live position.
    final actual = _str(comparison['actual_location']);
    final unchecked = comparison['location_checked'] == false ||
        _isUnknown(actual);
    final matches = !unchecked && claimed.toLowerCase() == actual.toLowerCase();
    return RealityCardData(
      key: 'location',
      title: 'Location',
      subtitle: unchecked ? 'Could not be checked' : 'Phone location',
      status: unchecked
          ? RealityStatus.notChecked
          : (matches ? RealityStatus.matches : RealityStatus.differs),
      claimedTitle: 'CLAIMED',
      claimed: claimed.isEmpty ? 'Unknown' : claimed,
      verifiedTitle: 'VERIFIED',
      verified: unchecked ? 'Not available' : actual,
      why: unchecked
          ? 'Your phone could not confirm where you were, so this is left out and does not lower your score.'
          : (matches
              ? 'Your phone was at $actual.'
              : 'Your phone was at $actual, not $claimed.'),
    );
  }

  final d = _map(detail);
  final checked = d['checked'] == true;
  final match = d['match'] == true;
  final reason = _str(d['reason']);
  final source = _str(d['source']);
  final label = _str(d['label']);
  final types = [for (final t in (d['place_types'] as List? ?? [])) _str(t)];
  final accuracy = (d['accuracy_m'] as num?)?.toDouble();
  final age = (d['age_at_capture_hours'] as num?)?.toDouble();
  final clock = clockOf(_str(d['captured_at']));

  final status = !checked
      ? RealityStatus.notChecked
      : (match ? RealityStatus.matches : RealityStatus.differs);

  final onCampus = types.any(_campusTypes.contains);
  String why;
  if (!checked) {
    switch (reason) {
      case 'late_entry':
        final when = age == null ? 'much later' : '${_hours(age)} after the activity';
        why = 'You wrote this entry $when, so we cannot tell where you were. '
            'It is left out and does not lower your score.';
      case 'no_capture':
        why = 'No location was captured when you wrote this entry (location off '
            'or no permission). It is left out of your score.';
      case 'no_place_data':
        why = 'No named place was found near your phone, so the claim could not '
            'be checked. It is left out of your score.';
      case 'cannot_verify_home':
        why = 'Being at home cannot be checked from the map, so it is left out '
            'of your score.';
      default:
        why = 'This entry gives no place that can be checked, so it is left out '
            'of your score.';
    }
  } else if (source == 'saved_place') {
    why = match
        ? 'When you wrote this entry your phone was at $label, a place you saved.'
        : 'When you wrote this entry your phone was at $label, a place you saved, '
            'not at $claimed.';
  } else if (match) {
    final where = onCampus ? 'on the university campus' : 'near $label';
    why = 'When you wrote this entry you were $where. That fits the $claimed.';
  } else if (claimed.toLowerCase() == 'home') {
    why = 'When you wrote this entry your phone was at ${label.isEmpty ? 'the campus' : label}, '
        'not at home.';
  } else {
    why = 'When you wrote this entry your phone was near $label. '
        'No $claimed was found within 100 m.';
  }

  final details = <RealityDetail>[
    if (clock.isNotEmpty)
      RealityDetail('Captured', age == null ? clock : '$clock (${_hours(age)} after the activity)'),
    if (types.isNotEmpty)
      RealityDetail('Place types', types.map(_typeLabel).join(', ')),
    if (accuracy != null) RealityDetail('GPS accuracy', '± ${accuracy.round()} m'),
    if (checked)
      RealityDetail(
        'Checked by',
        source == 'saved_place' ? 'A place you saved' : 'Places near your phone',
      ),
  ];

  final chips = <String>[];
  final hits = <String>[];
  if (source == 'nearby_places') {
    for (final t in types.take(4)) {
      chips.add(_typeLabel(t));
      if (checked && match) hits.add(_typeLabel(t));
    }
  }

  return RealityCardData(
    key: 'location',
    title: 'Location',
    subtitle: !checked
        ? 'Could not be checked'
        : (clock.isEmpty ? 'Checked automatically' : 'Checked at $clock · auto'),
    status: status,
    claimedTitle: 'CLAIMED',
    claimed: claimed.isEmpty ? 'Unknown' : claimed,
    verifiedTitle: 'VERIFIED',
    verified: !checked ? 'Not available' : (label.isEmpty ? 'Nearby' : label),
    why: why,
    visual: !checked
        ? (reason == 'late_entry' ? RealityVisual.lateTimeline : RealityVisual.none)
        : (source == 'nearby_places' || source == 'saved_place'
            ? RealityVisual.map
            : RealityVisual.none),
    chips: chips,
    hitChips: hits,
    details: details,
    lateHours: reason == 'late_entry' ? age : null,
    lat: (d['lat'] as num?)?.toDouble(),
    lng: (d['lng'] as num?)?.toDouble(),
  );
}

// ---------------------------------------------------------------------------
// Study duration
// ---------------------------------------------------------------------------

String formatMinutes(int minutes) {
  if (minutes >= 60) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }
  return '$minutes min';
}

RealityCardData durationCard(Map<String, dynamic> comparison) {
  final claimed = _int(comparison['claimed_duration']);
  final verified = _int(comparison['verified_educational']);
  final social = _int(comparison['social_media_minutes']);
  final isStudy = comparison['is_study_category'] != false;
  final checked = isStudy && claimed > 0 && comparison['duration_checked'] != false;

  if (!checked) {
    return RealityCardData(
      key: 'duration',
      title: 'Study duration',
      subtitle: 'From phone app usage',
      status: RealityStatus.notChecked,
      claimedTitle: 'YOU SAID',
      claimed: claimed > 0 ? formatMinutes(claimed) : 'Unknown',
      verifiedTitle: 'VERIFIED',
      verified: 'Not available',
      why: isStudy
          ? 'This entry gives no study time to compare, so it is left out of your score.'
          : 'This was not a study activity, so phone study time is not compared. '
              'It is left out of your score.',
    );
  }

  final ratio = (verified / claimed).clamp(0.0, 1.0);
  // The same 80% line the score uses for "a good match".
  final differs = ratio < 0.8;

  final pct = (ratio * 100).round();
  final why = differs
      ? 'Your phone shows ${formatMinutes(verified)} in study apps, which is $pct% '
          'of the time you claimed.${social > 0 ? ' About ${formatMinutes(social)} went to social media.' : ''}'
      : 'Your phone shows ${formatMinutes(verified)} in study apps. That is $pct% '
          'of the time you claimed.';

  return RealityCardData(
    key: 'duration',
    title: 'Study duration',
    subtitle: 'From phone app usage',
    status: differs ? RealityStatus.differs : RealityStatus.matches,
    claimedTitle: 'YOU SAID',
    claimed: formatMinutes(claimed),
    verifiedTitle: 'VERIFIED',
    verified: formatMinutes(verified),
    why: why,
    visual: RealityVisual.bars,
    bars: [
      RealityBar('You said', claimed, 'claimed'),
      RealityBar('Verified study apps', verified, 'verified'),
      if (social > 0) RealityBar('Social media', social, 'social'),
    ],
    details: [
      if (_map(comparison['educational_breakdown']).isNotEmpty)
        RealityDetail('Study apps', _topApps(_map(comparison['educational_breakdown']))),
      if (_map(comparison['social_media_breakdown']).isNotEmpty)
        RealityDetail('Distractions', _topApps(_map(comparison['social_media_breakdown']))),
    ],
  );
}

String _topApps(Map<String, dynamic> breakdown) {
  final entries = breakdown.entries.toList()
    ..sort((a, b) => ((b.value as num?) ?? 0).compareTo((a.value as num?) ?? 0));
  return entries
      .take(2)
      .map((e) => '${e.key} · ${formatMinutes(((e.value as num?) ?? 0).round())}')
      .join(', ');
}

// ---------------------------------------------------------------------------
// Mood shift
// ---------------------------------------------------------------------------

RealityCardData moodCard(Map<String, dynamic> comparison) {
  final before = _str(comparison['mood_before']);
  final after = _str(comparison['mood_after']);
  final declined = comparison['mood_declined'] == true;
  final face = _map(comparison['facial_emotion']);
  final hasFace = face['status'] == 'success';
  final stress = hasFace ? (face['stress_indicator'] as num?)?.toDouble() : null;

  final unknown = _isUnknown(after);
  final status = unknown
      ? RealityStatus.notChecked
      : (declined ? RealityStatus.differs : RealityStatus.matches);

  String why;
  if (unknown) {
    why = 'No mood was reported after this activity.';
  } else if (declined) {
    why = 'Your mood dropped from $before to $after during this activity.';
  } else {
    why = 'Your mood stayed steady or improved: $before to $after.';
  }
  if (stress != null) {
    why += ' Your face scan showed a stress signal of ${(stress * 100).round()}% '
        '(an estimate, not a medical result).';
  }

  return RealityCardData(
    key: 'mood',
    title: 'Mood shift',
    subtitle: hasFace ? 'Your report and the face scan' : 'Your report',
    status: status,
    claimedTitle: 'BEFORE',
    claimed: before.isEmpty ? 'Unknown' : before,
    verifiedTitle: 'AFTER',
    verified: after.isEmpty ? 'Unknown' : after,
    why: why,
  );
}

// ---------------------------------------------------------------------------
// Calendar
// ---------------------------------------------------------------------------

RealityCardData? calendarCard(Map<String, dynamic> comparison) {
  // Only when the calendar was actually read.
  if (comparison['calendar_checked'] != true) return null;
  final found = comparison['calendar_match'] == 1;
  return RealityCardData(
    key: 'calendar',
    title: 'Calendar',
    subtitle: 'Your phone calendar',
    status: found ? RealityStatus.matches : RealityStatus.differs,
    claimedTitle: 'CLAIMED',
    claimed: 'A scheduled activity',
    verifiedTitle: 'VERIFIED',
    verified: found ? 'Event found' : 'No event',
    why: found
        ? 'There is a calendar event at that time.'
        : 'There is no calendar event at that time.',
  );
}

/// The cards for one analysed entry, in the order they are shown.
List<RealityCardData> realityCards(Map<String, dynamic> comparison) => [
      locationCard(comparison),
      durationCard(comparison),
      ?calendarCard(comparison),
      moodCard(comparison),
    ];
