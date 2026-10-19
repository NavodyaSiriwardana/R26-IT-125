import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/widgets/score_gauge.dart';

Future<void> _pump(
  WidgetTester tester,
  int score, {
  double width = 280,
  bool sweep = false,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: ScoreGauge(score: score, width: width, sweep: sweep)),
      ),
    ));

/// The number the dial is showing right now.
int _shown(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.descendant(
    of: find.byType(ScoreGauge),
    matching: find.byType(Text),
  ));
  return int.parse(texts.first.data!);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('colour zones', () {
    test('red below 50, orange 50 to 69, green from 70', () {
      expect(ScoreGauge.colorFor(0), ScoreGauge.red);
      expect(ScoreGauge.colorFor(33), ScoreGauge.red);
      expect(ScoreGauge.colorFor(49), ScoreGauge.red);
      expect(ScoreGauge.colorFor(50), ScoreGauge.orange);
      expect(ScoreGauge.colorFor(69), ScoreGauge.orange);
      expect(ScoreGauge.colorFor(70), ScoreGauge.green);
      expect(ScoreGauge.colorFor(100), ScoreGauge.green);
    });
  });

  group('score tones', () {
    test('five pure colours, each in its zone family', () {
      expect(ScoreGauge.toneFor(0), ScoreGauge.red);
      expect(ScoreGauge.toneFor(34), ScoreGauge.red);
      expect(ScoreGauge.toneFor(35), ScoreGauge.coral);
      expect(ScoreGauge.toneFor(49), ScoreGauge.coral);
      expect(ScoreGauge.toneFor(50), ScoreGauge.orange);
      expect(ScoreGauge.toneFor(69), ScoreGauge.orange);
      expect(ScoreGauge.toneFor(70), ScoreGauge.green);
      expect(ScoreGauge.toneFor(84), ScoreGauge.green);
      expect(ScoreGauge.toneFor(85), ScoreGauge.teal);
      expect(ScoreGauge.toneFor(100), ScoreGauge.teal);
    });

    test('neighbouring scores in a typical list get different colours', () {
      final tones = {for (final s in [33, 43, 55, 72, 90]) ScoreGauge.toneFor(s)};
      expect(tones.length, 5);
    });

    test('a decimal score is placed correctly', () {
      expect(ScoreGauge.toneFor(69.9), ScoreGauge.orange);
      expect(ScoreGauge.toneFor(34.9), ScoreGauge.red);
    });
  });

  group('gauge', () {
    testWidgets('shows the score in the colour of its zone', (tester) async {
      for (final (score, colour) in [
        (33, ScoreGauge.red),
        (62, ScoreGauge.orange),
        (88, ScoreGauge.green),
      ]) {
        await _pump(tester, score);
        final text = tester.widget<Text>(find.text('$score'));
        expect(text.style?.color, colour, reason: 'score $score');
        expect(find.text('out of 100'), findsOneWidget);
      }
    });

    testWidgets('draws at every score from 0 to 100 without an error',
        (tester) async {
      for (final score in [0, 1, 49, 50, 69, 70, 99, 100]) {
        await _pump(tester, score);
        expect(tester.takeException(), isNull, reason: 'score $score');
      }
    });

    testWidgets('a score outside 0-100 is held to the dial', (tester) async {
      await _pump(tester, 140);
      expect(find.text('100'), findsOneWidget);
      await _pump(tester, -5);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('keeps its shape at other widths', (tester) async {
      await _pump(tester, 33, width: 200);
      expect(tester.getSize(find.byType(ScoreGauge)).width, 200);
      await _pump(tester, 33, width: 340);
      expect(tester.getSize(find.byType(ScoreGauge)).width, 340);
    });

    testWidgets('the logo sits behind the dial, faint', (tester) async {
      await _pump(tester, 33);
      final opacity = tester.widget<Opacity>(find.descendant(
        of: find.byType(ScoreGauge),
        matching: find.byType(Opacity),
      ));
      expect(opacity.opacity, lessThan(0.2));
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('needle sweep', () {
    testWidgets('starts at 0, ends at the score, and settles', (tester) async {
      await _pump(tester, 80, sweep: true);
      expect(_shown(tester), 0);
      await tester.pump(const Duration(milliseconds: 400));
      final mid = _shown(tester);
      expect(mid, greaterThan(0));
      expect(mid, lessThan(80));
      await tester.pump(ScoreGauge.sweepDuration);
      expect(_shown(tester), 80);
      // Nothing keeps running once it has arrived.
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('it sweeps only once, not on every rebuild', (tester) async {
      await _pump(tester, 80, sweep: true);
      await tester.pump(ScoreGauge.sweepDuration);
      await tester.pump(const Duration(milliseconds: 50));
      await _pump(tester, 80, sweep: true); // same score, rebuilt
      expect(_shown(tester), 80);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a new score moves the needle from where it was',
        (tester) async {
      await _pump(tester, 40, sweep: true);
      await tester.pump(ScoreGauge.sweepDuration);
      await _pump(tester, 90, sweep: true);
      await tester.pump(const Duration(milliseconds: 300));
      final mid = _shown(tester);
      expect(mid, greaterThan(40));
      expect(mid, lessThan(90));
      await tester.pump(ScoreGauge.sweepDuration);
      expect(_shown(tester), 90);
    });

    testWidgets('with the sweep off it shows the score at once', (tester) async {
      await _pump(tester, 55);
      expect(_shown(tester), 55);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a phone set to reduce motion shows the score at once',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(body: Center(child: ScoreGauge(score: 72))),
        ),
      ));
      expect(_shown(tester), 72);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
