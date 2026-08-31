import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/sensor_data_service.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_result_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/no_diary_entry_screen.dart';
import 'package:frontend/components/self_bias_identification/widgets/gradient_ring_painter.dart';

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
  static const _steps = [
    'Fetching your diary entry',
    'Comparing claimed vs verified',
    'Running bias classifier',
    'Generating your reflection',
  ];

  int _stepIndex = 0;
  int _elapsedMs = 0;
  late final Timer _stepTimer;
  late final Timer _elapsedTimer;
  late final AnimationController _spinController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
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
    _spinController.dispose();
    _pulseController.dispose();
    _stepTimer.cancel();
    _elapsedTimer.cancel();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    try {
      final sensorData = await SensorDataService.collectAll(
        userId: AppState.userId,
      );

      final response = await http.post(
        Uri.parse(
          '${ApiService.baseUrl}/api/bias/analyze-from-diary/${AppState.userId}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sensor_data': {
            ...sensorData,
            'facial_emotion': widget.facialResult,
          },
        }),
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        _failAndPop('Server error: ${response.statusCode}');
        return;
      }

      final result = jsonDecode(response.body);

      if (result['status'] == 'no_entry_found') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NoDiaryEntryScreen()),
        );
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => BiasResultScreen(result: result)),
      );
    } catch (e) {
      if (!mounted) return;
      _failAndPop('Connection error: $e');
    }
  }

  void _failAndPop(String message) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = (_elapsedMs / 1000).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: const Color(0xFF070812),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.2, -0.7),
                    radius: 1.3,
                    colors: [
                      const Color(0xFF35E47B).withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(26, 32, 26, 26),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 60,
                    offset: const Offset(0, 28),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 128,
                    height: 128,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _spinController,
                          builder: (context, child) => Transform.rotate(
                            angle: _spinController.value * 2 * math.pi,
                            child: child,
                          ),
                          child: CustomPaint(
                            size: const Size(128, 128),
                            painter: const GradientRingPainter(
                              progress: 0.25,
                              colors: [Color(0xFF35E47B), Color(0xFF6FE07E)],
                              strokeWidth: 3,
                              glowDot: true,
                            ),
                          ),
                        ),
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) => Transform.scale(
                            scale: 1 + 0.08 * _pulseController.value,
                            child: child,
                          ),
                          child: const Icon(
                            Icons.visibility_rounded,
                            size: 36,
                            color: Color(0xFF35E47B),
                          ),
                        ),
                        Positioned(
                          bottom: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0E14),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              '${elapsed}s',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Analyzing your entry',
                    style: GoogleFonts.outfit(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Usually takes a few seconds',
                    style: TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                  const SizedBox(height: 22),
                  ...List.generate(_steps.length, (i) {
                    final done = i < _stepIndex;
                    final active = i == _stepIndex;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          Container(
                            width: 23,
                            height: 23,
                            decoration: BoxDecoration(
                              color: done
                                  ? const Color(0xFF4ADE80).withValues(alpha: 0.2)
                                  : active
                                      ? const Color(0xFF35E47B).withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                              border: done || active
                                  ? null
                                  : Border.all(
                                      color: Colors.white.withValues(alpha: 0.08),
                                    ),
                            ),
                            child: done
                                ? const Icon(
                                    Icons.check,
                                    size: 13,
                                    color: Color(0xFF4ADE80),
                                  )
                                : active
                                    ? const Padding(
                                        padding: EdgeInsets.all(7),
                                        child: Icon(
                                          Icons.circle,
                                          size: 7,
                                          color: Color(0xFF35E47B),
                                        ),
                                      )
                                    : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _steps[i],
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    active ? FontWeight.w700 : FontWeight.w400,
                                color: active
                                    ? Colors.white
                                    : Colors.white.withValues(
                                        alpha: done ? 0.75 : 0.4,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (_stepIndex + 1) / _steps.length,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF35E47B), Color(0xFF6FE07E)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF35E47B).withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
