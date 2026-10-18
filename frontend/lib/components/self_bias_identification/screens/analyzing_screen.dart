import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/sensor_data_service.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_result_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/face_check_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/no_diary_entry_screen.dart';
import 'package:frontend/components/self_bias_identification/widgets/gradient_ring_painter.dart';
import 'package:frontend/components/self_bias_identification/services/privacy_helper.dart';
import 'package:frontend/components/self_bias_identification/services/data_refresh.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';

/// Shown from the moment Facial Capture's "Continue" is tapped until the
/// real API response lands — replaces the old pop-then-push-with-SnackBar
/// flow into the manual form (removed; the "claimed" side now comes from
/// the team's shared diaryEntries collection via /analyze-from-diary).
class AnalyzingScreen extends StatefulWidget {
  final Map<String, dynamic>? facialResult;
  const AnalyzingScreen({super.key, this.facialResult});

  @override
  State<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends State<AnalyzingScreen>
    with TickerProviderStateMixin {
  // The wording matches what is really happening. A bias analysis has these
  // steps; a face-only check has no classifier and no reflection.
  static const _biasSteps = [
    'Fetching your diary entry',
    'Comparing claimed vs verified',
    'Running bias classifier',
    'Generating your reflection',
  ];
  static const _faceSteps = [
    'Reading your scan',
    'Checking your latest diary entry',
    'Preparing your face check',
  ];

  static const _green = Color(0xFF35E47B);

  List<String> _steps = _biasSteps;
  String _title = 'Analyzing your entry';
  String _subtitle = 'Usually takes a few seconds';

  int _stepIndex = 0;
  int _elapsedMs = 0;
  late final Timer _stepTimer;
  late final Timer _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _elapsedMs += 100);
    });
    // Paced to feel like real progress — the API itself returns once,
    // all at once, so these steps advance on a timer rather than real
    // per-stage callbacks from the backend.
    _stepTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (mounted && _stepIndex < _steps.length - 1) {
        setState(() => _stepIndex++);
      }
    });
    _runAnalysis();
  }

  @override
  void dispose() {
    _stepTimer.cancel();
    _elapsedTimer.cancel();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    try {
      // With a good face scan, first ask whether there is anything new to
      // analyse. If not, this is only a face check, so say so and skip the
      // bias analysis (and the sensor reading it needs) altogether.
      final face = withoutFaceImage(widget.facialResult);
      if (face != null && face['status'] == 'success') {
        final state = await ApiService.diaryState(AppState.userId);
        if (!mounted) return;
        if (state != null && state != 'new') {
          setState(() {
            _steps = _faceSteps;
            _title = 'Checking your scan';
            _subtitle = 'Just a moment';
            _stepIndex = 0;
          });
          final reason = switch (state) {
            'stale' => 'stale',
            'analyzed' => 'analyzed',
            _ => 'none',
          };
          if (await _openFaceCheck(reason)) return;
          if (!mounted) return;
          // The face check could not be made: carry on with the usual route.
          setState(() {
            _steps = _biasSteps;
            _title = 'Analyzing your entry';
            _subtitle = 'Usually takes a few seconds';
            _stepIndex = 0;
          });
        }
      }

      final sensorData = await SensorDataService.collectAll(
        userId: AppState.userId,
      );

      final response = await ApiClient.post(
        Uri.parse(
          '${ApiService.baseUrl}/api/bias/analyze-from-diary/${AppState.userId}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sensor_data': {
            ...sensorData,
            'facial_emotion': withoutFaceImage(widget.facialResult),
          },
        }),
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        _failAndPop(
          'The server had a problem (code ${response.statusCode}). Please try again.',
        );
        return;
      }

      final result = jsonDecode(response.body);

      final status = result['status'];

      // Nothing new to compare with: no entry at all, or the latest entry is
      // too old for the phone's recent data. A good face scan still gives Mood
      // Support, so show that rather than a dead end or a misleading result.
      if (status == 'no_entry_found') {
        if (await _openFaceCheck(result['reason'] == 'stale' ? 'stale' : 'none')) {
          return;
        }
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                NoDiaryEntryScreen(tooOld: result['reason'] == 'stale'),
          ),
        );
        return;
      }

      // The latest diary entry was analysed before, so there is nothing new to
      // analyse. With a face scan, show the face check; without one, show the
      // saved result rather than storing a duplicate.
      if (status == 'already_analyzed' && result['result'] is Map) {
        if (await _openFaceCheck('analyzed')) return;
        if (!mounted) return;
        AppToast.info(
          context,
          'This diary entry was already analyzed. Showing the saved result. '
          'Add a new entry to analyze again.',
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BiasResultScreen(
              result: Map<String, dynamic>.from(result['result'] as Map),
            ),
          ),
        );
        return;
      }

      // The new result is saved; screens already in the stack reload now,
      // because the scan screen's Future completed when it was replaced.
      DataRefresh.notify();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => BiasResultScreen(result: result)),
      );
    } catch (e) {
      if (!mounted) return;
      _failAndPop(AppToast.friendlyError(e));
    }
  }

  /// Opens the Face check for a usable face scan. Returns false when there is
  /// no usable scan (nothing was opened).
  Future<bool> _openFaceCheck(String reason) async {
    final face = withoutFaceImage(widget.facialResult);
    if (face == null || face['status'] != 'success') return false;
    final check = await ApiService.faceCheck(AppState.userId, face);
    if (!mounted || check == null) return false;
    DataRefresh.notify();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FaceCheckScreen(
          facial: Map<String, dynamic>.from(check['facial_emotion'] as Map),
          moodSupport: Map<String, dynamic>.from(check['mood_support'] as Map),
          entryId: check['entry_id']?.toString() ?? '',
          reason: reason,
        ),
      ),
    );
    return true;
  }

  void _failAndPop(String message) {
    // Shown on the app-level messenger, so it stays visible after the pop.
    AppToast.error(context, message);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = (_elapsedMs / 1000).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: const Color(0xFF070B12),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  
                ),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(26, 34, 26, 28),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D131D),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 156,
                      height: 156,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Static ring that fills with the steps (no spinning).
                          CustomPaint(
                            size: const Size(156, 156),
                            painter: GradientRingPainter(
                              progress: (_stepIndex + 1) / _steps.length,
                              colors: const [_green, _green],
                              strokeWidth: 6,
                              glowDot: false,
                            ),
                          ),
                          const Icon(
                            Icons.visibility_rounded,
                            size: 46,
                            color: _green,
                          ),
                          Positioned(
                            bottom: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF151C27),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Text(
                                '${elapsed}s',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 26),
                    ...List.generate(_steps.length, (i) {
                      final done = i < _stepIndex;
                      final active = i == _stepIndex;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Container(
                              key: Key('step-$i'),
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                // Done: solid green. Now: a green ring. Next: a grey ring.
                                color: done ? _green : const Color(0xFF151C27),
                                shape: BoxShape.circle,
                                border: done
                                    ? null
                                    : Border.all(
                                        color: active
                                            ? _green
                                            : Colors.white.withValues(alpha: 0.22),
                                        width: 2,
                                      ),
                              ),
                              child: done
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 17,
                                      color: Color(0xFF04231A),
                                    )
                                  : active
                                      ? const Center(
                                          child: Icon(
                                            Icons.circle,
                                            size: 9,
                                            color: _green,
                                          ),
                                        )
                                      : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                _steps[i],
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 1.25,
                                  fontWeight:
                                      active ? FontWeight.w800 : FontWeight.w600,
                                  color: (active || done)
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: const Color(0xFF1C2430),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (_stepIndex + 1) / _steps.length,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: _green,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
