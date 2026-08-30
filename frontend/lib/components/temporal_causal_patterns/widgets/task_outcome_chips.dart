import 'package:flutter/material.dart';

class TaskOutcomeChips extends StatelessWidget {
  final String selected;
  final Function(String) onSelected;

  const TaskOutcomeChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const List<Map<String, String>> outcomes = [
    {'emoji': '✅', 'label': 'Completed'},
    {'emoji': '⏳', 'label': 'Partially Done'},
    {'emoji': '❌', 'label': 'Not Done'},
    {'emoji': '🔄', 'label': 'Postponed'},
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 3,
      children: outcomes.map((outcome) {
        final isSelected = selected == outcome['label'];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(outcome['label']!),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1DB95415)
                    : const Color(0xFF13132A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1DB954)
                      : const Color(0xFF2a2a3a),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF1DB954).withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
              children: [
                Text(outcome['emoji']!,
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    outcome['label']!,
                    style: TextStyle(
                      color: isSelected
                          ? const Color(0xFF1DB954)
                          : const Color(0xFF9999bb),
                      fontSize: 12,
                    ),
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