import 'package:flutter/material.dart';

class MoodSelector extends StatelessWidget {
  final String selected;
  final Function(String) onSelected;

  const MoodSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const List<Map<String, String>> moods = [
    {'emoji': '😊', 'label': 'Happy'},
    {'emoji': '⚡', 'label': 'Motivated'},
    {'emoji': '😐', 'label': 'Normal'},
    {'emoji': '😰', 'label': 'Stressed'},
    {'emoji': '😫', 'label': 'Tired'},
    {'emoji': '😑', 'label': 'Bored'},
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.2,
      children: moods.map((mood) {
        final isSelected = selected == mood['label'];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(mood['label']!),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF7B61FF15)
                    : const Color(0xFF13132A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF7B61FF)
                      : const Color(0xFF2a2a3a),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF7B61FF).withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(mood['emoji']!,
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 3),
                Text(
                  mood['label']!,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFFc0b0ff)
                        : const Color(0xFF9999bb),
                    fontSize: 11,
                  ),
                ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}