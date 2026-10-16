import 'dart:async';

import 'package:flutter/material.dart';

const weeklySummaryProgressMessages = [
  'Reflecting on your week…',
  'Connecting the dots…',
  'Looking for meaningful patterns…',
  'Noticing what stood out…',
  'Bringing your week into focus…',
  'Shaping your weekly reflection…',
];

class WeeklySummaryProgress extends StatefulWidget {
  final String initialMessage;
  final Color color;

  const WeeklySummaryProgress({
    super.key,
    this.initialMessage = 'Creating your weekly reflection…',
    this.color = const Color(0xFF7F77DD),
  });

  @override
  State<WeeklySummaryProgress> createState() => _WeeklySummaryProgressState();
}

class _WeeklySummaryProgressState extends State<WeeklySummaryProgress> {
  late final List<String> _messages;
  late String _message;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    _messages = List.of(weeklySummaryProgressMessages)..shuffle();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      setState(() => _message = _messages[(timer.tick - 1) % _messages.length]);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: widget.color),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            _message,
            key: ValueKey(_message),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFEDEBFF),
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
