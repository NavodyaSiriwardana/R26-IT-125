import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/analyzing_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/gradient_ring_painter.dart';
import 'package:frontend/components/self_bias_identification/widgets/tilt_card.dart';

class FacialCaptureScreen extends StatefulWidget {
  const FacialCaptureScreen({super.key});

  @override
  State<FacialCaptureScreen> createState() => _FacialCaptureScreenState();
}

class _FacialCaptureScreenState extends State<FacialCaptureScreen>
    with SingleTickerProviderStateMixin {
  File? _imageFile;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _result;
  String? _errorMessage;
  bool _facialTabSelected = true;
  List<Map<String, dynamic>> _history = [];

  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

  static const green = Color(0xFF5DCAA5);
  static const greenBright = Color(0xFF4ADE80);
  static const cyan = Color(0xFF22D3EE);
  static const amber = Color(0xFFFFCB6B);
  static const deepOrange = Color(0xFFFF7043);
  static const cardBg = Color(0xFF0A1710);

  @override
  void initState() {
    super.initState();
    _loadHistory();

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
      final response = await http.get(
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
          final aTime = int.tryParse(aId.replaceAll(RegExp(r'\D'), '')) ?? 0;
          final bTime = int.tryParse(bId.replaceAll(RegExp(r'\D'), '')) ?? 0;
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

  /// Many Android camera apps (Samsung's especially) save the photo with
  /// an EXIF orientation tag rather than physically rotating the pixels,
  /// so the file image_picker hands back can come out sideways when
  /// displayed or sent to the backend for face detection. This decodes
  /// the JPEG, bakes the EXIF orientation into the actual pixel data (so
  /// it reads as "normal" from then on), and overwrites the file.
  Future<File> _normalizeOrientation(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return file;
      final upright = img.bakeOrientation(decoded);
      await file.writeAsBytes(img.encodeJpg(upright, quality: 90));
    } catch (_) {
      // Fall through with the original file — better an occasionally
      // rotated photo than a capture that hard-fails.
    }
    return file;
  }

  Future<void> _captureImage() async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
      );
      if (photo == null) return;

      final uprightFile = await _normalizeOrientation(File(photo.path));

      setState(() {
        _imageFile = uprightFile;
        _isAnalyzing = true;
        _errorMessage = null;
        _result = null;
      });

      _scanController.repeat();
      await _analyzeExpression();
      _scanController.stop();
      _scanController.reset();
    } catch (e) {
      setState(() {
        _errorMessage =
            'Could not access the camera. Please check camera permissions in your device settings.';
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _analyzeExpression() async {
    try {
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
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
          _errorMessage = 'Server error: ${response.statusCode}';
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error: $e';
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
    final bool isMultipleFaces =
        _result != null && _result!['status'] == 'multiple_faces_detected';
    final bool showWarning =
        isNoFace || isPartialFace || isBlurryImage || isMultipleFaces;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -1.2),
                    radius: 1.1,
                    colors: [green.withValues(alpha: 0.16), Colors.transparent],
                  ),
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
                        fontSize: 12, color: Colors.white38, height: 1.4),
                  ),
                  const SizedBox(height: 24),

                  _buildTabToggle(),
                  const SizedBox(height: 24),

                  _facialTabSelected ? _buildCameraCard() : _buildDiaryMoodCard(),

                  if (_facialTabSelected) ...[
                    const SizedBox(height: 28),
                    _buildCaptureButton(),
                  ],

                  if (_isAnalyzing) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Analyzing expression...',
                        style: GoogleFonts.outfit(
                            color: Colors.white54, fontSize: 12),
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
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildStressCard()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildMoodHeatmapCard()),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildContinueButton(),
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
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
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
        gradient: selected ? const LinearGradient(colors: [green, cyan]) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
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
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.015),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _cardLabel(String text) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 10,
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
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Facial scan tab
  // ---------------------------------------------------------------------

  Widget _buildCameraCard() {
    final hasImage = _imageFile != null;
    final croppedFace = _result != null && _result!['cropped_face_base64'] != null
        ? base64Decode(_result!['cropped_face_base64'])
        : null;

    return Center(
      child: Column(
      children: [
        Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: green.withValues(alpha: 0.18),
                blurRadius: 60,
                spreadRadius: 6,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_isAnalyzing)
                AnimatedBuilder(
                  animation: _scanAnimation,
                  builder: (context, child) => Transform.rotate(
                    angle: _scanAnimation.value * 2 * math.pi,
                    child: child,
                  ),
                  child: CustomPaint(
                    size: const Size(260, 260),
                    painter: const GradientRingPainter(
                      progress: 0.22,
                      colors: [green, cyan],
                      strokeWidth: 3,
                      glowDot: true,
                    ),
                  ),
                )
              else
                CustomPaint(
                  size: const Size(260, 260),
                  painter: const GradientRingPainter(
                    progress: 1.0,
                    colors: [green, cyan],
                    strokeWidth: 3,
                  ),
                ),
              ClipOval(
                child: SizedBox(
                  width: 224,
                  height: 224,
                  child: croppedFace != null
                      ? Image.memory(croppedFace, fit: BoxFit.cover)
                      : hasImage
                          ? Image.file(_imageFile!, fit: BoxFit.cover)
                          : Container(
                              color: cardBg,
                              child: Icon(
                                Icons.face_outlined,
                                size: 64,
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Text(
            _isAnalyzing
                ? 'Scanning facial features...'
                : hasImage
                    ? 'Face captured — ready to analyze'
                    : 'Align face within the frame',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 14),
          _buildDiagnosticChips(),
        ],
      ],
      ),
    );
  }

  Widget _buildDiagnosticChips() {
    final isNoFace = _result!['status'] == 'no_face_detected';
    final isBlurry = _result!['status'] == 'blurry_image';
    final isPartial = _result!['status'] == 'partial_face';
    final isMultipleFaces = _result!['status'] == 'multiple_faces_detected';

    final faceChip = isNoFace
        ? _diagnosticChip(Icons.close, 'No face detected', Colors.redAccent)
        : isMultipleFaces
            ? _diagnosticChip(
                Icons.close, 'Multiple faces detected', Colors.redAccent)
            : _diagnosticChip(Icons.check, 'Face detected', green);

    final qualityChip = isBlurry
        ? _diagnosticChip(Icons.close, 'Image blurry', Colors.orangeAccent)
        : isPartial
            ? _diagnosticChip(
                Icons.close, 'Face partially visible', Colors.orangeAccent)
            : _diagnosticChip(Icons.check, 'Image quality good', green);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [faceChip, if (!isNoFace && !isMultipleFaces) qualityChip],
    );
  }

  Widget _diagnosticChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
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
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75)),
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
                      gradient: const LinearGradient(colors: [green, cyan]),
                      boxShadow: [
                        BoxShadow(
                          color: green.withValues(alpha: 0.35),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
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
            _imageFile == null ? 'Tap to capture' : 'Retake photo',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStressCard() {
    final double stress = (_result!['stress_indicator'] ?? 0).toDouble().clamp(
      0,
      1,
    );
    final label = stress > 0.6
        ? 'High'
        : stress > 0.3
        ? 'Moderate'
        : 'Low';
    final gradientColors = stress > 0.6
        ? const [Colors.redAccent, deepOrange]
        : stress > 0.3
            ? const [amber, deepOrange]
            : const [green, greenBright];
    final labelColor = stress > 0.6
        ? Colors.redAccent
        : stress > 0.3
        ? Colors.orangeAccent
        : greenBright;

    return TiltCard(
      borderRadius: BorderRadius.circular(16),
      child: _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardLabel('STRESS LEVEL'),
          const SizedBox(height: 14),
          Center(
            child: SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(84, 84),
                    painter: GradientRingPainter(
                      progress: stress,
                      colors: gradientColors,
                      strokeWidth: 8,
                    ),
                  ),
                  Text(
                    '${(stress * 100).round()}%',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: labelColor,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Color _pasColor(num pas) {
    if (pas >= 70) return greenBright;
    if (pas >= 50) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Widget _buildMoodHeatmapCard() {
    return TiltCard(
      borderRadius: BorderRadius.circular(16),
      child: _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardLabel('MOOD HEATMAP'),
          const SizedBox(height: 12),
          if (_history.isEmpty)
            const Text(
              'No entries yet',
              style: TextStyle(fontSize: 11, color: Colors.white38),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _history.map((e) {
                final pas = (e['pas_score'] ?? 0) as num;
                final color = _pasColor(pas);
                return Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color.withValues(alpha: 0.85), color],
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          const Text(
            '● low  ● moderate  ● good',
            style: TextStyle(fontSize: 9, color: Colors.white38),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: _continueToForm,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [green, cyan]),
            boxShadow: [
              BoxShadow(
                color: green.withValues(alpha: 0.3),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              'Continue to diary entry',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF04342C),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }

    final mood = _deriveMoodResult();
    final confidence = (_result!['confidence'] ?? 0).toDouble();
    final stress = (_result!['stress_indicator'] ?? 0).toDouble().clamp(0, 1);
    final stressColor = stress > 0.5
        ? Colors.redAccent
        : stress > 0.3
        ? Colors.orangeAccent
        : greenBright;
    final stressLabel = stress > 0.5
        ? 'High'
        : stress > 0.3
        ? 'Moderate'
        : 'Low';

    final scores = Map<String, dynamic>.from(_result!['emotion_scores'] ?? {});
    final topEmotions = scores.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return Column(
      children: [
        _glassCard(
          padding: const EdgeInsets.all(26),
          child: Column(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(96, 96),
                      painter: GradientRingPainter(
                        progress: confidence.clamp(0, 1),
                        colors: [
                          stressColor.withValues(alpha: 0.7),
                          stressColor,
                        ],
                        strokeWidth: 7,
                      ),
                    ),
                    Text(mood['emoji'], style: const TextStyle(fontSize: 30)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                mood['label'],
                style: GoogleFonts.outfit(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                mood['reliable']
                    ? 'Detected with ${(confidence * 100).round()}% confidence'
                    : 'Facial signal was ambiguous — try a clearer expression',
                style: TextStyle(
                  fontSize: 12,
                  color: mood['reliable']
                      ? Colors.white38
                      : Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardLabel('EMOTION BREAKDOWN'),
              const SizedBox(height: 12),
              ...topEmotions.take(3).map((e) {
                final value = (e.value as num).toDouble();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            e.key,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            '${(value * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 5,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation(green),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardLabel('STRESS'),
                    const SizedBox(height: 8),
                    Text(
                      '${(stress * 100).round()}%',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: stressColor,
                      ),
                    ),
                    Text(
                      stressLabel,
                      style: TextStyle(fontSize: 11, color: stressColor),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cardLabel('TIP'),
                    const SizedBox(height: 8),
                    Text(
                      stress > 0.4
                          ? 'Take a short break before your next task.'
                          : 'You seem settled — good time to focus.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
