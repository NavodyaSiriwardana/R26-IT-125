import 'package:flutter/material.dart';

// Pure data for the mood light: which colour the bulb shows for a scan and
// what the Mood Support text says. No widgets and no network, so the rules are
// unit-tested. The thresholds are the same ones the backend uses to pick a mood
// state (mood_support.py): stress at or above 0.5 is stressed, stress at or
// above 0.3 or a sad score at or above 0.3 is uneasy, anything else is calm.

enum MoodLightLevel { calm, uneasy, stressed }

class MoodLightInfo {
  final MoodLightLevel level;

  /// Short word shown under the bulb, for example "CALM".
  final String word;

  /// The same word in normal case, for example "Calm".
  final String label;
  final Color color;
  const MoodLightInfo(this.level, this.word, this.label, this.color);
}

const moodLightGreen = Color(0xFF5DCAA5);
const moodLightAmber = Color(0xFFF2B84B);
const moodLightRed = Color(0xFFEF6B6B);

MoodLightLevel moodLightLevel({required double stress, double sad = 0}) {
  if (stress >= 0.5) return MoodLightLevel.stressed;
  if (stress >= 0.3 || sad >= 0.3) return MoodLightLevel.uneasy;
  return MoodLightLevel.calm;
}

/// The light for a mood state that the backend sent (`stressed`, `uneasy`,
/// `low`, `tired`, `calm`, `positive`).
MoodLightLevel moodLightLevelForState(String state) {
  switch (state) {
    case 'stressed':
      return MoodLightLevel.stressed;
    case 'uneasy':
    case 'low':
    case 'tired':
      return MoodLightLevel.uneasy;
    default:
      return MoodLightLevel.calm;
  }
}

MoodLightInfo moodLightInfo(MoodLightLevel level) {
  switch (level) {
    case MoodLightLevel.stressed:
      return const MoodLightInfo(
          MoodLightLevel.stressed, 'STRESSED', 'Stressed', moodLightRed);
    case MoodLightLevel.uneasy:
      return const MoodLightInfo(
          MoodLightLevel.uneasy, 'UNEASY', 'Uneasy', moodLightAmber);
    case MoodLightLevel.calm:
      return const MoodLightInfo(
          MoodLightLevel.calm, 'CALM', 'Calm', moodLightGreen);
  }
}

/// A plain sentence for the Mood Support card, matched to the light.
String moodLightText(MoodLightLevel level) {
  switch (level) {
    case MoodLightLevel.stressed:
      return 'Your expression showed strong stress signals. Slow breathing can '
          'help you settle.';
    case MoodLightLevel.uneasy:
      return 'Some stress signals showed in your expression. A short pause may '
          'help.';
    case MoodLightLevel.calm:
      return 'Your mood looks settled. Keep your routine going.';
  }
}

/// The reset is the main action when the light is amber or red, and a quiet
/// optional link when it is green.
bool moodLightNeedsReset(MoodLightLevel level) => level != MoodLightLevel.calm;

/// Breathing used when a reset starts from the scan screen (4-7-8, six rounds,
/// about two minutes). It matches the plan the backend sends.
const defaultBreathing = {'inhale': 4, 'hold': 7, 'exhale': 8, 'rounds': 6};

/// One simple thing a student can do now.
class MoodTip {
  final IconData icon;
  final String title;
  final String detail;
  const MoodTip(this.icon, this.title, this.detail);
}

/// Short, practical suggestions for the scan on screen. Calm gets none.
List<MoodTip> moodRecommendations(MoodLightLevel level) {
  const breathing = MoodTip(Icons.self_improvement_rounded,
      'Slow breathing, 2 minutes', 'Use the Mood Reset. It is the quickest way to settle.');
  const walk = MoodTip(Icons.directions_walk_rounded, 'Walk for 5 minutes',
      'Step away from the desk, ideally outside.');
  const water = MoodTip(Icons.water_drop_outlined, 'Drink some water',
      'Stress feels worse when you are dehydrated.');
  const diary = MoodTip(Icons.edit_note_rounded, 'Write one worry in your diary',
      'Naming one thing makes it smaller.');
  const talk = MoodTip(Icons.chat_bubble_outline_rounded,
      'Talk to someone you trust', 'A friend or a lecturer.');
  switch (level) {
    case MoodLightLevel.stressed:
      return const [breathing, walk, water, diary, talk];
    case MoodLightLevel.uneasy:
      return const [walk, water, diary];
    case MoodLightLevel.calm:
      return const [];
  }
}
