import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/screens/consent_screen.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';

Future<void> _pumpWith(
  WidgetTester tester,
  void Function(BuildContext) onTap,
) async {
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => onTap(context),
          child: const Text('go'),
        ),
      ),
    ),
  ));
}

/// Lets time pass in small steps, like real frames, so the toast's own
/// timer and exit animation run.
Future<void> _elapse(WidgetTester tester, int milliseconds) async {
  for (var t = 0; t < milliseconds; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    AppState.userId = 'u1';
    SharedPreferences.setMockInitialValues({});
  });

  group('AppToast', () {
    testWidgets('shows the message with a matching icon for each type',
        (tester) async {
      final cases = <String, (void Function(BuildContext, String), IconData)>{
        'saved': (AppToast.success, Icons.check_circle_rounded),
        'careful': (AppToast.warning, Icons.warning_amber_rounded),
        'failed': (AppToast.error, Icons.error_rounded),
        'fyi': (AppToast.info, Icons.info_rounded),
      };
      for (final entry in cases.entries) {
        await _pumpWith(tester, (c) => entry.value.$1(c, entry.key));
        await tester.tap(find.text('go'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(entry.key), findsOneWidget, reason: entry.key);
        expect(find.byIcon(entry.value.$2), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('a new toast replaces the one on screen', (tester) async {
      var n = 0;
      await _pumpWith(tester, (c) => AppToast.info(c, 'message ${++n}'));
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('message 2'), findsOneWidget);
      expect(find.text('message 1'), findsNothing);
    });

    testWidgets('disappears by itself', (tester) async {
      await _pumpWith(tester, (c) => AppToast.success(c, 'saved'));
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('saved'), findsOneWidget);
      await _elapse(tester, 4500);
      expect(find.text('saved'), findsNothing);
    });

    testWidgets('errors stay longer than successes', (tester) async {
      await _pumpWith(tester, (c) => AppToast.error(c, 'failed'));
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 400));
      await _elapse(tester, 3000);
      expect(find.text('failed'), findsOneWidget); // a success would be gone by now
      await _elapse(tester, 3000);
      expect(find.text('failed'), findsNothing);
    });

    testWidgets('does nothing when there is no messenger', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(Builder(builder: (c) {
        captured = c;
        return const SizedBox();
      }));
      expect(() => AppToast.info(captured, 'x'), returnsNormally);
    });

    test('network failures become a plain-language message', () {
      expect(
        AppToast.friendlyError(
            'ClientException with SocketException: Connection refused'),
        "Can't reach the server. Check your connection.",
      );
      expect(
        AppToast.friendlyError('TimeoutException after 0:00:15'),
        'The server is taking too long to answer. Try again in a moment.',
      );
    });

    test('other failures never show a raw exception', () {
      final text = AppToast.friendlyError(StateError('boom'));
      expect(text, 'Something went wrong. Please try again.');
      expect(text.contains('boom'), isFalse);
    });
  });

  group('toasts at real events', () {
    testWidgets('agreeing to consent confirms it', (tester) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const ConsentScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('I have read this and agree'));
      await tester.pump();
      await tester.tap(find.text('I agree'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      // the toast outlives the consent screen that raised it
      expect(find.text('Thanks. Camera analysis is on.'), findsOneWidget);
      expect(find.text('Before we use your camera'), findsNothing);
    });

    testWidgets('joining the study is mentioned in the consent toast',
        (tester) async {
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => const ConsentScreen(studyPreselected: true),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('I have read this and agree'));
      await tester.pump();
      await tester.tap(find.text('I agree'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Thanks. Camera analysis and study mode are on.'),
          findsOneWidget);
    });
  });
}
