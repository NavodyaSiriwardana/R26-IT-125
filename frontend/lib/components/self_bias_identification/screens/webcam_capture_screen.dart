import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_palette.dart';
import 'package:frontend/components/self_bias_identification/services/consent_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';

/// Opens the live webcam capture and returns the photo as JPEG bytes, or
/// null when the user backs out / continues without the camera. Shared by
/// the Expression Scan and the Mood Reset re-check.
Future<Uint8List?> captureFromWebcam(BuildContext context) async {
  // The camera is only used after informed consent (shown once per user).
  if (!await ConsentService.ensure(context)) return null;
  if (!context.mounted) return null;
  return Navigator.push<Uint8List>(
    context,
    MaterialPageRoute(builder: (_) => const WebcamCaptureScreen()),
  );
}

enum _CamState { starting, live, countdown, capturing, error }

class WebcamCaptureScreen extends StatefulWidget {
  const WebcamCaptureScreen({super.key});

  @override
  State<WebcamCaptureScreen> createState() => _WebcamCaptureScreenState();
}

class _WebcamCaptureScreenState extends State<WebcamCaptureScreen> {
  static const double _size = 260;

  CameraController? _controller;
  _CamState _state = _CamState.starting;
  String _errorTitle = '';
  String _errorDetail = '';
  int _count = 3;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _startCamera() async {
    setState(() => _state = _CamState.starting);
    await _controller?.dispose();
    _controller = null;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail(
          'No webcam found',
          'Plug in your webcam, or check that it opens in the Camera app.',
        );
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _state = _CamState.live;
      });
    } on CameraException catch (e) {
      final denied = e.code.toLowerCase().contains('access') ||
          e.code.toLowerCase().contains('denied');
      _fail(
        denied ? 'Camera access is blocked' : 'Camera unavailable',
        denied
            ? 'Allow camera access for desktop apps in Windows settings.'
            : 'The webcam could not be opened. It may be in use by another app.',
      );
    } catch (_) {
      _fail(
        'Camera unavailable',
        'The webcam could not be opened. It may be in use by another app.',
      );
    }
  }

  void _fail(String title, String detail) {
    if (!mounted) return;
    setState(() {
      _errorTitle = title;
      _errorDetail = detail;
      _state = _CamState.error;
    });
  }

  Future<void> _capture() async {
    if (_state != _CamState.live || _controller == null) return;

    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() {
        _count = i;
        _state = _CamState.countdown;
      });
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => _state = _CamState.capturing);

    try {
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.pop(context, bytes);
    } catch (_) {
      _fail('Could not take the photo', 'Please try again.');
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: [
                  _topBar(),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Expression Scan',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtitle(),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _stage()),
                  ..._bottom(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    switch (_state) {
      case _CamState.starting:
        return 'Webcam check, then emotion and stress analysis.';
      case _CamState.live:
        return 'Look at the camera with a relaxed face.';
      case _CamState.countdown:
      case _CamState.capturing:
        return 'Photo is taken after the countdown.';
      case _CamState.error:
        return 'We could not open a webcam.';
    }
  }

  Widget _topBar() {
    final (label, color) = switch (_state) {
      _CamState.starting => ('CONNECTING', MoodPalette.cyan),
      _CamState.live => ('LIVE', MoodPalette.mint),
      _CamState.countdown => ('HOLD STILL', MoodPalette.mint),
      _CamState.capturing => ('CAPTURING', MoodPalette.cyan),
      _CamState.error => ('NO CAMERA', MoodPalette.coral),
    };
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stage() {
    if (_state == _CamState.error) return _errorStage();

    final live = _state != _CamState.starting && _controller != null;
    final good = _state == _CamState.live || _state == _CamState.countdown;
    final ringColor = good
        ? MoodPalette.mint
        : Colors.white.withValues(alpha: 0.2);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
                border: Border.all(color: ringColor, width: 3),
              ),
              child: ClipOval(
                child: live
                    ? Opacity(
                        opacity: _state == _CamState.countdown ? 0.7 : 1,
                        child: _preview(),
                      )
                    : Icon(
                        Icons.videocam_outlined,
                        size: 64,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
              ),
            ),
            if (_state == _CamState.starting)
              const SizedBox(
                width: _size,
                height: _size,
                child: CircularProgressIndicator(
                  color: MoodPalette.cyan,
                  strokeWidth: 3,
                ),
              ),
            if (_state == _CamState.countdown)
              Text(
                '$_count',
                style: GoogleFonts.outfit(
                  fontSize: 84,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          switch (_state) {
            _CamState.starting =>
              'Looking for your webcam. Allow camera access if Windows asks.',
            _CamState.live => 'Centre your face in the circle, in good light.',
            _CamState.countdown => 'Hold still...',
            _ => 'Taking the photo...',
          },
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  /// True where the preview must be mirrored by us to look like a selfie
  /// mirror: a computer webcam. Phones' front cameras are mirrored already.
  static bool get needsManualMirror =>
      kIsWeb || !(Platform.isAndroid || Platform.isIOS);

  /// Square, centre-cropped, mirrored (selfie-style) camera preview.
  ///
  /// The preview is given only a width. CameraPreview then works out its own
  /// height from the camera's real shape (it is tall on a phone held upright
  /// and wide on a laptop), and the FittedBox crops that to the square without
  /// stretching it. Forcing a height here is what squashed faces before.
  Widget _preview() {
    final controller = _controller!;
    return SizedBox(
      width: _size,
      height: _size,
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _size,
          // A selfie preview is a mirror. On Android and iOS the camera plugin
          // already mirrors the front camera, so mirroring again would undo it
          // (and the photo would look flipped next to the preview). A laptop
          // webcam is not mirrored by the plugin, so it is mirrored here.
          child: needsManualMirror
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(math.pi),
                  child: CameraPreview(controller),
                )
              : CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _errorStage() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.04),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Icon(
              Icons.videocam_off_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MoodPalette.coral.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MoodPalette.coral.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: MoodPalette.coral,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _errorTitle,
                        style: const TextStyle(
                          color: MoodPalette.coral,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _errorDetail,
                        style: const TextStyle(
                          color: MoodPalette.coral,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(
              '1. Plug in your webcam, or check it opens in the Camera app.\n'
              '2. Open Settings > Privacy > Camera and allow desktop apps.\n'
              '3. Close other apps that may be using the camera, then press Try again.',
              style: TextStyle(
                fontSize: 14,
                height: 1.75,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _bottom() {
    switch (_state) {
      case _CamState.live:
        return [
          GestureDetector(
            onTap: _capture,
            child: Container(
              width: 74,
              height: 74,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: MoodPalette.mint.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [MoodPalette.mint, MoodPalette.cyan],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Capture',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          _skipLink('Skip for now'),
        ];
      case _CamState.error:
        return [
          GestureDetector(
            onTap: _startCamera,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [MoodPalette.mint, MoodPalette.cyan],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.refresh_rounded,
                    color: Color(0xFF0A0E14),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Try again',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0A0E14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _skipLink('Continue without the camera'),
        ];
      default:
        return [
          const SizedBox(height: 74),
          _skipLink('Skip for now'),
        ];
    }
  }

  Widget _skipLink(String label) {
    return TextButton(
      onPressed: () {
        AppToast.info(context, 'Skipped the camera. You can scan again any time.');
        Navigator.pop(context);
      },
      child: Text(
        label,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
      ),
    );
  }
}
