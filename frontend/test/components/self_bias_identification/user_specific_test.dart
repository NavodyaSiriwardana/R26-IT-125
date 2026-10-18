import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/home_screen.dart';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';
import 'package:frontend/components/self_bias_identification/services/calendar_settings_service.dart';
import 'package:frontend/components/self_bias_identification/services/sign_in_check.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('calendar verification is kept per student', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('off by default', () async {
      AppState.userId = 'alice';
      expect(await CalendarSettingsService.isEnabled(), isFalse);
    });

    test('one student turning it on does not turn it on for another', () async {
      AppState.userId = 'alice';
      await CalendarSettingsService.setEnabled(true);
      expect(await CalendarSettingsService.isEnabled(), isTrue);

      AppState.userId = 'bob';
      expect(await CalendarSettingsService.isEnabled(), isFalse);
      await CalendarSettingsService.setEnabled(true);
      await CalendarSettingsService.setEnabled(false);
      expect(await CalendarSettingsService.isEnabled(), isFalse);

      // Alice's choice is untouched by what Bob did.
      AppState.userId = 'alice';
      expect(await CalendarSettingsService.isEnabled(), isTrue);
    });
  });

  group('SignInCheck', () {
    test('a known student id is enough', () async {
      SharedPreferences.setMockInitialValues({});
      AppState.userId = 'alice';
      expect(await SignInCheck.ensure(), isTrue);
      expect(AppState.userId, 'alice');
    });

    test('a missing id is recovered from the saved sign-in', () async {
      SharedPreferences.setMockInitialValues({'userId': 'saved_uid'});
      AppState.userId = '';
      expect(await SignInCheck.ensure(), isTrue);
      expect(AppState.userId, 'saved_uid');
    });

    test('with no student anywhere it says not signed in and sets nothing',
        () async {
      SharedPreferences.setMockInitialValues({});
      AppState.userId = '';
      expect(await SignInCheck.ensure(), isFalse);
      expect(AppState.userId, '');
    });
  });

  group('Home without a signed-in student', () {
    late List<String> requested;

    setUp(() {
      requested = [];
      ApiClient.clientOverride = MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response('{}', 200);
      });
    });

    tearDown(() => ApiClient.clientOverride = null);

    testWidgets('asks the student to sign in and makes no requests',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppState.userId = '';
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Please sign in'), findsOneWidget);
      expect(find.text('Good morning'), findsNothing);
      expect(requested, isEmpty, reason: 'no request for an empty account');
    });

    testWidgets('Go back leaves the screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      AppState.userId = '';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Please sign in'), findsOneWidget);
      await tester.tap(find.byKey(const Key('signed-out-back')));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });
}
