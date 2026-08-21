import 'package:flutter/material.dart';

import 'task_list_screen.dart';
import 'daily_plan_screen.dart';
import 'productivity_dashboard_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    TaskListScreen(),
    DailyPlanScreen(),
    ProductivityDashboardScreen(),
  ];

  void _selectScreen(int index) {
    if (_selectedIndex == index) return;

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectScreen,
        backgroundColor: const Color(0xFF17141C),
        indicatorColor: Colors.deepPurpleAccent.withOpacity(0.22),
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            selectedIcon: Icon(
              Icons.checklist_rounded,
              color: Colors.deepPurpleAccent,
            ),
            label: "Tasks",
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(
              Icons.calendar_month_rounded,
              color: Colors.deepPurpleAccent,
            ),
            label: "Daily Plan",
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(
              Icons.insights_rounded,
              color: Colors.deepPurpleAccent,
            ),
            label: "Insights",
          ),
        ],
      ),
    );
  }
}
