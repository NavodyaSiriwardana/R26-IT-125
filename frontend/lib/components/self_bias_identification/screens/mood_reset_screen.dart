import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/screens/webcam_capture_screen.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/gradient_ring_painter.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';
import 'package:frontend/components/self_bias_identification/services/study_service.dart';
import 'package:frontend/components/self_bias_identification/services/data_refresh.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';

enum _Stage { ready, breathing, rating, recheck, analyzing, result }

/// Guided 4-7-8 breathing reset followed by a second camera reading, so the
/// user (and the research report) can see stress before vs after.
class MoodResetScreen extends StatefulWidget {
  final String entryId;
  final double beforeStress;
  final String beforeMoodLabel;
  final Map<String, dynamic> breathing;

  const MoodResetScreen({
    super.key,
    required this.entryId,
    required this.beforeStress,
    required this.beforeMoodLabel,
    required this.breathing,
  });

  @override
  State<MoodResetScreen> createState() => _MoodResetScreenState();
}

class _MoodResetScreenState extends State<MoodResetScreen>
    with SingleTickerProviderStateMixin {
  _Stage _stage = _Stage.ready;

  late final int _inhale;
  late final int _hold;
  late final int _exhale;
  late final int _rounds;
  late final AnimationController _cycle;

  int _round = 0;
  String _lastPhase = '';
  final Stopwatch _clock = Stopwatch();
  int _roundsDone = 0;
  int _durationSeconds = 0;

  String? _warning;
  String? _error;
  Map<String, dynamic>? _evaluation;

  // Research study: self-reported stress (1-5) is what the facial stress score
  // is validated against, and the condition separates breathing from waiting.
  bool _studyMode = false;
  String _condition = StudyService.breathing;
  int? _selfBefore;
  int? _selfAfter;
  bool get _isControl => _condition == StudyService.control;

  int get _cycleSeconds => _inhale + _hold + _exhale;

  @override
  void initState() {
    super.initState();
    _inhale = (widget.breathing['inhale'] as num?)?.toInt() ?? 4;
    _hold = (widget.breathing['hold'] as num?)?.toInt() ?? 7;
    _exhale = (widget.breathing['exhale'] as num?)?.toInt() ?? 8;
    _rounds = (widget.breathing['rounds'] as num?)?.toInt() ?? 6;

    _cycle = AnimationController(
      vsync: this,
      duration: Duration(seconds: _cycleSeconds),
    )..addStatusListener(_onCycleStatus);
    _cycle.addListener(_onTick);
    _loadStudy();
  }

  Future<void> _loadStudy() async {
    final study = await StudyService.isStudyMode();
    final condition =
        study ? await StudyService.nextCondition() : StudyService.breathing;
    if (!mounted) return;
    setState(() {
      _studyMode = study;
      _condition = condition;
    });
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Breathing
  // ---------------------------------------------------------------------

  void _startBreathing() {
    _round = 0;
    _roundsDone = 0;
    _clock
      ..reset()
      ..start();
    setState(() => _stage = _Stage.breathing);
    _cycle.forward(from: 0);
  }

  void _onCycleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _stage != _Stage.breathing) {
      return;
    }
    _roundsDone++;
    _round++;
    if (_round >= _rounds) {
      _finishBreathing();
    } else {
      setState(() {});
      _cycle.forward(from: 0);
    }
  }

  void _finishBreathing() {
    _cycle.stop();
    _clock.stop();
    _durationSeconds = _clock.elapsed.inSeconds;
    HapticFeedback.mediumImpact();
    setState(() => _stage = _Stage.rating);
  }

  void _onTick() {
    if (_isControl) return;
    final phase = _phaseName(_cycle.value * _cycleSeconds);
    if (phase != _lastPhase) {
      _lastPhase = phase;
      HapticFeedback.selectionClick();
    }
  }

  String _phaseName(double t) {
    if (t < _inhale) return 'Inhale';
    if (t < _inhale + _hold) return 'Hold';
    return 'Exhale';
  }

  /// Orb size 0.55 -> 1.0 on inhale, stays on hold, back down on exhale.
  double _orbScale(double t) {
    if (t < _inhale) {
      return 0.55 + 0.45 * Curves.easeInOut.transform(t / _inhale);
    }
    if (t < _inhale + _hold) return 1.0;
    final e = (t - _inhale - _hold) / _exhale;
    return 1.0 - 0.45 * Curves.easeInOut.transform(e.clamp(0.0, 1.0));
  }

  Color _phaseColor(String phase) {
    switch (phase) {
      case 'Inhale':
        return MoodPalette.mint;
      case 'Hold':
        return MoodPalette.violetSoft;
      default:
        return MoodPalette.cyan;
    }
  }

  // ---------------------------------------------------------------------
  // Re-check capture
  // ---------------------------------------------------------------------

  Future<void> _capture() async {
    try {
      final bytes = await captureFromWebcam(context);
      if (bytes == null || !mounted) return;

      setState(() {
        _stage = _Stage.analyzing;
        _warning = null;
        _error = null;
      });

      final facial = await ApiService.analyzeFace(base64Encode(bytes));
      if (!mounted) return;

      if (facial['status'] != 'success') {
        setState(() {
          _stage = _Stage.recheck;
          _warning =
              (facial['message'] ?? 'Please retake the photo.').toString();
        });
        return;
      }

      final evaluation = await ApiService.saveMoodReset(
        userId: AppState.userId,
        entryId: widget.entryId,
        beforeStress: widget.beforeStress,
        beforeMood: widget.beforeMoodLabel,
        afterFacial: facial,
        durationSeconds: _durationSeconds,
        roundsCompleted: _roundsDone,
        selfBefore: _selfBefore,
        selfAfter: _selfAfter,
        condition: _condition,
        studyMode: _studyMode,
      );
      if (_studyMode) await StudyService.recordCompleted(_condition);
      DataRefresh.notify();
      if (!mounted) return;

      final afterStress =
          ((evaluation['after_mood'] as Map?)?['stress'] as num?)?.toDouble();
      if (evaluation['saved'] == false) {
        AppToast.warning(
          context,
          'Your reset could not be saved. Check your connection.',
        );
      } else if (afterStress != null) {
        AppToast.success(
          context,
          'Reset saved. Stress ${(widget.beforeStress * 100).round()}% '
          '→ ${(afterStress * 100).round()}%.',
        );
      } else {
        AppToast.success(context, 'Reset saved.');
      }
      setState(() {
        _evaluation = evaluation;
        _stage = _Stage.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.recheck;
        _error =
            'Could not complete the check. Make sure the server is running and try again.';
      });
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Leaving mid-session throws it away, so the back gesture asks first.
      canPop: _stage != _Stage.breathing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  _topBar(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: KeyedSubtree(
                        key: ValueKey(_stage),
                        child: _stageBody(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  void _requestClose() {
    if (_stage == _Stage.breathing) {
      _confirmLeave();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave the reset?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your session so far will not be saved.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay', style: TextStyle(color: MoodPalette.mint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Leave',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _cycle.stop();
      Navigator.pop(context);
    }
  }

  Widget _topBar() {
    final title = switch (_stage) {
      _Stage.ready => 'Mood Reset',
      _Stage.breathing => _isControl ? 'Quiet rest' : '4-7-8 breathing',
      _Stage.rating => 'How stressed now?',
      _Stage.recheck || _Stage.analyzing => 'How do you feel now?',
      _Stage.result => 'Reset result',
    };
    return Row(
      children: [
        GestureDetector(
          onTap: _requestClose,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _stageBody() {
    switch (_stage) {
      case _Stage.ready:
        return _readyStage();
      case _Stage.breathing:
        return _breathingStage();
      case _Stage.rating:
        return _ratingStage();
      case _Stage.recheck:
        return _recheckStage();
      case _Stage.analyzing:
        return _analyzingStage();
      case _Stage.result:
        return _resultStage();
    }
  }

  // --- Ready -----------------------------------------------------------

  Widget _readyStage() {
    final seconds = _cycleSeconds * _rounds;
    final minutes = (seconds / 60).round();
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 12),
          if (_isControl)
            _restBadge(150)
          else
            _orb(scale: 0.8, color: MoodPalette.mint, size: 170),
          const SizedBox(height: 24),
          Text(
            _isControl ? 'Rest quietly for two minutes' : 'Take two minutes to reset',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _isControl
                ? 'Sit comfortably and let your mind settle. Please do not do any '
                    'breathing exercise. About $minutes minutes, then one more photo '
                    'to compare your stress.'
                : 'Sit upright and relax your shoulders. Follow the circle: inhale '
                    '$_inhale, hold $_hold, exhale $_exhale. $_rounds rounds, about '
                    '$minutes minutes. Afterwards we take one more photo to compare '
                    'your stress.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          _beforeChip(),
          const SizedBox(height: 22),
          _ratingPrompt('How stressed do you feel right now?', optional: true),
          const SizedBox(height: 10),
          _ratingChips(
            value: _selfBefore,
            onChanged: (v) => setState(() => _selfBefore = v),
          ),
          const SizedBox(height: 26),
          _gradientButton(
            label: 'Begin',
            icon: Icons.play_arrow_rounded,
            colors: const [MoodPalette.mint, MoodPalette.cyan],
            onTap: _startBreathing,
          ),
        ],
      ),
    );
  }

  Widget _restBadge(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: MoodPalette.violetSoft.withValues(alpha: 0.5),
          width: 3,
        ),
      ),
      child: Icon(
        Icons.self_improvement_rounded,
        size: size * 0.45,
        color: MoodPalette.violetSoft,
      ),
    );
  }

  Widget _ratingPrompt(String text, {bool optional = false}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        optional ? '$text (optional)' : text,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  /// 1 = very calm ... 5 = very stressed.
  Widget _ratingChips({required int? value, required ValueChanged<int> onChanged}) {
    const colors = [
      MoodPalette.mint,
      MoodPalette.cyan,
      MoodPalette.amber,
      MoodPalette.orange,
      MoodPalette.coral,
    ];
    return Column(
      children: [
        Row(
          children: [
            for (int i = 1; i <= 5; i++) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: value == i
                          ? colors[i - 1]
                          : Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: value == i
                            ? colors[i - 1]
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$i',
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: value == i
                              ? const Color(0xFF0A0E14)
                              : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (i != 5) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Very calm',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            Text(
              'Very stressed',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Self-report after the session (before any result is shown) -------

  Widget _ratingStage() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 40),
          _restBadge(120),
          const SizedBox(height: 26),
          Text(
            'How stressed do you feel now?',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Answer from how you feel. You will see the camera comparison afterwards.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 28),
          _ratingChips(
            value: _selfAfter,
            onChanged: (v) => setState(() => _selfAfter = v),
          ),
          const SizedBox(height: 32),
          _gradientButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            colors: const [MoodPalette.mint, MoodPalette.cyan],
            onTap: () => setState(() => _stage = _Stage.recheck),
          ),
          TextButton(
            onPressed: () => setState(() {
              _selfAfter = null;
              _stage = _Stage.recheck;
            }),
            child: Text(
              'Skip',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _beforeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: MoodPalette.coral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MoodPalette.coral.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Before: ${widget.beforeMoodLabel} · ${(widget.beforeStress * 100).round()}% stress',
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: MoodPalette.coral,
        ),
      ),
    );
  }

  // --- Breathing -------------------------------------------------------

  Widget _breathingStage() {
    if (_isControl) return _restStage();
    return AnimatedBuilder(
      animation: _cycle,
      builder: (context, _) {
        final t = _cycle.value * _cycleSeconds;
        final phase = _phaseName(t);
        final color = _phaseColor(phase);
        final phaseLen = phase == 'Inhale'
            ? _inhale
            : phase == 'Hold'
            ? _hold
            : _exhale;
        final phaseStart = phase == 'Inhale'
            ? 0
            : phase == 'Hold'
            ? _inhale
            : _inhale + _hold;
        final remaining = (phaseLen - (t - phaseStart)).ceil().clamp(1, phaseLen);
        final overall = ((_round + _cycle.value) / _rounds).clamp(0.0, 1.0);
        final left = (_cycleSeconds * _rounds * (1 - overall)).round();

        return Column(
          children: [
            const Spacer(),
            SizedBox(
              width: 290,
              height: 290,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(290, 290),
                    painter: GradientRingPainter(
                      progress: overall,
                      colors: const [MoodPalette.mint, MoodPalette.cyan],
                      strokeWidth: 5,
                      glowDot: true,
                    ),
                  ),
                  _orb(scale: _orbScale(t), color: color, size: 220),
                  Text(
                    '$remaining',
                    style: GoogleFonts.outfit(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0A0E14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              phase,
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Round ${math.min(_round + 1, _rounds)} of $_rounds · ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} left',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const Spacer(),
            // In study mode every session runs the same length, so no early exit.
            if (_studyMode)
              const SizedBox(height: 48)
            else
              TextButton(
                onPressed: _roundsDone >= 1 ? _finishBreathing : null,
                child: Text(
                  _roundsDone >= 1 ? 'End early' : 'Finish one round to end early',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Control condition: same length as the breathing session, no guidance.
  Widget _restStage() {
    return AnimatedBuilder(
      animation: _cycle,
      builder: (context, _) {
        final overall = ((_round + _cycle.value) / _rounds).clamp(0.0, 1.0);
        final left = (_cycleSeconds * _rounds * (1 - overall)).round();
        return Column(
          children: [
            const Spacer(),
            SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(260, 260),
                    painter: GradientRingPainter(
                      progress: overall,
                      colors: const [MoodPalette.violetSoft, MoodPalette.cyan],
                      strokeWidth: 5,
                    ),
                  ),
                  Text(
                    '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}',
                    style: GoogleFonts.outfit(
                      fontSize: 54,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Rest quietly',
              style: GoogleFonts.outfit(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: MoodPalette.violetSoft,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Let your mind settle. No exercise needed.',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const Spacer(),
            const SizedBox(height: 48),
          ],
        );
      },
    );
  }

  Widget _orb({required double scale, required Color color, required double size}) {
    final d = size * scale;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [
            Color.lerp(color, Colors.white, 0.45)!,
            color,
            Color.lerp(color, MoodPalette.violet, 0.6)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
    );
  }

  // --- Re-check --------------------------------------------------------

  Widget _recheckStage() {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: MoodPalette.mint.withValues(alpha: 0.5),
              width: 3,
            ),
            color: Colors.white.withValues(alpha: 0.04),
          ),
          child: Icon(
            Icons.face_retouching_natural_rounded,
            size: 78,
            color: MoodPalette.mint.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Nice work. One quick photo.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Face the camera in good light. We compare it with your first scan.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        if (_warning != null) ...[
          const SizedBox(height: 16),
          _notice(Icons.face_retouching_off, _warning!, MoodPalette.amber),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          _notice(Icons.error_outline_rounded, _error!, MoodPalette.coral),
        ],
        const Spacer(),
        _gradientButton(
          label: _warning != null || _error != null ? 'Retake photo' : 'Capture',
          icon: Icons.camera_alt_rounded,
          colors: const [MoodPalette.mint, MoodPalette.cyan],
          onTap: _capture,
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Skip the comparison',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
          ),
        ),
      ],
    );
  }

  Widget _analyzingStage() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            color: MoodPalette.mint,
            strokeWidth: 4,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Comparing with your first scan...',
          style: GoogleFonts.outfit(fontSize: 16, color: Colors.white70),
        ),
      ],
    );
  }

  // --- Result ----------------------------------------------------------

  String get _outcome => (_evaluation?['outcome'] ?? 'unknown').toString();

  Color _outcomeColor() {
    switch (_outcome) {
      case 'improved':
        return MoodPalette.mint;
      case 'worse':
        return MoodPalette.coral;
      case 'no_change':
        return MoodPalette.amber;
      default:
        return MoodPalette.violet;
    }
  }

  Widget _resultStage() {
    final afterMood = Map<String, dynamic>.from(
      _evaluation?['after_mood'] as Map? ?? {},
    );
    final afterStress = (afterMood['stress'] as num?)?.toDouble();
    final points = (_evaluation?['delta_points'] as num?)?.toInt();
    final color = _outcomeColor();
    final headline = switch (_outcome) {
      'improved' => '${points ?? 0} points lower',
      'worse' => '${(points ?? 0).abs()} points higher',
      'no_change' => 'About the same',
      _ => 'No comparison',
    };

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _stressGauge(
                        label: 'BEFORE',
                        value: widget.beforeStress,
                        moodLabel: widget.beforeMoodLabel,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 26,
                    ),
                    Expanded(
                      child: afterStress == null
                          ? const SizedBox.shrink()
                          : _stressGauge(
                              label: 'AFTER',
                              value: afterStress,
                              moodLabel: (afterMood['label'] ?? '').toString(),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  headline,
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (_evaluation?['message'] ?? '').toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Saved to your history · $_roundsDone rounds · ${_durationSeconds}s',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 22),
          if (!_studyMode && (_outcome == 'worse' || _outcome == 'no_change')) ...[
            _gradientButton(
              label: 'Another round',
              icon: Icons.refresh_rounded,
              colors: const [MoodPalette.mint, MoodPalette.cyan],
              onTap: () {
                setState(() {
                  _evaluation = null;
                          _stage = _Stage.ready;
                });
              },
            ),
            const SizedBox(height: 12),
          ],
          _gradientButton(
            label: 'Done',
            icon: Icons.check_rounded,
            colors: _outcome == 'improved'
                ? const [MoodPalette.mint, MoodPalette.cyan]
                : const [MoodPalette.violet, MoodPalette.violetSoft],
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _stressGauge({
    required String label,
    required double value,
    required String moodLabel,
  }) {
    final c = value >= 0.5
        ? MoodPalette.coral
        : value >= 0.3
        ? MoodPalette.orange
        : MoodPalette.mint;
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(92, 92),
                  painter: GradientRingPainter(
                    progress: v,
                    colors: [c.withValues(alpha: 0.7), c],
                    strokeWidth: 9,
                  ),
                ),
                Text(
                  '${(v * 100).round()}%',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          moodLabel,
          style: TextStyle(fontSize: 14, color: c, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  // --- Shared bits -----------------------------------------------------

  Widget _notice(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(colors: colors),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: const Color(0xFF0A0E14)),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0A0E14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
