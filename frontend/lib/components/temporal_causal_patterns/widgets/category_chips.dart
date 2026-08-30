import 'package:flutter/material.dart';

class CategoryChips extends StatelessWidget {
  final String selected;
  final Function(String) onSelected;

  const CategoryChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const List<String> categories = [
    'Lecture', 'Self-study', 'Group work',
    'Assignment', 'Meeting', 'Internship',
    'Play', 'Trips', 'Entertainment',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((cat) {
        final isSelected = selected == cat;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(cat),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF8A73FF), Color(0xFF6E56E8)],
                      )
                    : null,
                color: isSelected ? null : const Color(0xFF13132A),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF9784FF)
                      : const Color(0xFF2a2a3a),
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF7B61FF).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFF9999bb),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
