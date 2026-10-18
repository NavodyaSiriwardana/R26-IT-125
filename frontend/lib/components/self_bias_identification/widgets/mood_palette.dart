import 'package:flutter/material.dart';

/// Highlight colours for the Mood Support / Mood Reset feature. Vivid on
/// purpose: each mood state has a clear hue so it reads at a glance on the
/// app's dark background.
class MoodPalette {
  static const violet = Color(0xFF7B6EFF);
  static const violetSoft = Color(0xFFB2A8FF);
  static const mint = Color(0xFF34F5C5);
  static const cyan = Color(0xFF22D3EE);
  static const coral = Color(0xFFFF5C7A);
  static const orange = Color(0xFFFF9A5C);
  static const amber = Color(0xFFFFC857);
  static const pink = Color(0xFFFF7AD9);
  static const blue = Color(0xFF60A5FA);

  /// Primary colour + gradient pair for a mood state from the backend.
  static Color forState(String state) {
    switch (state) {
      case 'stressed':
        return coral;
      case 'uneasy':
        return orange;
      case 'low':
        return blue;
      case 'tired':
        return amber;
      case 'positive':
        return mint;
      default:
        return cyan;
    }
  }

  static List<Color> gradientForState(String state) {
    switch (state) {
      case 'stressed':
        return const [coral, orange];
      case 'uneasy':
        return const [orange, amber];
      case 'low':
        return const [blue, violet];
      case 'tired':
        return const [amber, orange];
      case 'positive':
        return const [mint, cyan];
      default:
        return const [cyan, mint];
    }
  }

  static Color forKind(String kind) {
    switch (kind) {
      case 'break':
        return mint;
      case 'body':
        return violetSoft;
      case 'music':
        return cyan;
      case 'plan':
        return amber;
      case 'reflect':
        return pink;
      case 'rest':
        return blue;
      case 'social':
        return coral;
      default:
        return violet;
    }
  }

  static IconData iconForKind(String kind) {
    switch (kind) {
      case 'break':
        return Icons.directions_walk_rounded;
      case 'body':
        return Icons.self_improvement_rounded;
      case 'music':
        return Icons.headphones_rounded;
      case 'plan':
        return Icons.event_note_rounded;
      case 'reflect':
        return Icons.edit_note_rounded;
      case 'rest':
        return Icons.bedtime_rounded;
      case 'social':
        return Icons.forum_rounded;
      default:
        return Icons.spa_rounded;
    }
  }
}
