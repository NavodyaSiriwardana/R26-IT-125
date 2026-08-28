import 'package:flutter/material.dart';

class PatternFilterChips extends StatelessWidget {
  final String selected;
  final Function(String) onSelected;

  const PatternFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const List<String> filters = [
    'All', 'Strong', 'Moderate', 'Cross-day'
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: filters.map((filter) {
          final isSelected = selected == filter;
          return GestureDetector(
            onTap: () => onSelected(filter),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF7B61FF)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF7B61FF)
                      : const Color(0xFF2a2a3a),
                ),
              ),
              child: Text(
                filter,
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
      ),
    );
  }
}