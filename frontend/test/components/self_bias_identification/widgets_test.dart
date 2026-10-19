import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/consent_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/mood_reset_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/webcam_capture_screen.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_support_card.dart';

Map<String, dynamic> _moodSupport({
  String state = 'stressed',
  String label = 'Stressed',
  double? stress = 0.62,
  bool needsReset = true,
  bool escalate = false,
  bool mismatch = true,
}) =>
    {
      'mood': {
        'state': state,
        'label': label,
        'stress': stress,
        'source': 'camera',
        'reported': 'motivated',
        'mismatch': mismatch,
      },
      'needs_reset': needsReset,
      'reason': 'Your camera reading shows a 62% stress signal.',
      'actions': [
        {
          'id': 'walk',
          'title': 'Walk away from the screen',
          'detail': 'Water and daylight.',
          'minutes': 5,
          'kind': 'break'
        },
        {
          'id': 'split',
          'title': 'Split your next block in two',
          'detail': 'Two 45-minute blocks.',
          'minutes': 0,
          'kind': 'plan'
        },
      ],
      'trend': {
        'values': [0.28, 0.41, 0.55, 0.62],
        'direction': 'rising'
      },
      'escalate': escalate,
      'breathing': {'inhale': 4, 'hold': 7, 'exhale': 8, 'rounds': 6},
    };

const _face = {
  'status': 'success',
  'emotion_scores': {'sad': 0.31, 'angry': 0.18, 'fear': 0.13, 'neutral': 0.28},
};

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))));
  await tester.pump();
}

/// Starts the app on a screen with a button that opens [screen], like the real
/// navigation does, so `Navigator.pop(context, value)` has somewhere to go.
Future<void> _pumpRoot(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Opens [screen] from a button on a tall test screen, like real navigation,
/// and returns what the screen popped.
Future<void> _openFromButton(
  WidgetTester tester,
  Widget screen,
  void Function(Object?) onResult,
) async {
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => onResult(await Navigator.push<Object?>(
            context,
            MaterialPageRoute(builder: (_) => screen),
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Replaces the camera plugin's method channel so no real webcam is needed.
void _mockCamera(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/camera'),
    handler,
  );
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/camera'), null));
}

MoodResetScreen _resetScreen() => const MoodResetScreen(
      entryId: 'ENT_1',
      beforeStress: 0.62,
      beforeMoodLabel: 'Stressed',
      breathing: {'inhale': 4, 'hold': 7, 'exhale': 8, 'rounds': 6},
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    AppState.userId = 'u1';
    SharedPreferences.setMockInitialValues({});
  });

  group('MoodSupportCard', () {
    testWidgets('shows mood, reason, trend, actions and the reset button',
        (tester) async {
      await _pump(
        tester,
        MoodSupportCard(
          moodSupport: _moodSupport(),
          facialEmotion: Map<String, dynamic>.from(_face),
          entryId: 'ENT_1',
        ),
      );
      expect(find.text('Mood Support'), findsOneWidget);
      expect(find.text('Stressed · 62%'), findsOneWidget);
      expect(find.text('You reported: motivated'), findsOneWidget);
      expect(find.text('Rising'), findsOneWidget);
      expect(find.text('Walk away from the screen'), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('Sad'), findsOneWidget);
      expect(find.text('Start 2-min Mood Reset'), findsOneWidget);
    });

    testWidgets('no reset button and a hint when there is no camera reading',
        (tester) async {
      await _pump(
        tester,
        MoodSupportCard(
          moodSupport: _moodSupport(),
          facialEmotion: null,
          entryId: 'ENT_1',
        ),
      );
      expect(find.text('Start 2-min Mood Reset'), findsNothing);
      expect(find.textContaining('camera scan on your next entry'), findsOneWidget);
    });

    testWidgets('a calm mood offers no reset', (tester) async {
      await _pump(
        tester,
        MoodSupportCard(
          moodSupport: _moodSupport(
              state: 'calm', label: 'Calm', stress: 0.1, needsReset: false, mismatch: false),
          facialEmotion: Map<String, dynamic>.from(_face),
          entryId: 'ENT_1',
        ),
      );
      expect(find.text('Calm · 10%'), findsOneWidget);
      expect(find.text('Start 2-min Mood Reset'), findsNothing);
    });

    testWidgets('shows the care note after repeated high stress', (tester) async {
      await _pump(
        tester,
        MoodSupportCard(
          moodSupport: _moodSupport(escalate: true),
          facialEmotion: Map<String, dynamic>.from(_face),
          entryId: 'ENT_1',
        ),
      );
      expect(find.textContaining('high for several entries'), findsOneWidget);
    });

    testWidgets('the button opens the Mood Reset screen', (tester) async {
      await _pump(
        tester,
        MoodSupportCard(
          moodSupport: _moodSupport(),
          facialEmotion: Map<String, dynamic>.from(_face),
          entryId: 'ENT_1',
        ),
      );
      await tester.tap(find.text('Start 2-min Mood Reset'));
      await tester.pumpAndSettle();
      expect(find.text('Take two minutes to reset'), findsOneWidget);
    });
  });

  group('ConsentScreen', () {
    testWidgets('agree is blocked until the camera box is ticked', (tester) async {
      await _pumpRoot(tester, const ConsentScreen());
      expect(find.text('Before we use your camera'), findsOneWidget);
      expect(find.text('Using the camera is optional', skipOffstage: false), findsNothing);

      await tester.tap(find.text('I agree'));
      await tester.pump();
      // still on the consent screen: nothing was recorded
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('research_consent_v1_u1'), isNull);
      expect(find.text('Before we use your camera'), findsOneWidget);
    });

    testWidgets('ticking the box and agreeing stores consent', (tester) async {
      Object? result = 'unset';
      await _openFromButton(tester, const ConsentScreen(), (r) => result = r);

      await tester.tap(find.textContaining('I have read this and agree'));
      await tester.pump();
      await tester.tap(find.text('I agree'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('research_consent_v1_u1'), isTrue);
    });

    testWidgets('declining returns false and stores nothing', (tester) async {
      Object? result = 'unset';
      await _openFromButton(tester, const ConsentScreen(), (r) => result = r);

      await tester.tap(find.textContaining('No thanks'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('research_consent_v1_u1'), isNull);
    });
  });

  group('MoodResetScreen', () {
    testWidgets('ready screen shows the before reading and 1-5 rating',
        (tester) async {
      await _pumpRoot(tester, _resetScreen());
      await tester.pumpAndSettle();
      expect(find.text('Take two minutes to reset'), findsOneWidget);
      expect(find.text('Before: Stressed · 62% stress'), findsOneWidget);
      for (final n in ['1', '2', '3', '4', '5']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('Begin'), findsOneWidget);
    });

    testWidgets('breathing starts, with early exit locked until one round',
        (tester) async {
      await _pumpRoot(tester, _resetScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('4'));
      await tester.tap(find.text('Begin'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Inhale'), findsOneWidget);
      expect(find.text('Round 1 of 6 · 1:54 left'), findsOneWidget);
      expect(find.text('Finish one round to end early'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a full session leads to the self-rating, then the re-check',
        (tester) async {
      await _pumpRoot(tester, _resetScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('How stressed do you feel now?'), findsOneWidget);

      await tester.tap(find.text('2'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Nice work. One quick photo.'), findsOneWidget);
      expect(find.text('Capture'), findsOneWidget);
    });

    testWidgets('study mode assigns the quiet-rest control without guidance',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'study_mode_u1': true,
        'study_count_breathing_u1': 1,
      });
      await _pumpRoot(tester, _resetScreen());
      await tester.pumpAndSettle();
      expect(find.text('Rest quietly for two minutes'), findsOneWidget);
      expect(find.textContaining('do not do any breathing exercise'), findsOneWidget);

      await tester.tap(find.text('Begin'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Rest quietly'), findsOneWidget);
      expect(find.text('Inhale'), findsNothing);
      expect(find.textContaining('End early'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('study mode breathing session has no early exit',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'study_mode_u1': true,
        'study_count_control_u1': 1,
      });
      await _pumpRoot(tester, _resetScreen());
      await tester.pumpAndSettle();
      expect(find.text('Take two minutes to reset'), findsOneWidget);
      await tester.tap(find.text('Begin'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Inhale'), findsOneWidget);
      expect(find.textContaining('end early'), findsNothing);
      expect(find.text('End early'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('closing during breathing asks first, and Stay keeps going',
        (tester) async {
      await _pumpRoot(tester, _resetScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Leave the reset?'), findsOneWidget);

      await tester.tap(find.text('Stay'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Leave the reset?'), findsNothing);
      expect(find.text('Inhale'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Leave closes the reset', (tester) async {
      Object? popped = 'unset';
      await _openFromButton(tester, _resetScreen(), (r) => popped = r);
      await tester.tap(find.text('Begin'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Begin'), findsNothing);
      expect(find.text('open'), findsOneWidget);
      expect(popped, isNull);
    });

    testWidgets('closing before the session starts needs no confirmation',
        (tester) async {
      await _openFromButton(tester, _resetScreen(), (_) {});
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Leave the reset?'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('capturing asks for consent first', (tester) async {
      await _pumpRoot(tester, _resetScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();
      expect(find.text('Before we use your camera'), findsOneWidget);
    });
  });

  group('WebcamCaptureScreen', () {
    testWidgets('shows fix steps when no webcam is found', (tester) async {
      _mockCamera((call) async => call.method == 'availableCameras' ? <Object?>[] : null);
      await _pumpRoot(tester, const WebcamCaptureScreen());
      await tester.pumpAndSettle();
      expect(find.text('NO CAMERA'), findsOneWidget);
      expect(find.text('No webcam found'), findsOneWidget);
      expect(find.textContaining('Settings > Privacy > Camera'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Continue without the camera'), findsOneWidget);
    });

    testWidgets('explains blocked camera access', (tester) async {
      _mockCamera((call) async {
        throw PlatformException(code: 'CameraAccessDenied', message: 'denied');
      });
      await _pumpRoot(tester, const WebcamCaptureScreen());
      await tester.pumpAndSettle();
      expect(find.text('Camera access is blocked'), findsOneWidget);
    });

    testWidgets('Try again asks the camera again', (tester) async {
      var calls = 0;
      _mockCamera((call) async {
        if (call.method == 'availableCameras') calls++;
        return <Object?>[];
      });
      await _pumpRoot(tester, const WebcamCaptureScreen());
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });

    testWidgets('continuing without the camera returns nothing', (tester) async {
      _mockCamera((call) async => <Object?>[]);
      Object? result = 'unset';
      await _openFromButton(tester, const WebcamCaptureScreen(), (r) => result = r);
      await tester.tap(find.text('Continue without the camera'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });
}
