import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/no_diary_entry_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/consent_service.dart';
import 'package:frontend/components/self_bias_identification/services/study_service.dart';
import 'package:frontend/components/temporal_causal_patterns/screens/new_entry_screen.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('team diary template', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // The team's template is not ours to change; this only checks that the
    // existing way into Bias Detection (the "Bias Insights" tab) is still there.
    testWidgets('still has the Bias Insights tab that opens Bias Detection',
        (tester) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: NewEntryScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('New session entry'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('My Patterns'), findsOneWidget);
      expect(find.text('Bias Insights'), findsOneWidget);
    });
  });

  group('no diary entry screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('opens the team template and leaves one screen under it',
        (tester) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // root (like the Past Task / Future Task chooser) -> Home -> NoDiary
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NoDiaryEntryScreen()),
              ),
              child: const Text('root'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('root'));
      await tester.pumpAndSettle();
      expect(find.text('No diary entry found'), findsOneWidget);

      await tester.tap(find.text('Open Diary Entry'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('New session entry'), findsOneWidget);
      expect(find.text('No diary entry found'), findsNothing);

      // Back goes to the root, not to the "no entry" screen or a duplicate
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('root'), findsOneWidget);
    });
  });

  group('research state survives a logout that clears preferences', () {
    late HttpServer server;
    late String originalBase;

    setUp(() async {
      // flutter_test replaces HTTP with a stub that answers 400; use the real one.
      HttpOverrides.global = null;
      originalBase = ApiService.baseUrl;
      AppState.userId = 'p1';
      SharedPreferences.setMockInitialValues({}); // as if clearAll() just ran
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      ApiService.baseUrl = 'http://127.0.0.1:${server.port}';
      server.listen((request) {
        final path = request.uri.path;
        Map<String, dynamic>? body;
        if (path == '/api/bias/consent/p1') {
          body = {
            'consent': {'agreed': true, 'version': 'v1', 'study_mode': true},
          };
        } else if (path == '/api/bias/mood-resets/p1') {
          body = {
            'resets': [
              {'condition': 'control', 'study_mode': true},
              {'condition': 'control', 'study_mode': true},
              {'condition': 'breathing', 'study_mode': true},
              {'condition': 'breathing', 'study_mode': false},
            ],
          };
        }
        request.response
          ..statusCode = body == null ? 404 : 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body ?? {}))
          ..close();
      });
    });

    tearDown(() async {
      ApiService.baseUrl = originalBase;
      await server.close(force: true);
    });

    test('consent and study mode come back from the server', () async {
      expect(await ConsentService.hasConsent(), isTrue);
      expect(await StudyService.isStudyMode(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('research_consent_v1_p1'), isTrue);
    });

    test('the balanced order resumes from the saved resets', () async {
      // 2 control + 1 breathing counted as study resets; the non-study one is ignored
      expect(await StudyService.nextCondition(), StudyService.breathing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('study_count_control_p1'), 2);
      expect(prefs.getInt('study_count_breathing_p1'), 1);
    });

    test('a different version of the consent is not accepted', () async {
      AppState.userId = 'other_user';
      expect(await ConsentService.hasConsent(), isFalse);
    });
  });
}
