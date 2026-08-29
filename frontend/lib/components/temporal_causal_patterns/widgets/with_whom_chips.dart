import 'package:flutter/material.dart';

class WithWhomChips extends StatelessWidget {
  final String selected;
  final Function(String) onSelected;

  const WithWhomChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const List<String> options = [
    'Alone', 'Group', 'Lecturer', 'Friends', 'Partner',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected == opt;
        return GestureDetector(
          onTap: () => onSelected(opt),
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
              opt,
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