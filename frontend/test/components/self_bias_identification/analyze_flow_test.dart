import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/analyzing_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/face_check_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';

const _face = {
  'status': 'success',
  'dominant_emotion': 'fear',
  'stress_indicator': 0.48,
  'emotion_scores': {'fear': 0.48},
  'cropped_face_base64': 'AAAA',
};

const _support = {
  'mood': {'state': 'uneasy', 'label': 'Uneasy', 'stress': 0.48, 'source': 'camera'},
  'needs_reset': true,
  'escalate': false,
  'reason': '',
  'actions': [],
  'trend': {'values': [0.48], 'direction': 'steady'},
};

/// Answers /analyze-from-diary with [analysis] and /face-check with a Mood
/// Support, and records the paths that were asked for.
List<String> _api(Map<String, dynamic> analysis, {String? state}) {
  final paths = <String>[];
  ApiClient.clientOverride = MockClient((request) async {
    paths.add(request.url.path);
    Map<String, dynamic> body = {};
    if (request.url.path.contains('diary-status')) {
      body = {'state': ?state};
    } else if (request.url.path.contains('analyze-from-diary')) {
      body = analysis;
    } else if (request.url.path.contains('face-check')) {
      final sent = jsonDecode(request.body) as Map;
      // The photo must never be sent along.
      expect((sent['facial_emotion'] as Map).containsKey('cropped_face_base64'), isFalse);
      body = {
        'status': 'success',
        'entry_id': 'FACE_1',
        'facial_emotion': sent['facial_emotion'],
        'mood_support': _support,
      };
    }
    return http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});
  });
  return paths;
}

Future<void> _open(
  WidgetTester tester,
  Map<String, dynamic>? face, {
  Finder? until,
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AnalyzingScreen(facialResult: face)),
          ),
          child: const Text('home'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('home'));
  await tester.pump();
  // The fake answers instantly; the sensors have no plugins in a test and
  // fail at once, so a few frames are enough.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    // Stop as soon as the screen is there: a toast only stays for a few seconds.
    if (until != null && until.evaluate().isNotEmpty) break;
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.userId = 'u1';
    // A phone's location plugin never answers in a test; say "location off".
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => false,
    );
  });

  tearDown(() => ApiClient.clientOverride = null);

  testWidgets('no diary entry but a good face scan opens the Face check',
      (tester) async {
    final paths = _api({'status': 'no_entry_found'});
    await _open(tester, _face);
    expect(find.byType(FaceCheckScreen), findsOneWidget);
    expect(find.text('This is a face check only'), findsOneWidget);
    expect(find.textContaining('no diary entry yet'), findsOneWidget);
    expect(paths.any((p) => p.contains('face-check')), isTrue);

    // Back goes to where the scan was started, not to the analyzing screen.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('no diary entry and no face scan keeps the No diary entry screen',
      (tester) async {
    final paths = _api({'status': 'no_entry_found'});
    await _open(tester, null);
    expect(find.text('No diary entry found'), findsOneWidget);
    expect(find.byType(FaceCheckScreen), findsNothing);
    expect(paths.any((p) => p.contains('face-check')), isFalse);
  });

  const saved = {
    'entry_id': 'ENT_LEADER_1',
    'pas_score': 80,
    'pas_level': 'Good Alignment',
    'primary_bias': {'bias_type': 'accurate_perception', 'confidence': 0.9},
    'comparison': {},
    'additional_indicators': [],
    'suggested_actions': [],
    'reflection_text': '',
  };

  testWidgets('already analysed and no face scan shows the saved result',
      (tester) async {
    _api({'status': 'already_analyzed', 'result': saved});
    await _open(tester, null, until: find.text('TruthLens Analysis'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('TruthLens Analysis'), findsOneWidget);
    expect(find.textContaining('already analyzed'), findsOneWidget);
    expect(find.byType(FaceCheckScreen), findsNothing);
  });

  testWidgets('already analysed with a face scan opens the Face check instead',
      (tester) async {
    final paths = _api({'status': 'already_analyzed', 'result': saved});
    await _open(tester, _face);
    expect(find.byType(FaceCheckScreen), findsOneWidget);
    expect(find.text('TruthLens Analysis'), findsNothing);
    expect(find.textContaining('already analyzed'), findsOneWidget);
    expect(paths.any((p) => p.contains('face-check')), isTrue);
  });

  testWidgets('an entry that is too old with a face scan opens the Face check',
      (tester) async {
    _api({'status': 'no_entry_found', 'reason': 'stale', 'entry_age_hours': 30});
    await _open(tester, _face);
    expect(find.byType(FaceCheckScreen), findsOneWidget);
    expect(find.text('TruthLens Analysis'), findsNothing);
    expect(find.textContaining('too old'), findsOneWidget);
  });

  testWidgets('an entry that is too old and no face scan says it is too old',
      (tester) async {
    _api({'status': 'no_entry_found', 'reason': 'stale', 'entry_age_hours': 30});
    await _open(tester, null);
    expect(find.text('No recent diary entry'), findsOneWidget);
    expect(find.textContaining('too old'), findsOneWidget);
    expect(find.text('No diary entry found'), findsNothing);
  });

  group('the Analyzing screen says what is really happening', () {
    /// Holds the face-check answer back so the screen can be looked at mid-way.
    Completer<void> hold(String state) {
      final gate = Completer<void>();
      ApiClient.clientOverride = MockClient((request) async {
        final path = request.url.path;
        Map<String, dynamic> body = {};
        if (path.contains('diary-status')) {
          body = {'state': state};
        } else if (path.contains('face-check')) {
          await gate.future;
          body = {
            'status': 'success',
            'entry_id': 'FACE_1',
            'facial_emotion': (jsonDecode(request.body) as Map)['facial_emotion'],
            'mood_support': _support,
          };
        }
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      });
      return gate;
    }

    for (final state in ['none', 'stale', 'analyzed']) {
      testWidgets('face only ($state): no bias classifier, no reflection',
          (tester) async {
        final gate = hold(state);
        tester.view.physicalSize = const Size(800, 3200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: AnalyzingScreen(facialResult: _face),
        ));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Checking your scan'), findsOneWidget);
        expect(find.text('Reading your scan'), findsOneWidget);
        expect(find.text('Preparing your face check'), findsOneWidget);
        expect(find.text('Running bias classifier'), findsNothing);
        expect(find.text('Generating your reflection'), findsNothing);
        expect(find.text('Analyzing your entry'), findsNothing);

        gate.complete();
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(FaceCheckScreen), findsOneWidget);
      });
    }

    testWidgets('face only goes straight to the face check, without a bias analysis',
        (tester) async {
      final paths = _api({'status': 'success'}, state: 'none');
      await _open(tester, _face);
      expect(find.byType(FaceCheckScreen), findsOneWidget);
      expect(paths.any((p) => p.contains('analyze-from-diary')), isFalse);
    });

    testWidgets('a new entry keeps the bias analysis wording', (tester) async {
      _api({'status': 'no_entry_found'}, state: 'new');
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AnalyzingScreen(facialResult: _face)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Running bias classifier'), findsOneWidget);
      expect(find.text('Analyzing your entry'), findsOneWidget);
      expect(find.text('Checking your scan'), findsNothing);
    });

    testWidgets('a new entry is analysed as before', (tester) async {
      final paths = _api({'status': 'no_entry_found'}, state: 'new');
      await _open(tester, _face);
      expect(paths.any((p) => p.contains('analyze-from-diary')), isTrue);
    });

    testWidgets('without a face scan the diary status is not even asked',
        (tester) async {
      final paths = _api({'status': 'no_entry_found'}, state: 'none');
      await _open(tester, null);
      expect(paths.any((p) => p.contains('diary-status')), isFalse);
      expect(find.text('No diary entry found'), findsOneWidget);
    });

    testWidgets('if the status cannot be read, the usual route is used',
        (tester) async {
      final paths = _api({'status': 'no_entry_found'}); // no state answered
      await _open(tester, _face);
      expect(paths.any((p) => p.contains('analyze-from-diary')), isTrue);
      expect(find.byType(FaceCheckScreen), findsOneWidget);
    });
  });
}
