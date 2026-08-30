import 'package:flutter/material.dart';

class ProductivityChips extends StatelessWidget {
  final String selected;
  final Function(String) onSelected;

  const ProductivityChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ['Low', 'Medium', 'High'].map((level) {
        final isSelected = selected == level;
        return Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onSelected(level),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 12),
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
                  children: [
                    Icon(Icons.bolt,
                        size: 16,
                        color: isSelected
                            ? const Color(0xFF7B61FF)
                            : const Color(0xFF6a6a86)),
                    const SizedBox(height: 3),
                    Text(
                      level,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF7B61FF)
                            : const Color(0xFF9999bb),
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}