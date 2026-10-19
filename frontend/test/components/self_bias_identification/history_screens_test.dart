import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/bias_history_screen.dart';
import 'package:frontend/components/self_bias_identification/screens/facial_history_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';
import 'package:frontend/components/self_bias_identification/widgets/history_hub.dart';

/// Answers the history screens' requests from memory, instantly, so the tests
/// need no network and no real asynchronous waiting.
class _FakeApi {
  List<Map<String, dynamic>> history = [];
  List<Map<String, dynamic>> resets = [];
  List<Map<String, dynamic>> faceChecks = [];
  int historyStatus = 200;
  int resetsStatus = 200;
  final requested = <String>[];

  void start() {
    ApiClient.clientOverride = MockClient((request) async {
      requested.add(request.url.toString());
      if (request.url.path.contains('/face-checks/')) {
        return http.Response(
          jsonEncode({'checks': faceChecks}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      final isHistory = request.url.path.contains('/history/');
      final status = isHistory ? historyStatus : resetsStatus;
      final rows = isHistory ? history : resets;
      return http.Response(
        jsonEncode(status == 200
            ? {isHistory ? 'history' : 'resets': rows}
            : {'detail': 'down'}),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  void stop() => ApiClient.clientOverride = null;
}

final _now = DateTime.now();

String _ago({int days = 0, int minutes = 0}) =>
    'ENT_${_now.subtract(Duration(days: days, minutes: minutes)).millisecondsSinceEpoch}';

Map<String, dynamic> _row(
  String id,
  String bias,
  int pas,
  String category,
  int minutes, {
  Map<String, dynamic>? facial,
}) =>
    {
      'entry_id': id,
      'pas_score': pas,
      'pas_level': 'Good Alignment',
      'primary_bias': {'bias_type': bias, 'confidence': 0.9},
      'additional_indicators': [],
      'reflection_text': '',
      'suggested_actions': [],
      'comparison': {
        'activity_category': category,
        'claimed_duration': minutes,
        'facial_emotion': ?facial,
      },
    };

Map<String, dynamic> _face(double stress, String dominant) => {
      'status': 'success',
      'stress_indicator': stress,
      'dominant_emotion': dominant,
      'emotion_scores': {'sad': 0.31, 'angry': 0.18, 'neutral': 0.28},
    };

Map<String, dynamic> _resetRow(
  String entryId, {
  required String condition,
  required double before,
  required double after,
  required int delta,
  required String outcome,
  int minutesAgo = 5,
}) =>
    {
      'entry_id': entryId,
      'condition': condition,
      'before_stress': before,
      'after_stress': after,
      'delta_points': delta,
      'outcome': outcome,
      'self_before': 4,
      'self_after': 2,
      'rounds_completed': 6,
      'duration_seconds': 114,
      'created_at':
          _now.subtract(Duration(minutes: minutesAgo)).toUtc().toIso8601String(),
    };

late String _stressId; // the entry that was followed by a reset
late String _lectureId;

void _seed(_FakeApi api) {
  final calm = _ago(minutes: 20);
  _stressId = _ago(minutes: 10);
  _lectureId = _ago(days: 3);
  api.history = [
    _row(_stressId, 'stress_underestimation', 89, 'Assignment', 60,
        facial: _face(0.62, 'sad')),
    _row(calm, 'accurate_perception', 92, 'Self-study', 90,
        facial: _face(0.10, 'neutral')),
    _row(_ago(days: 1), 'productivity_overestimation', 46, 'Self-study', 120,
        facial: {'status': 'no_face_detected'}),
    _row(_lectureId, 'focus_mismatch', 61, 'Lecture', 60,
        facial: _face(0.35, 'sad')),
    _row(_ago(days: 12), 'context_mismatch', 58, 'Group work', 75),
    _row(_ago(days: 20), 'accurate_perception', 80, 'Self-study', 60,
        facial: _face(0.20, 'neutral')),
  ];
  api.resets = [
    _resetRow(_stressId,
        condition: 'breathing', before: 0.62, after: 0.24, delta: 38, outcome: 'improved'),
    _resetRow(_lectureId,
        condition: 'control',
        before: 0.35,
        after: 0.32,
        delta: 3,
        outcome: 'no_change',
        minutesAgo: 60 * 24 * 3),
  ];
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump(); // the fake answers on the next microtask
  await tester.pump(const Duration(milliseconds: 400));
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

void main() {
  late _FakeApi api;

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.userId = 'u1';
    api = _FakeApi()..start();
    _seed(api);
  });

  tearDown(() => api.stop());

  group('Bias History', () {
    testWidgets('lists every entry grouped by day, with a reset badge',
        (tester) async {
      await _pumpScreen(tester, const BiasHistoryScreen());
      expect(find.text('Bias History'), findsOneWidget);
      expect(find.text('6 entries · Avg PAS 71'), findsOneWidget);

      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('YESTERDAY'), findsOneWidget);
      expect(find.text('EARLIER THIS WEEK'), findsOneWidget);
      expect(find.text('EARLIER'), findsNWidgets(1));

      expect(find.text('Stress Underestimation'), findsOneWidget);
      expect(find.text('Assignment · 60 min'), findsOneWidget);
      expect(find.text('Reset −38 pts'), findsOneWidget);
      expect(find.text('89'), findsOneWidget);
      // yesterday's failed scan and the old entry without one
      expect(find.text('no scan'), findsNWidgets(2));
    });

    testWidgets('asks the server for the full history, not the default ten',
        (tester) async {
      await _pumpScreen(tester, const BiasHistoryScreen());
      expect(api.requested.any((r) => r.contains('/history/u1?limit=200')), isTrue);
    });

    testWidgets('chips show full totals and filter the list', (tester) async {
      await _pumpScreen(tester, const BiasHistoryScreen());
      expect(find.text('All 6'), findsOneWidget);
      expect(find.text('Accurate 2'), findsOneWidget);
      expect(find.text('Biased 4'), findsOneWidget);

      await tester.tap(find.text('Stress 1'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Stress Underestimation'), findsOneWidget);
      expect(find.text('Focus Mismatch'), findsNothing);
      expect(find.text('1 of 6 entries'), findsOneWidget);
      // totals on the chips do not shrink with the filter
      expect(find.text('All 6'), findsOneWidget);
    });

    testWidgets('search narrows by category and can be cleared', (tester) async {
      await _pumpScreen(tester, const BiasHistoryScreen());
      await tester.enterText(find.byType(TextField), 'lecture');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Focus Mismatch'), findsOneWidget);
      expect(find.text('Accurate Perception'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No matches'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No matches'), findsNothing);
      expect(find.text('Accurate Perception'), findsWidgets);
    });

    testWidgets('sorting by lowest PAS puts the weakest entry first',
        (tester) async {
      await _pumpScreen(tester, const BiasHistoryScreen());
      expect(_top(tester, 'Accurate Perception') < _top(tester, 'Productivity Overestimation'),
          isTrue);

      await tester.tap(find.text('Newest first ▾'));
      await tester.pumpAndSettle(); // let the menu finish opening
      await tester.tap(find.text('Lowest PAS first').last);
      await tester.pumpAndSettle();

      expect(find.text('Lowest PAS first ▾'), findsOneWidget);
      expect(_top(tester, 'Productivity Overestimation') < _top(tester, 'Accurate Perception'),
          isTrue);
      // not grouped by day any more
      expect(find.text('TODAY'), findsNothing);
    });

    testWidgets('tapping an entry opens its full analysis', (tester) async {
      await _pumpScreen(tester, const BiasHistoryScreen());
      await tester.tap(find.text('Productivity Overestimation'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('TruthLens Analysis'), findsOneWidget);
    });

    testWidgets('a server error is a failure page, not "no entries"',
        (tester) async {
      api.historyStatus = 503;
      await _pumpScreen(tester, const BiasHistoryScreen());
      expect(find.text('Could not load your history'), findsOneWidget);
      expect(find.text('Pull down to refresh'), findsOneWidget);
      expect(find.text('No entries yet'), findsNothing);
      // the toast explains why, in plain words
      expect(find.text('The server had a problem (code 503). Please try again.'),
          findsOneWidget);
      // no retry button, only the pull-down
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('no entries is its own state, with a way to start', (tester) async {
      api.history = [];
      await _pumpScreen(tester, const BiasHistoryScreen());
      expect(find.text('No entries yet'), findsOneWidget);
      expect(find.text('Start your first entry'), findsOneWidget);
      expect(find.text('Could not load your history'), findsNothing);
    });

    testWidgets('resets failing to load does not hide the entries',
        (tester) async {
      api.resetsStatus = 503;
      await _pumpScreen(tester, const BiasHistoryScreen());
      expect(find.text('Stress Underestimation'), findsOneWidget);
      expect(find.text('Reset −38 pts'), findsNothing);
    });
  });

  group('Facial History', () {
    testWidgets('summarises the scans and resets', (tester) async {
      await _pumpScreen(tester, const FacialHistoryScreen());
      expect(find.text('Facial History'), findsOneWidget);
      expect(find.text('4 scans · 2 resets'), findsOneWidget);
      // default range is 30 days: all four scans, average stress 32%
      expect(find.text('32%'), findsOneWidget);
      expect(find.text('Avg stress'), findsOneWidget);
      // two resets lowered stress by 38 and 3 points on average
      expect(find.text('−21'), findsOneWidget);
    });

    testWidgets('lists scans with a stress label and the timeline', (tester) async {
      await _pumpScreen(tester, const FacialHistoryScreen());
      expect(find.text('Stressed · 62%'), findsOneWidget);
      expect(find.text('Calm · 10%'), findsOneWidget);
      expect(find.text('Uneasy · 35%'), findsOneWidget);
      expect(find.text('FACIAL STRESS OVER TIME'), findsOneWidget);
      expect(find.text('Reset −38 pts'), findsOneWidget);
    });

    testWidgets('a face-only check shows with a "Face only" chip and no PAS',
        (tester) async {
      api.faceChecks = [
        {
          'entry_id': 'FACE_${_now.millisecondsSinceEpoch}',
          'kind': 'face_only',
          'comparison': {'facial_emotion': _face(0.48, 'fear')},
          'mood_support': {'mood': {'state': 'uneasy', 'label': 'Uneasy'}},
        },
      ];
      await _pumpScreen(tester, const FacialHistoryScreen());
      expect(find.text('5 scans · 2 resets'), findsOneWidget);
      expect(find.text('Uneasy · 48%'), findsOneWidget);
      expect(find.text('Face only'), findsOneWidget);
    });

    testWidgets('the 7-day range drops older scans', (tester) async {
      await _pumpScreen(tester, const FacialHistoryScreen());
      await tester.tap(find.text('7 days'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Calm · 20%'), findsNothing); // the 20-day-old scan
      expect(find.text('Stressed · 62%'), findsOneWidget);
    });

    testWidgets('tapping a scan shows its scores and says no photo was kept',
        (tester) async {
      await _pumpScreen(tester, const FacialHistoryScreen());
      await tester.tap(find.text('Stressed · 62%'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Your photo was not saved. Only these scores are kept.'),
          findsOneWidget);
      expect(find.text('View full analysis'), findsOneWidget);
      expect(find.text('Sad'), findsOneWidget);
      expect(find.text('31%'), findsOneWidget);
    });

    testWidgets('the Resets tab compares breathing with quiet rest', (tester) async {
      await _pumpScreen(tester, const FacialHistoryScreen());
      await tester.tap(find.text('Resets').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('AVERAGE CHANGE BY TYPE'), findsOneWidget);
      expect(find.text('−38 pts'), findsWidgets);
      expect(find.text('−3 pts'), findsWidgets);
      expect(find.text('Breathing'), findsWidgets);
      expect(find.text('Quiet rest'), findsWidgets);
      expect(find.textContaining('You rated 4 → 2'), findsWidgets);
    });

    testWidgets('no scans yet', (tester) async {
      api.history = [];
      api.resets = [];
      await _pumpScreen(tester, const FacialHistoryScreen());
      expect(find.text('No scans yet'), findsOneWidget);
      expect(find.text('Start a scan'), findsOneWidget);
    });

    testWidgets('no resets yet, but scans exist', (tester) async {
      api.resets = [];
      await _pumpScreen(tester, const FacialHistoryScreen());
      await tester.tap(find.text('Resets').first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No resets yet'), findsOneWidget);
    });

    testWidgets('a server error is a failure page with only a pull-down',
        (tester) async {
      api.historyStatus = 503;
      await _pumpScreen(tester, const FacialHistoryScreen());
      expect(find.text('Could not load your history'), findsOneWidget);
      expect(find.text('Pull down to refresh'), findsOneWidget);
      expect(find.text('No scans yet'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('History hub', () {
    Future<void> pumpHub(WidgetTester tester) => _pumpScreen(
          tester,
          const Scaffold(body: SingleChildScrollView(child: HistoryHub())),
        );

    testWidgets('shows a summary on each button', (tester) async {
      await pumpHub(tester);
      expect(find.text('Bias History'), findsOneWidget);
      expect(find.text('6 entries'), findsOneWidget);
      expect(find.text('Avg PAS 71'), findsOneWidget);
      expect(find.text('Facial History'), findsOneWidget);
      expect(find.text('4 scans · 2 resets'), findsOneWidget);
      expect(find.text('Avg stress 32%'), findsOneWidget);
    });

    testWidgets('the buttons open the two pages', (tester) async {
      await pumpHub(tester);
      await tester.tap(find.byKey(const Key('history-hub-bias')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Search bias type or activity category'), findsOneWidget);
    });

    testWidgets('the facial button opens Facial History', (tester) async {
      await pumpHub(tester);
      await tester.tap(find.byKey(const Key('history-hub-facial')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Scans'), findsWidgets);
      expect(find.text('7 days'), findsOneWidget);
    });

    testWidgets('still works, without numbers, when the server is down',
        (tester) async {
      api.historyStatus = 503;
      await pumpHub(tester);
      expect(find.text('Tap to open'), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('history-hub-bias')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Could not load your history'), findsOneWidget);
    });

    testWidgets('a new user sees friendly empty summaries', (tester) async {
      api.history = [];
      api.resets = [];
      await pumpHub(tester);
      expect(find.text('No entries yet'), findsOneWidget);
      expect(find.text('No scans yet'), findsOneWidget);
    });
  });
}
