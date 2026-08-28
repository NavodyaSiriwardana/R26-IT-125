import 'package:flutter/material.dart';

class HealthStatusChips extends StatelessWidget {
  final String selected;
  final Function(String) onSelected;

  const HealthStatusChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const List<String> statuses = [
    'Normal', 'Headache', 'Sleepy',
    'Anxious', 'Tired', 'Stomach ache',
    'Fever', 'Cold',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: statuses.map((status) {
        final isSelected = selected == status;
        return GestureDetector(
          onTap: () => onSelected(status),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFE24B4A22)
                  : const Color(0xFF13132A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFE24B4A)
                    : const Color(0xFF2a2a3a),
              ),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFFE24B4A)
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