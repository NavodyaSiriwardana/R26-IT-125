import 'package:flutter/material.dart';
import 'new_entry_screen.dart';
import '../../task_prioritization/screens/main_navigation_screen.dart';

class TaskSelectionScreen extends StatelessWidget {
  const TaskSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'What would you like to do?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose how you want to manage your day',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF7b7b9a),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 48),

              // FUTURE TASK — routes to friend's component
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MainNavigationScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13132A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF7B61FF)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.upcoming,
                          color: Color(0xFF7B61FF), size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Future Task',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Plan and prioritize upcoming tasks',
                              style: TextStyle(
                                color: Color(0xFF7b7b9a),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          color: Color(0xFF7B61FF), size: 16),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // PAST TASK — routes to YOUR diary entry template
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NewEntryScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13132A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1DB954)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history_edu,
                          color: Color(0xFF1DB954), size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Past Task',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Log a diary entry & discover patterns',
                              style: TextStyle(
                                color: Color(0xFF7b7b9a),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          color: Color(0xFF1DB954), size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}