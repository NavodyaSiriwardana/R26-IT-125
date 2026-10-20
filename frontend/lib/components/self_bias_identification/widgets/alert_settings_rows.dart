import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/alert_rules.dart';
import 'package:frontend/components/self_bias_identification/services/alert_service.dart';

/// The Profile rows for critical alerts, quiet hours and lecture mode. Loads
/// and saves its own settings.
class AlertSettingsRows extends StatefulWidget {
  const AlertSettingsRows({super.key});

  @override
  State<AlertSettingsRows> createState() => _AlertSettingsRowsState();
}

String formatMinute(int m) {
  final h = m ~/ 60, min = m % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${min.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String formatRange(DayRange r) =>
    '${formatMinute(r.startMinute)} - ${formatMinute(r.endMinute)}';

class _AlertSettingsRowsState extends State<AlertSettingsRows> {
  AlertSettings _s = const AlertSettings();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AlertService.loadSettings().then((s) {
      if (!mounted) return;
      setState(() {
        _s = s;
        _loaded = true;
      });
    });
  }

  Future<void> _save(AlertSettings s) async {
    setState(() => _s = s);
    await AlertService.saveSettings(s);
  }

  Future<DayRange?> _pick(DayRange from) async {
    final start = await showTimePicker(
      context: context,
      helpText: 'Starts at',
      initialTime:
          TimeOfDay(hour: from.startMinute ~/ 60, minute: from.startMinute % 60),
    );
    if (start == null || !mounted) return null;
    final end = await showTimePicker(
      context: context,
      helpText: 'Ends at',
      initialTime:
          TimeOfDay(hour: from.endMinute ~/ 60, minute: from.endMinute % 60),
    );
    if (end == null) return null;
    return DayRange(start.hour * 60 + start.minute, end.hour * 60 + end.minute);
  }

  Widget _switchRow({
    required Key key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.outfit(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.55))),
              ],
            ),
          ),
          Switch(
            key: key,
            value: value,
            onChanged: _loaded ? onChanged : null,
            activeThumbColor: const Color(0xFF7B6EFF),
          ),
        ],
      ),
    );
  }

  Widget _timeChip(Key key, String label, VoidCallback onTap) => GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8, bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF5DCAA5).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color: const Color(0xFF5DCAA5).withValues(alpha: 0.5)),
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Color(0xFF5DCAA5),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _switchRow(
          key: const Key('alerts-switch'),
          title: 'Critical alerts',
          subtitle: 'Tell me about a critical bias or a stress trend. At most '
              'one a day.',
          value: _s.alertsOn,
          onChanged: (v) => _save(_s.copyWith(alertsOn: v)),
        ),
        _switchRow(
          key: const Key('quiet-switch'),
          title: 'Quiet hours',
          subtitle: 'No notifications ${formatRange(_s.quietHours)}.',
          value: _s.quietHoursOn,
          onChanged: (v) => _save(_s.copyWith(quietHoursOn: v)),
        ),
        _switchRow(
          key: const Key('lecture-switch'),
          title: 'Lecture mode',
          subtitle: 'Hold alerts during class (Mon-Fri). They arrive after '
              'class ends.',
          value: _s.lectureModeOn,
          onChanged: (v) => _save(_s.copyWith(lectureModeOn: v)),
        ),
        if (_s.lectureModeOn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                children: [
                  for (var i = 0; i < _s.lectureBlocks.length; i++)
                    _timeChip(
                      Key('lecture-block-$i'),
                      formatRange(_s.lectureBlocks[i]),
                      () async {
                        final r = await _pick(_s.lectureBlocks[i]);
                        if (r == null) return;
                        final blocks = [..._s.lectureBlocks]..[i] = r;
                        await _save(_s.copyWith(lectureBlocks: blocks));
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
