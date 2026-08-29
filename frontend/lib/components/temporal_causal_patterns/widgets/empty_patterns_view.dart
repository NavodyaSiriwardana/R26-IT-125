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
            const Icon(
              Icons.auto_graph,
              size: 64,
              color: Color(0xFF2a2a3a),
            ),
            const SizedBox(height: 20),
            const Text(
              'No patterns yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
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