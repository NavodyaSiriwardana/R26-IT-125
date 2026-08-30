import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/notification_preferences_service.dart';
import '../services/notification_service.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  NotificationPreferences _preferences = NotificationPreferences.defaults;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final preferences = await NotificationPreferencesService.instance.load();

      if (!mounted) return;

      setState(() {
        _preferences = preferences;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Could not load notification preferences.');
    }
  }

  Map<String, dynamic> _buildPlanFromSavedTasks(
    List<Map<String, dynamic>> tasks,
  ) {
    final scheduledTasks = <Map<String, dynamic>>[];

    for (final task in tasks) {
      final status = task['status']?.toString();

      final scheduleStatus = task['schedule_status']?.toString();

      final isSnoozed = task['is_snoozed'] == true;

      if (status == 'completed' || scheduleStatus != 'scheduled' || isSnoozed) {
        continue;
      }

      final taskId = task['id']?.toString();

      if (taskId == null || taskId.isEmpty) {
        continue;
      }

      final parts = task['scheduled_parts'] as List?;

      if (parts != null && parts.isNotEmpty) {
        for (final item in parts) {
          final part = Map<String, dynamic>.from(item as Map);

          final merged = Map<String, dynamic>.from(task);

          merged.addAll(part);
          merged['_doc_id'] = taskId;

          scheduledTasks.add(merged);
        }
      } else {
        final scheduledStart = task['scheduled_start']?.toString();

        if (scheduledStart != null && scheduledStart.isNotEmpty) {
          final merged = Map<String, dynamic>.from(task);

          merged['_doc_id'] = taskId;

          scheduledTasks.add(merged);
        }
      }
    }

    return {
      'scheduled_tasks': scheduledTasks,
      'unscheduled_tasks': <Map<String, dynamic>>[],
    };
  }

  Future<int> _restoreSnoozeNotifications(
    List<Map<String, dynamic>> tasks,
  ) async {
    int count = 0;

    for (final task in tasks) {
      if (task['is_snoozed'] != true) {
        continue;
      }

      final taskId = task['id']?.toString();

      final title = task['title']?.toString().trim();

      final snoozedUntilText = task['snoozed_until']?.toString();

      if (taskId == null ||
          taskId.isEmpty ||
          snoozedUntilText == null ||
          snoozedUntilText.isEmpty) {
        continue;
      }

      final snoozedUntil = DateTime.tryParse(snoozedUntilText);

      if (snoozedUntil == null || !snoozedUntil.isAfter(DateTime.now())) {
        continue;
      }

      final scheduled = await NotificationService.instance
          .scheduleSnoozeReminder(
            taskId: taskId,
            taskTitle: title == null || title.isEmpty ? 'Your task' : title,
            snoozedUntil: snoozedUntil,
          );

      if (scheduled) {
        count++;
      }
    }

    return count;
  }

  Future<void> _savePreferences() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    bool preferencesSaved = false;

    try {
      await NotificationPreferencesService.instance.save(_preferences);

      preferencesSaved = true;

      /*
       * Existing reminders may have been created using old settings.
       * Remove them and recreate valid reminders using the new settings.
       */
      await NotificationService.instance.cancelAllTaskNotifications();

      int planNotificationCount = 0;
      int snoozeNotificationCount = 0;

      if (_preferences.notificationsEnabled) {
        final tasks = await _firestoreService.getAllTasksRaw();

        final savedPlan = _buildPlanFromSavedTasks(tasks);

        planNotificationCount = await NotificationService.instance
            .schedulePlanNotifications(savedPlan);

        snoozeNotificationCount = await _restoreSnoozeNotifications(tasks);
      }

      if (!mounted) return;

      _showMessage(
        _preferences.notificationsEnabled
            ? 'Preferences saved. '
                  '$planNotificationCount plan reminders and '
                  '$snoozeNotificationCount snooze reminders are active.'
            : 'Notifications disabled and pending reminders removed.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Notification preference update failed: '
        '$error',
      );

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showMessage(
        preferencesSaved
            ? 'Preferences were saved, but existing reminders '
                  'could not be refreshed.'
            : 'Could not save notification preferences.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _restoreDefaults() {
    setState(() {
      _preferences = NotificationPreferences.defaults;
    });

    _showMessage('Default values restored. Tap Save Changes to apply them.');
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF172238),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _preferenceSwitch({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Container(
        width: 43,
        height: 43,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _preferences.notificationsEnabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Preferences')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF633BFF), Color(0xFF168DD8)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        size: 38,
                        color: Colors.white,
                      ),
                      SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stay on track',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              'Choose useful reminders without '
                              'creating unnecessary interruptions.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                _sectionCard(
                  child: _preferenceSwitch(
                    icon: Icons.notifications_rounded,
                    color: const Color(0xFF4C8DFF),
                    title: 'Task notifications',
                    subtitle: 'Enable or disable every task reminder.',
                    value: enabled,
                    onChanged: (value) {
                      setState(() {
                        _preferences = _preferences.copyWith(
                          notificationsEnabled: value,
                        );
                      });
                    },
                  ),
                ),

                const SizedBox(height: 14),

                Opacity(
                  opacity: enabled ? 1 : 0.45,
                  child: IgnorePointer(
                    ignoring: !enabled,
                    child: _sectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Advance reminder',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Notify me before a planned task begins.',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Wrap(
                            spacing: 9,
                            runSpacing: 9,
                            children: NotificationPreferencesService
                                .supportedAdvanceMinutes
                                .map((minutes) {
                                  final selected =
                                      _preferences.advanceReminderMinutes ==
                                      minutes;

                                  return ChoiceChip(
                                    label: Text('$minutes min'),
                                    selected: selected,
                                    onSelected: (_) {
                                      setState(() {
                                        _preferences = _preferences.copyWith(
                                          advanceReminderMinutes: minutes,
                                        );
                                      });
                                    },
                                  );
                                })
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Opacity(
                  opacity: enabled ? 1 : 0.45,
                  child: IgnorePointer(
                    ignoring: !enabled,
                    child: _sectionCard(
                      child: Column(
                        children: [
                          _preferenceSwitch(
                            icon: Icons.play_circle_rounded,
                            color: Colors.greenAccent,
                            title: 'Task-start alerts',
                            subtitle: 'Notify me when a scheduled task begins.',
                            value: _preferences.taskStartNotificationsEnabled,
                            onChanged: (value) {
                              setState(() {
                                _preferences = _preferences.copyWith(
                                  taskStartNotificationsEnabled: value,
                                );
                              });
                            },
                          ),
                          Divider(color: Colors.white.withValues(alpha: 0.08)),
                          _preferenceSwitch(
                            icon: Icons.snooze_rounded,
                            color: Colors.cyanAccent,
                            title: 'Snooze-expiry alerts',
                            subtitle:
                                'Notify me when a snoozed task becomes active.',
                            value: _preferences.snoozeNotificationsEnabled,
                            onChanged: (value) {
                              setState(() {
                                _preferences = _preferences.copyWith(
                                  snoozeNotificationsEnabled: value,
                                );
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                FilledButton.icon(
                  onPressed: _isSaving ? null : _savePreferences,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4C8DFF),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                TextButton(
                  onPressed: _isSaving ? null : _restoreDefaults,
                  child: const Text('Restore defaults'),
                ),
              ],
            ),
    );
  }
}
