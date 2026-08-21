import 'package:flutter/material.dart';
import '../services/task_api_service.dart';

class TaskTestScreen extends StatefulWidget {
  const TaskTestScreen({super.key});

  @override
  State<TaskTestScreen> createState() => _TaskTestScreenState();
}

class _TaskTestScreenState extends State<TaskTestScreen> {
  List<dynamic> rankedTasks = [];

  Future<void> testApi() async {
    List<Map<String, dynamic>> tasks = [
      {
        "urgency": 0.9,
        "importance_score": 0.8,
        "deadline_hours": 10,
        "severity": 0.7,
        "cognitive_load": 0.6,
        "preparation_level": 0.5,
        "category": 1,
        "task_duration": 3,
        "snooze_count": 0,
        "postpone_count": 0,
        "completion_status": 0.0,
        "energy_level": 0.5,
        "focus_score": 0.5,
        "time_of_day": 2,
        "day_of_week": 3,
        "conflict_flag": 0,
        "recent_behavior_score": 0.0,
      },
    ];

    final response = await TaskApiService.rankTasks(tasks);

    setState(() {
      rankedTasks = response;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Task API Test")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: testApi,
              child: const Text("Test Backend"),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: rankedTasks.length,
                itemBuilder: (context, index) {
                  final task = rankedTasks[index];

                  return Card(
                    child: ListTile(
                      title: Text("Priority: ${task['priority']}"),
                      subtitle: Text(task['reason_tags'].toString()),
                      trailing: Text(task['pred_score'].toString()),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
