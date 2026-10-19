import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/components/self_bias_identification/screens/face_check_screen.dart';

const _face = {
  'status': 'success',
  'dominant_emotion': 'fear',
  'stress_indicator': 0.48,
  'emotion_scores': {'fear': 0.48, 'neutral': 0.4},
};

const _support = {
  'mood': {'state': 'uneasy', 'label': 'Uneasy', 'stress': 0.48, 'source': 'camera'},
  'needs_reset': true,
  'escalate': false,
  'reason': 'Your camera reading shows a 48% stress signal.',
  'actions': [
    {'id': 'walk', 'title': 'Walk away from the screen', 'detail': 'Water and daylight.', 'minutes': 5, 'kind': 'break'},
  ],
  'trend': {'values': [0.48], 'direction': 'steady'},
};

Future<void> _pump(
  WidgetTester tester, {
  bool fromHistory = false,
  String reason = 'none',
}) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: FaceCheckScreen(
      facial: _face,
      moodSupport: _support,
      entryId: 'FACE_1',
      fromHistory: fromHistory,
      reason: reason,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('says it is a face check only and shows the face reading',
      (tester) async {
    await _pump(tester);
    expect(find.text('Face check'), findsOneWidget);
    expect(find.text('This is a face check only'), findsOneWidget);
    expect(find.text('Fear detected'), findsOneWidget);
    expect(find.text('48% stress signal'), findsOneWidget);
  });

  testWidgets('shows Mood Support but no PAS or bias', (tester) async {
    await _pump(tester);
    expect(find.text('Mood Support'), findsOneWidget);
    expect(find.text('Walk away from the screen'), findsOneWidget);
    expect(find.textContaining('PAS'), findsNothing);
    expect(find.textContaining('bias type'), findsNothing);
  });

  testWidgets('offers the diary, and notes the save only right after a scan',
      (tester) async {
    await _pump(tester);
    expect(find.text('Open Diary Entry'), findsOneWidget);
    expect(find.text('Saved to Facial History as "Face only"'), findsOneWidget);
  });

  group('the message about adding a diary entry', () {
    testWidgets('no entry yet', (tester) async {
      await _pump(tester, reason: 'none');
      expect(find.textContaining('no diary entry yet'), findsOneWidget);
    });

    testWidgets('the latest entry is too old', (tester) async {
      await _pump(tester, reason: 'stale');
      expect(find.textContaining('too old'), findsOneWidget);
    });

    testWidgets('the latest entry was already analyzed', (tester) async {
      await _pump(tester, reason: 'analyzed');
      expect(find.textContaining('already analyzed'), findsOneWidget);
    });

    testWidgets('a reminder pops up right after a scan', (tester) async {
      await _pump(tester);
      expect(find.text('Add a diary entry to see your full bias result.'),
          findsOneWidget);
    });

    testWidgets('opening an old face check from history shows no reminder',
        (tester) async {
      await _pump(tester, fromHistory: true);
      expect(find.text('Add a diary entry to see your full bias result.'),
          findsNothing);
    });
  });

  diaryNavigationTest();

  testWidgets('opened from history, it does not claim it was just saved',
      (tester) async {
    await _pump(tester, fromHistory: true);
    expect(find.text('Saved to Facial History as "Face only"'), findsNothing);
  });
}

// Opening the diary from the Face check keeps one screen under it.
void diaryNavigationTest() {
  testWidgets('Open Diary Entry opens the team template, back reaches the root',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(700, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FaceCheckScreen(
                  facial: _face,
                  moodSupport: _support,
                  entryId: 'FACE_1',
                ),
              ),
            ),
            child: const Text('root'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('root'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Diary Entry'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('New session entry'), findsOneWidget);
    expect(find.text('Face check'), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('root'), findsOneWidget);
  });
}
