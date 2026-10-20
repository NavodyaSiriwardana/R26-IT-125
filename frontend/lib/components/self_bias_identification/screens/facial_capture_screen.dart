import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:frontend/components/self_bias_identification/widgets/scan_continue_button.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/screens/webcam_capture_screen.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/analyzing_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/gradient_ring_painter.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_heatmap.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_bulb_popup.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_recommendations_card.dart';
import 'package:frontend/components/self_bias_identification/widgets/scan_mood_card.dart';
import 'package:frontend/components/self_bias_identification/screens/mood_reset_screen.dart';
import 'package:frontend/components/self_bias_identification/services/mood_light_data.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/services/mood_heatmap.dart';
import 'package:frontend/components/self_bias_identification/services/entry_time.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';

class FacialCaptureScreen extends StatefulWidget {
  const FacialCaptureScreen({super.key});

  @override
  State<FacialCaptureScreen> createState() => _FacialCaptureScreenState();
}

class _FacialCaptureScreenState extends State<FacialCaptureScreen>
    with SingleTickerProviderStateMixin {
  Uint8List? _imageBytes;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _result;
  String? _errorMessage;
  bool _facialTabSelected = true;
  List<Map<String, dynamic>> _history = [];
  List<HistoryEntry> _heatEntries = [];

  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

  static const green = Color(0xFF5DCAA5);
  static const greenBright = Color(0xFF4ADE80);
  static const cyan = Color(0xFF22D3EE);
  static const amber = Color(0xFFFFCB6B);
  static const cardBg = Color(0xFF0A1710);

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadHeat();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scanAnimation = Tween<double>(begin: 0, end: 1).animate(_scanController);
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiService.baseUrl}/api/bias/history/${AppState.userId}'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = (data['history'] as List? ?? [])
            .map((e) => e as Map<String, dynamic>)
            .toList();

        history.sort((a, b) {
          final aId = a['entry_id']?.toString() ?? '';
          final bId = b['entry_id']?.toString() ?? '';
          final aTime = entryTimestampMs(aId) ?? 0;
          final bTime = entryTimestampMs(bId) ?? 0;
          return bTime.compareTo(aTime);
        });

        setState(() {
          _history = history.take(7).toList().reversed.toList();
        });
      }
    } catch (e) {
      // history is optional here — silently ignore
    }
  }

  Future<void> _captureImage() async {
    final bytes = await captureFromWebcam(context);
    if (bytes == null || !mounted) return;

    setState(() {
      _imageBytes = bytes;
      _isAnalyzing = true;
      _errorMessage = null;
      _result = null;
    });

    _scanController.repeat();
    await _analyzeExpression();
    _scanController.stop();
    _scanController.reset();
  }

  Future<void> _analyzeExpression() async {
    try {
      final bytes = _imageBytes!;
      final base64Image = base64Encode(bytes);

      final response = await ApiClient.post(
        Uri.parse('${ApiService.baseUrl}/api/bias/facial/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image_base64': base64Image}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _result = jsonDecode(response.body);
          _isAnalyzing = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'The server had a problem (code ${response.statusCode}). Please try again.';
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = AppToast.friendlyError(e);
        _isAnalyzing = false;
      });
    }
  }

  void _continueToForm() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AnalyzingScreen(facialResult: _result),
      ),
    );
  }

  void _skipCapture() {
    AppToast.info(
      context,
      'Skipped the camera. The result uses your reported mood.',
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AnalyzingScreen()),
    );
  }

  Map<String, dynamic> _deriveMoodResult() {
    final dominant = _result!['dominant_emotion'] ?? '';
    final confidence = (_result!['confidence'] ?? 0).toDouble();
    final stress = (_result!['stress_indicator'] ?? 0).toDouble();

    if (confidence < 0.35) {
      return {'label': 'Inconclusive', 'emoji': '❔', 'reliable': false};
    }

    // Stress score takes priority — it directly sums negative emotion signals
    if (stress >= 0.5) {
      return {'label': 'Stressed', 'emoji': '😟', 'reliable': true};
    }
    if (stress >= 0.3) {
      return {'label': 'Uneasy', 'emoji': '😕', 'reliable': true};
    }

    const positiveEmotions = ['happy', 'surprise'];
    if (positiveEmotions.contains(dominant)) {
      return {'label': 'Positive', 'emoji': '😊', 'reliable': true};
    }

    return {'label': 'Neutral', 'emoji': '😐', 'reliable': true};
  }

  @override
  Widget build(BuildContext context) {
    final bool isSuccess = _result != null && _result!['status'] == 'success';
    final bool isNoFace =
        _result != null && _result!['status'] == 'no_face_detected';
    final bool isPartialFace =
        _result != null && _result!['status'] == 'partial_face';
    final bool isBlurryImage =
        _result != null && _result!['status'] == 'blurry_image';
    final bool isLowLight =
        _result != null && _result!['status'] == 'low_light';
    // More than one face: the backend refuses to guess whose stress it is.
    final bool isMultipleFaces =
        _result != null && _result!['status'] == 'multiple_faces_detected';
    final bool showWarning = isNoFace ||
        isPartialFace ||
        isBlurryImage ||
        isLowLight ||
        isMultipleFaces;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      // Once a scan is good, Continue stays on screen on both tabs, instead of
      // sitting at the bottom of a long page where it was easy to miss.
      bottomNavigationBar: isSuccess
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: _buildContinueButton(),
              ),
            )
          : null,
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
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(isSuccess, showWarning),
                  const SizedBox(height: 22),
                  Text(
                    'Expression Scan',
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'MediaPipe landmark check + Vision Transformer emotion model',
                    style: TextStyle(
                        fontSize: 14, color: Colors.white38, height: 1.4),
                  ),
                  const SizedBox(height: 24),

                  _buildTabToggle(),
                  const SizedBox(height: 24),

                  _facialTabSelected ? _buildCameraCard() : _buildDiaryMoodCard(),

                  if (_facialTabSelected && !isSuccess) ...[
                    const SizedBox(height: 28),
                    _buildCaptureButton(),
                  ],

                  if (_isAnalyzing) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Analyzing expression...',
                        style: GoogleFonts.outfit(
                            color: Colors.white54, fontSize: 14),
                      ),
                    ),
                  ],

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _glassMessageCard(
                      icon: Icons.error_outline,
                      text: _errorMessage!,
                      color: Colors.redAccent,
                    ),
                  ],

                  if (showWarning && _facialTabSelected) ...[
                    const SizedBox(height: 16),
                    _glassMessageCard(
                      icon: Icons.face_retouching_off,
                      text: _result!['message'] ?? 'Please retake the photo.',
                      color: Colors.orangeAccent,
                    ),
                  ],

                  if (isSuccess && _facialTabSelected) ...[
                    const SizedBox(height: 18),
                    _buildStressCard(),
                    const SizedBox(height: 14),
                    _buildScanMoodCard(),
                    if (_moodLevel != MoodLightLevel.calm) ...[
                      const SizedBox(height: 14),
                      MoodRecommendationsCard(level: _moodLevel),
                    ],
                    const SizedBox(height: 14),
                    _buildExpressionCard(),
                    const SizedBox(height: 14),
                    MoodHeatmapCard(heatmap: _heatmap),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: _isAnalyzing ? null : _captureImage,
                        icon: const Icon(Icons.refresh_rounded,
                            size: 18, color: Colors.white54),
                        label: Text(
                          'Retake photo',
                          style: GoogleFonts.outfit(
                              fontSize: 14, color: Colors.white54),
                        ),
                      ),
                    ),
                  ] else if (_facialTabSelected) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: _skipCapture,
                        child: const Text(
                          'Skip for now',
                          style: TextStyle(color: Colors.white38),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Shared visual building blocks
  // ---------------------------------------------------------------------

  Widget _buildTopBar(bool isSuccess, bool showWarning) {
    final statusColor =
        isSuccess ? green : showWarning ? Colors.orangeAccent : green;
    final statusLabel = isSuccess
        ? 'SCAN COMPLETE'
        : showWarning
            ? 'NEEDS RETAKE'
            : 'READY';
    final statusIcon = isSuccess
        ? Icons.check_circle
        : showWarning
            ? Icons.warning_amber_rounded
            : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        _statusPill(color: statusColor, label: statusLabel, icon: statusIcon),
      ],
    );
  }

  Widget _statusPill({required Color color, required String label, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: color)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                
              ),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF12161F),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _facialTabSelected = true),
              child: _tabSegment('Facial scan', _facialTabSelected),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _facialTabSelected = false),
              child: _tabSegment('Diary mood', !_facialTabSelected),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabSegment(String label, bool selected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: selected ? green : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? const Color(0xFF04342C) : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _cardLabel(String text) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.4),
          letterSpacing: 1,
        ),
      );

  Widget _glassMessageCard({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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

  // ---------------------------------------------------------------------
  // Facial scan tab
  // ---------------------------------------------------------------------

  Widget _mirrored(Widget photo) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: photo,
      );

  Widget _buildCameraCard() {
    final hasImage = _imageBytes != null;
    final success = _result != null && _result!['status'] == 'success';
    final croppedFace = _result != null && _result!['cropped_face_base64'] != null
        ? base64Decode(_result!['cropped_face_base64'])
        : null;
    final badge = _isAnalyzing
        ? 'Scanning...'
        : success
            ? 'Scan complete'
            : hasImage
                ? 'Photo captured'
                : 'Align your face in the frame';
    final ringColor = _isAnalyzing
        ? cyan
        : (success ? moodLightInfo(_moodLevel).color : green);
    const stageHeight = 276.0;

    return Column(
      children: [
        Container(
          width: double.infinity,
          height: stageHeight,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _BracketPainter(color: cyan)),
                ),
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColor, width: 3),
                  ),
                  child: ClipOval(
                    // Shown mirrored, like the preview was. This is display
                    // only: the photo that is analysed is the true one.
                    child: croppedFace != null
                        ? _mirrored(Image.memory(croppedFace, fit: BoxFit.cover))
                        : hasImage
                            ? _mirrored(
                                Image.memory(_imageBytes!, fit: BoxFit.cover))
                            : Container(
                                color: cardBg,
                                child: Icon(
                                  Icons.face_outlined,
                                  size: 56,
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                  ),
                ),
                if (_isAnalyzing)
                  AnimatedBuilder(
                    animation: _scanAnimation,
                    builder: (context, _) {
                      // Up and down, not a jump back to the top.
                      final t =
                          (math.sin(_scanAnimation.value * 2 * math.pi - math.pi / 2) + 1) / 2;
                      return Positioned(
                        left: 30,
                        right: 30,
                        top: 36 + t * (stageHeight - 72),
                        child: Container(height: 2, color: cyan),
                      );
                    },
                  ),
                if (success)
                  Positioned.fill(
                    child: MoodBulbPopup(
                      key: ValueKey(identityHashCode(_result)),
                      level: _moodLevel,
                    ),
                  ),
                Positioned(
                  bottom: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isAnalyzing ? cyan : (success ? green : const Color(0xFF1B2430)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: (_isAnalyzing || success)
                            ? const Color(0xFF06231A)
                            : Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 14),
          _buildDiagnosticChips(),
        ],
      ],
    );
  }

  Widget _buildDiagnosticChips() {
    final isNoFace = _result!['status'] == 'no_face_detected';
    final isBlurry = _result!['status'] == 'blurry_image';
    final isLowLight = _result!['status'] == 'low_light';
    final isMultipleFaces = _result!['status'] == 'multiple_faces_detected';
    final isPartial = _result!['status'] == 'partial_face';
    // Blur and low-light checks run before face detection, so no face
    // verdict exists for those results.
    final faceChecked = !(isBlurry || isLowLight);

    final faceChip = isNoFace
        ? _diagnosticChip(Icons.close, 'No face detected', Colors.redAccent)
        : isMultipleFaces
            ? _diagnosticChip(
                Icons.close, 'Multiple faces detected', Colors.redAccent)
            : _diagnosticChip(Icons.check, 'Face detected', green);

    final qualityChip = isLowLight
        ? _diagnosticChip(Icons.close, 'Too dark', Colors.orangeAccent)
        : isBlurry
        ? _diagnosticChip(Icons.close, 'Image blurry', Colors.orangeAccent)
        : isPartial
            ? _diagnosticChip(
                Icons.close, 'Face partially visible', Colors.orangeAccent)
            : _diagnosticChip(Icons.check, 'Image quality good', green);

    final confidenceChip = _result!['status'] == 'success'
        ? _diagnosticChip(
            Icons.verified_outlined,
            'Confidence ${(((_result!['confidence'] ?? 0) as num) * 100).round()}%',
            cyan,
          )
        : null;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        if (faceChecked) faceChip,
        if (!isNoFace && !isMultipleFaces) qualityChip,
        ?confidenceChip,
      ],
    );
  }

  Widget _diagnosticChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _isAnalyzing ? null : _captureImage,
            child: SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: green.withValues(alpha: 0.25)),
                    ),
                  ),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: green.withValues(alpha: 0.35)),
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: green,
                      
                    ),
                    child: _isAnalyzing
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: Color(0xFF04342C),
                              strokeWidth: 2.4,
                            ),
                          )
                        : const Icon(
                            Icons.qr_code_scanner_rounded,
                            color: Color(0xFF04342C),
                            size: 26,
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _imageBytes == null ? 'Tap to capture' : 'Retake photo',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// The light for the scan on screen: the same thresholds the backend uses.
  MoodLightLevel get _moodLevel {
    final r = _result;
    if (r == null || r['status'] != 'success') return MoodLightLevel.calm;
    final stress = ((r['stress_indicator'] ?? 0) as num).toDouble();
    final scores = r['emotion_scores'];
    final sad = scores is Map ? ((scores['sad'] ?? 0) as num).toDouble() : 0.0;
    return moodLightLevel(stress: stress, sad: sad);
  }

  Widget _buildScanMoodCard() {
    final stress = ((_result!['stress_indicator'] ?? 0) as num).toDouble();
    final level = _moodLevel;
    return ScanMoodCard(
      level: level,
      stress: stress,
      onReset: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MoodResetScreen(
            entryId: '',
            beforeStress: stress,
            beforeMoodLabel: moodLightInfo(level).label,
            breathing: Map<String, dynamic>.from(defaultBreathing),
          ),
        ),
      ),
    );
  }

  Widget _buildStressCard() {
    final double stress =
        ((_result!['stress_indicator'] ?? 0) as num).toDouble().clamp(0.0, 1.0);
    final band = stressBand(stress);
    final color = band == StressBand.high
        ? Colors.redAccent
        : band == StressBand.moderate
            ? amber
            : green;
    final word = band == StressBand.high
        ? 'High · stressed'
        : band == StressBand.moderate
            ? 'Moderate · uneasy'
            : 'Low · calm';

    return _glassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardLabel('STRESS LEVEL'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${(stress * 100).round()}%',
                style: GoogleFonts.outfit(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                word,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            const markerW = 4.0;
            return SizedBox(
              height: 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Row(
                        children: [
                          Expanded(child: Container(height: 10, color: green)),
                          Expanded(child: Container(height: 10, color: amber)),
                          Expanded(
                              child: Container(height: 10, color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth - markerW) * stress,
                    top: 0,
                    child: Container(
                      width: markerW,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Low', style: TextStyle(fontSize: 10, color: Colors.white38)),
              Text('Moderate', style: TextStyle(fontSize: 10, color: Colors.white38)),
              Text('High', style: TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ),
        ],
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _buildExpressionCard() {
    final scores = Map<String, dynamic>.from(_result!['emotion_scores'] ?? {});
    final sorted = scores.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    final top = sorted.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();
    final topSum =
        top.fold<double>(0, (s, e) => s + (e.value as num).toDouble());
    final other = (1 - topSum).clamp(0.0, 1.0);
    const colors = [cyan, green, amber];
    final values = [
      for (final e in top) (e.value as num).toDouble(),
      if (other > 0.005) other,
    ];
    final paints = [...colors.take(top.length), if (other > 0.005) const Color(0xFF3A4452)];
    final stress =
        ((_result!['stress_indicator'] ?? 0) as num).toDouble().clamp(0.0, 1.0);
    final dominant = _cap(top.first.key);

    return _glassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardLabel('EXPRESSION'),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(112, 112),
                      painter: _DonutPainter(values: values, colors: paints),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dominant,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const Text('dominant',
                            style: TextStyle(fontSize: 10, color: Colors.white38)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < top.length; i++)
                      _legendRow(
                        paints[i],
                        _cap(top[i].key),
                        (top[i].value as num).toDouble(),
                      ),
                    if (other > 0.005)
                      _legendRow(paints.last, 'Other', other),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              stress >= 0.3
                  ? 'Reading: signs of ${stress >= 0.5 ? 'strong' : 'some'} stress in the face (sad, angry, fear or disgust).'
                  : 'Reading: mostly ${top.first.key.toLowerCase()} face with no strong stress signal.',
              style: const TextStyle(fontSize: 12, color: Colors.white60, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// The scan result's lasting history: a 4 week calendar of daily stress.
  /// Today's cell already includes the scan that was just taken.
  MoodHeatmap get _heatmap {
    final entries = List<HistoryEntry>.of(_heatEntries);
    if (_result != null && _result!['status'] == 'success') {
      entries.add(HistoryEntry.fromJson({
        'entry_id': 'LIVE',
        'created_at': DateTime.now().toIso8601String(),
        'comparison': {'facial_emotion': _result},
      }));
    }
    return buildMoodHeatmap(entries, DateTime.now());
  }

  Future<void> _loadHeat() async {
    try {
      final results = await Future.wait([
        ApiService.fetchHistory(AppState.userId, limit: 120),
        ApiService.fetchFaceChecks(AppState.userId, limit: 120),
      ]);
      if (!mounted) return;
      setState(() {
        _heatEntries = [
          for (final list in results)
            for (final json in list) HistoryEntry.fromJson(json),
        ];
      });
    } catch (_) {
      // the heatmap is optional here, so a failed load just leaves it empty
    }
  }

  Color _pasColor(num pas) {
    if (pas >= 70) return greenBright;
    if (pas >= 50) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Widget _buildContinueButton() =>
      ScanContinueButton(onTap: _continueToForm, color: green);

  // ---------------------------------------------------------------------
  // Diary mood tab
  // ---------------------------------------------------------------------

  Widget _buildDiaryMoodCard() {
    if (_result == null || _result!['status'] != 'success') {
      return _glassCard(
        padding: const EdgeInsets.all(28),
        child: const Center(
          child: Text(
            'Capture a facial scan first to see your mood summary.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 15),
          ),
        ),
      );
    }

    final mood = _deriveMoodResult();
    final double confidence =
        ((_result!['confidence'] ?? 0) as num).toDouble().clamp(0.0, 1.0);
    final double stress =
        ((_result!['stress_indicator'] ?? 0) as num).toDouble().clamp(0.0, 1.0);
    final moodColor = stress > 0.5
        ? Colors.redAccent
        : stress > 0.3
        ? amber
        : green;
    final stressLabel = stress > 0.5
        ? 'High'
        : stress > 0.3
        ? 'Moderate'
        : 'Low';
    final reliable = mood['reliable'] == true;

    final scores = Map<String, dynamic>.from(_result!['emotion_scores'] ?? {});
    final topEmotions = scores.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return Column(
      children: [
        // Hero: the mood, how sure the scan is, and where it sits between
        // stressed and calm.
        _glassCard(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
          child: Column(
            children: [
              SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(108, 108),
                      painter: GradientRingPainter(
                        progress: confidence,
                        colors: [moodColor, moodColor],
                        strokeWidth: 9,
                      ),
                    ),
                    Text(mood['emoji'], style: const TextStyle(fontSize: 40)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                mood['label'],
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                reliable
                    ? 'Detected with ${(confidence * 100).round()}% confidence'
                    : 'Facial signal was ambiguous — try a clearer expression',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: reliable ? Colors.white38 : amber,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _moodPill(
                    reliable ? 'Reliable scan' : 'Unclear scan',
                    reliable ? green : amber,
                    reliable ? Icons.check_rounded : Icons.help_outline_rounded,
                  ),
                  _moodPill(
                    'Stress ${(stress * 100).round()}% · $stressLabel',
                    moodColor,
                    null,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _calmSpectrum(1 - stress),
            ],
          ),
        ),
        const SizedBox(height: 14),

        if (topEmotions.isNotEmpty)
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardLabel('TOP EMOTIONS'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < topEmotions.take(3).length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _emotionTile(
                          topEmotions[i].key,
                          (topEmotions[i].value as num).toDouble(),
                          highlight: i == 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        if (topEmotions.isNotEmpty) const SizedBox(height: 14),

        if (_history.isNotEmpty) ...[
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _cardLabel('LAST ${_history.length} ENTRIES'),
                    const Text(
                      'Perception score',
                      style: TextStyle(fontSize: 11, color: green),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _recentBars(),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        _glassCard(
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: moodColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  stress > 0.4
                      ? Icons.self_improvement_rounded
                      : Icons.center_focus_strong_rounded,
                  color: moodColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardLabel('SUGGESTION'),
                    const SizedBox(height: 5),
                    Text(
                      stress > 0.4
                          ? 'Take a short break before your next task.'
                          : 'You seem settled — good time to focus.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _moodPill(String text, Color color, IconData? icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Stressed -> Neutral -> Calm track with a marker at [position] (0..1).
  Widget _calmSpectrum(double position) {
    final p = position.clamp(0.0, 1.0);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const markerW = 4.0;
            return SizedBox(
              height: 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Row(
                        children: [
                          Expanded(child: Container(height: 10, color: Colors.redAccent)),
                          Expanded(child: Container(height: 10, color: amber)),
                          Expanded(child: Container(height: 10, color: green)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (c.maxWidth - markerW) * p,
                    top: 0,
                    child: Container(
                      width: markerW,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Stressed', style: TextStyle(fontSize: 10, color: Colors.white38)),
            Text('Neutral', style: TextStyle(fontSize: 10, color: Colors.white38)),
            Text('Calm', style: TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ),
      ],
    );
  }

  static const _emotionEmoji = {
    'happy': '🙂',
    'neutral': '😐',
    'sad': '😔',
    'angry': '😠',
    'fear': '😨',
    'disgust': '🤢',
    'surprise': '😮',
  };

  Widget _emotionTile(String name, double value, {required bool highlight}) {
    final label = name.isEmpty
        ? name
        : '${name[0].toUpperCase()}${name.substring(1)}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? cyan : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          Text(
            _emotionEmoji[name.toLowerCase()] ?? '🙂',
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(height: 4),
          Text(
            '${(value * 100).round()}%',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  /// One bar per recent analysed entry, taller and greener = better score.
  Widget _recentBars() {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SizedBox(
      height: 78,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: _history.map((e) {
          final pas =
              ((e['pas_score'] ?? 0) as num).toDouble().clamp(0.0, 100.0).toDouble();
          final ms = entryTimestampMs(e['entry_id']?.toString() ?? '');
          final day = ms == null
              ? ''
              : letters[DateTime.fromMillisecondsSinceEpoch(ms).weekday - 1];
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                width: 26,
                height: 8 + pas / 100 * 48,
                decoration: BoxDecoration(
                  color: _pasColor(pas),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                    bottom: Radius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(day, style: const TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

/// Four viewfinder corners, drawn in the card that holds the photo.
class _BracketPainter extends CustomPainter {
  final Color color;
  const _BracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 16.0;
    const len = 26.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * len, y), paint);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * len), paint);
    }

    corner(inset, inset, 1, 1);
    corner(size.width - inset, inset, -1, 1);
    corner(inset, size.height - inset, 1, -1);
    corner(size.width - inset, size.height - inset, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter old) => old.color != color;
}

/// A flat donut: one arc per value, in the matching colour.
class _DonutPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  const _DonutPainter({required this.values, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2,
        size.width - stroke, size.height - stroke);
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.values != values || old.colors != colors;
}
