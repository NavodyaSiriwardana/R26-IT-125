import 'package:flutter/material.dart';

class EmptyPatternsView extends StatelessWidget {
  const EmptyPatternsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFF7B61FF).withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFF7B61FF).withValues(alpha: 0.2)),
              ),
              child: const Icon(
                Icons.auto_graph_rounded,
                size: 40,
                color: Color(0xFF7B61FF),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No patterns yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Keep adding diary entries.\nPatterns appear after at least\n3 similar activity entries.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF7b7b9a),
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF7B61FF15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF7B61FF30)),
              ),
              child: const Text(
                'Add more entries to discover patterns',
                style: TextStyle(
                  color: Color(0xFF7B61FF),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}