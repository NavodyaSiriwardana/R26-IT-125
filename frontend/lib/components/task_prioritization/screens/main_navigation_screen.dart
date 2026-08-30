import 'dart:async';

import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import 'daily_plan_screen.dart';
import 'productivity_dashboard_screen.dart';
import 'task_list_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final ValueNotifier<String?> _taskToReveal = ValueNotifier<String?>(null);

  late final PageController _pageController;

  late final List<Widget> _screens;

  StreamSubscription<String>? _notificationTapSubscription;

  int _selectedIndex = 0;

  bool _pageTransitionInProgress = false;

  @override
  void initState() {
    super.initState();

    _pageController = PageController(initialPage: _selectedIndex);

    _screens = [
      _KeepAlivePage(child: TaskListScreen(taskToReveal: _taskToReveal)),
      const _KeepAlivePage(child: DailyPlanScreen()),
      const _KeepAlivePage(child: ProductivityDashboardScreen()),
    ];

    _notificationTapSubscription = NotificationService
        .instance
        .notificationTapStream
        .listen(_handleNotificationPayload);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launchPayload = NotificationService.instance.takeLaunchPayload();

      if (launchPayload != null) {
        _handleNotificationPayload(launchPayload);
      }
    });
  }

  @override
  void dispose() {
    _notificationTapSubscription?.cancel();
    _taskToReveal.dispose();
    _pageController.dispose();

    super.dispose();
  }

  void _handleNotificationPayload(String payload) {
    if (!payload.startsWith('task:')) {
      debugPrint(
        'Ignored unsupported notification payload: '
        '$payload',
      );

      return;
    }

    final firstSection = payload.split('|').first;

    final taskId = firstSection.substring('task:'.length);

    if (taskId.isEmpty) {
      debugPrint('Notification payload did not contain a task ID.');

      return;
    }

    debugPrint(
      'Opening Tasks tab for notification task: '
      '$taskId',
    );

    unawaited(_openNotificationTask(taskId));
  }

  Future<void> _openNotificationTask(String taskId) async {
    if (!mounted) {
      return;
    }

    if (_selectedIndex != 0) {
      await _selectScreen(0);
    }

    if (!mounted) {
      return;
    }

    /*
     * Trigger the reveal only after the Tasks page has become
     * visible. Resetting the value allows the same notification
     * task to be opened more than once.
     */
    _taskToReveal.value = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _taskToReveal.value = taskId;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Opened your task reminder.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _selectScreen(int index) async {
    if (index < 0 || index >= _screens.length) {
      return;
    }

    if (_selectedIndex == index || _pageTransitionInProgress) {
      return;
    }

    _pageTransitionInProgress = true;

    setState(() {
      _selectedIndex = index;
    });

    try {
      if (!_pageController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_pageController.hasClients) {
            return;
          }

          _pageController.jumpToPage(index);
        });

        return;
      }

      await _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _pageTransitionInProgress = false;
    }
  }

  void _handlePageChanged(int index) {
    if (!mounted || _selectedIndex == index) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,

        // Navigation is controlled by the bottom bar.
        // This prevents accidental horizontal movement while
        // users interact with charts and task cards.
        physics: const NeverScrollableScrollPhysics(),

        onPageChanged: _handlePageChanged,
        children: _screens,
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            unawaited(_selectScreen(index));
          },
          backgroundColor: const Color(0xFF14121C),
          indicatorColor: const Color(0xFF4C8DFF).withValues(alpha: 0.22),
          elevation: 0,
          height: 72,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.checklist_rounded),
              selectedIcon: Icon(
                Icons.checklist_rounded,
                color: Color(0xFF4C8DFF),
              ),
              label: 'Tasks',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(
                Icons.calendar_month_rounded,
                color: Color(0xFF4C8DFF),
              ),
              label: 'Daily Plan',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(
                Icons.insights_rounded,
                color: Color(0xFF4C8DFF),
              ),
              label: 'Insights',
            ),
          ],
        ),
      ),
    );
  }
}

/*
 * PageView can dispose pages that move outside its cache.
 * This wrapper explicitly preserves the state of each screen,
 * including scroll positions, expansion state and loaded data.
 */
class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin<_KeepAlivePage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return widget.child;
  }
}
