import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/widgets/compared_with_usual.dart';
import 'package:frontend/components/self_bias_identification/widgets/your_trend_card.dart';

final _start = DateTime(2026, 10, 1, 9).millisecondsSinceEpoch;

Map<String, dynamic> _json(
  int index, {
  num pas = 60,
  num social = 20,
  num switches = 9,
  double? stress,
}) {
  final ms = _start + index * 3600 * 1000;
  return {
    'entry_id': 'ENT_LEADER_$ms',
    'pas_score': pas,
    'primary_bias': {'bias_type': 'focus_mismatch', 'confidence': 0.8},
    'comparison': {
      'social_media_minutes': social,
      'app_switches': switches,
      if (stress != null)
        'facial_emotion': {'status': 'success', 'stress_indicator': stress},
    },
  };
}

List<HistoryEntry> _steady(int n) => [
      for (var i = 0; i < n; i++)
        HistoryEntry.fromJson(_json(i, pas: 60 + (i % 3), stress: 0.08)),
    ];

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Compared with your usual', () {
    ComparedWithUsual card(Map<String, dynamic> today, List<HistoryEntry> all) =>
        ComparedWithUsual(result: today, loader: () async => all);

    testWidgets('a heavy day shows how far above the usual it is', (tester) async {
      final all = [..._steady(8)];
      final today = _json(20, pas: 33, social: 70, switches: 12, stress: 0.48);
      await _pump(tester, card(today, [...all, HistoryEntry.fromJson(today)]));
      expect(find.text('COMPARED WITH YOUR USUAL'), findsOneWidget);
      expect(find.text('Last 8 entries'), findsOneWidget);
      expect(find.text('3.5× your usual'), findsOneWidget);
      expect(find.text('+40 points'), findsOneWidget);
      expect(find.text('Social media'), findsOneWidget);
      expect(find.text('Facial stress'), findsOneWidget);
      expect(find.text('Alignment (PAS)'), findsOneWidget);
      expect(find.byKey(const Key('usual-mark')), findsWidgets);
    });

    testWidgets('a good day reads as better than usual', (tester) async {
      final all = _steady(8);
      final today = _json(20, pas: 95, social: 0, switches: 2, stress: 0.0);
      await _pump(tester, card(today, all));
      expect(find.text('below your usual'), findsWidgets);
      expect(find.textContaining('above usual'), findsOneWidget);
    });

    testWidgets('a new student sees a progress bar, not numbers', (tester) async {
      final today = _json(10, pas: 50);
      await _pump(tester, card(today, _steady(3)));
      expect(find.text('Building your baseline'), findsOneWidget);
      expect(find.text('3 of 5 entries'), findsOneWidget);
      expect(find.text('2 to go'), findsOneWidget);
      expect(find.text('Not yet'), findsOneWidget);
      expect(find.text('Social media'), findsNothing);
    });

    testWidgets('entries after this one are not part of its usual',
        (tester) async {
      // This is entry 3. Entries 4 to 12 happened later.
      final all = [for (var i = 0; i < 12; i++) HistoryEntry.fromJson(_json(i))];
      await _pump(tester, card(_json(3), all));
      // Only entries 0, 1 and 2 came before it: still building.
      expect(find.text('Building your baseline'), findsOneWidget);
      expect(find.text('3 of 5 entries'), findsOneWidget);
    });

    testWidgets('the entry itself is never counted in its own usual',
        (tester) async {
      final all = _steady(6);
      final itself = _json(5, pas: 60 + (5 % 3), stress: 0.08);
      await _pump(tester, card(itself, all));
      // 5 earlier entries (0 to 4) are enough: ready, "Last 5 entries".
      expect(find.text('Last 5 entries'), findsOneWidget);
    });

    testWidgets('when the entries cannot be loaded the card is simply absent',
        (tester) async {
      await _pump(
        tester,
        ComparedWithUsual(
          result: _json(1),
          loader: () async => throw Exception('offline'),
        ),
      );
      expect(find.text('COMPARED WITH YOUR USUAL'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a measure that was not taken today is not shown', (tester) async {
      final all = _steady(8);
      await _pump(tester, card(_json(20, pas: 70), all)); // no face scan
      expect(find.text('Facial stress'), findsNothing);
      expect(find.text('Social media'), findsOneWidget);
    });
  });

  group('Your trend card', () {
    testWidgets('shows the tabs, the usual range and the summary', (tester) async {
      await _pump(tester, YourTrendCard(entries: _steady(9)));
      expect(find.text('Your trend'), findsOneWidget);
      for (final t in ['PAS', 'Facial stress', 'Social media', 'App switches']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Your usual range'), findsOneWidget);
      expect(find.textContaining('Your average ('), findsOneWidget);
      expect(find.textContaining('better than your usual'), findsOneWidget);
      expect(find.byKey(const Key('trend-chart')), findsOneWidget);
    });

    testWidgets('switching the tab changes the words to fit the measure',
        (tester) async {
      await _pump(tester, YourTrendCard(entries: _steady(9)));
      await tester.tap(find.byKey(const Key('trend-tab-stress')));
      await tester.pump();
      expect(find.text('Calmer'), findsOneWidget);
      expect(find.text('More stressed'), findsOneWidget);
      expect(find.textContaining('calmer than your usual'), findsOneWidget);

      await tester.tap(find.byKey(const Key('trend-tab-social')));
      await tester.pump();
      expect(find.text('Less'), findsOneWidget);
      expect(find.textContaining('below your usual'), findsOneWidget);
    });

    testWidgets('a new student sees the line and a progress bar only',
        (tester) async {
      await _pump(tester, YourTrendCard(entries: _steady(3)));
      expect(find.byKey(const Key('trend-chart')), findsOneWidget);
      expect(find.text('Building your baseline'), findsOneWidget);
      expect(find.text('3 of 5 entries'), findsOneWidget);
      expect(find.text('Your usual range'), findsNothing);
    });

    testWidgets('with too few readings of a measure it says so', (tester) async {
      // Plenty of entries, but only one has a face scan.
      final entries = [
        for (var i = 0; i < 9; i++)
          HistoryEntry.fromJson(_json(i, stress: i == 0 ? 0.1 : null)),
      ];
      await _pump(tester, YourTrendCard(entries: entries));
      await tester.tap(find.byKey(const Key('trend-tab-stress')));
      await tester.pump();
      expect(find.textContaining('Not enough facial stress readings'), findsOneWidget);
    });

    testWidgets('a single entry draws no line and does not crash', (tester) async {
      await _pump(tester, YourTrendCard(entries: _steady(1)));
      expect(find.textContaining('Not enough pas readings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no entries at all does not crash', (tester) async {
      await _pump(tester, const YourTrendCard(entries: []));
      expect(find.text('Your trend'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every tab draws without an error', (tester) async {
      await _pump(tester, YourTrendCard(entries: _steady(9)));
      for (final key in ['pas', 'stress', 'social', 'switches']) {
        await tester.tap(find.byKey(Key('trend-tab-$key')));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: key);
      }
    });
  });
}
