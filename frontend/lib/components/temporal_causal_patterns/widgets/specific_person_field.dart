import 'package:flutter/material.dart';

class SpecificPersonField extends StatelessWidget {
  final TextEditingController controller;
  final bool visible;

  const SpecificPersonField({
    super.key,
    required this.controller,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Row(
          children: const [
            Icon(Icons.person_outline,
                size: 14, color: Color(0xFF7B61FF)),
            SizedBox(width: 6),
            Text(
              'Specific person',
              style: TextStyle(
                color: Color(0xFF7B61FF),
                fontSize: 13,
              ),
            ),
            SizedBox(width: 6),
            Text(
              'shows when not Alone',
              style: TextStyle(
                color: Color(0xFF5a5a7a),
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'e.g. Kasun, Pasan, Dr. Silva',
            hintStyle: const TextStyle(
              color: Color(0xFF6B61AA), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF7B61FF15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF7B61FF50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF7B61FF50)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF7B61FF)),
            ),
          ),
        ),
      ],
    );
  }
}