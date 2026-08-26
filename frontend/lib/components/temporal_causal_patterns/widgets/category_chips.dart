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
        return GestureDetector(
          onTap: () => onSelected(cat),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF7B61FF)
                  : const Color(0xFF13132A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF7B61FF)
                    : const Color(0xFF2a2a3a),
              ),
            ),
            child: Text(
              cat,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : const Color(0xFF9999bb),
                fontSize: 12,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}