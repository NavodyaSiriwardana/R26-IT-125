import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/self_bias_identification/services/history_data.dart';
import 'package:frontend/components/self_bias_identification/services/mood_heatmap.dart';
import 'package:frontend/components/self_bias_identification/widgets/mood_heatmap.dart';

// Sunday 18 Oct 2026, so this week is Mon 12 .. Sun 18 and the 4 weeks start
// on Monday 21 Sep.
final _now = DateTime(2026, 10, 18, 15, 0);

HistoryEntry _scan(DateTime time, double stress, {String emotion = 'neutral'}) =>
    HistoryEntry.fromJson({
      'entry_id': 'FACE_${time.millisecondsSinceEpoch}',
      'kind': 'face_only',
      'comparison': {
        'facial_emotion': {
          'status': 'success',
          'stress_indicator': stress,
          'dominant_emotion': emotion,
        },
      },
    });

void main() {
  group('buildMoodHeatmap', () {
    test('has 28 cells, Monday first, ending on the week that holds today', () {
      final map = buildMoodHeatmap([], _now);
      expect(map.cells.length, 28);
      expect(map.cells.first.date, DateTime(2026, 9, 21));
      expect(map.cells.first.date.weekday, DateTime.monday);
      expect(map.cells.last.date, DateTime(2026, 10, 18));
      expect(map.cells.where((c) => c.isToday).length, 1);
      expect(map.cells.last.isToday, isTrue);
      expect(map.isEmpty, isTrue);
    });

    test('colours a day by its stress band and averages several scans', () {
      final map = buildMoodHeatmap([
        _scan(DateTime(2026, 10, 13, 9), 0.1),
        _scan(DateTime(2026, 10, 14, 9), 0.4),
        _scan(DateTime(2026, 10, 15, 9), 0.7),
        _scan(DateTime(2026, 10, 15, 18), 0.5),
      ], _now);
      HeatCell on(int d) =>
          map.cells.firstWhere((c) => c.date == DateTime(2026, 10, d));
      expect(on(13).band, StressBand.low);
      expect(on(14).band, StressBand.moderate);
      expect(on(15).band, StressBand.high);
      expect(on(15).scans, 2);
      expect(on(15).stress, closeTo(0.6, 1e-9));
      expect(on(16).band, isNull);
      expect(map.scans, 4);
    });

    test('ignores readings without a usable face and entries without a time', () {
      final bad = HistoryEntry.fromJson({
        'entry_id': 'x',
        'comparison': {
          'facial_emotion': {'status': 'no_face_detected'},
        },
      });
      final noTime = HistoryEntry.fromJson({
        'entry_id': 'nope',
        'comparison': {
          'facial_emotion': {'status': 'success', 'stress_indicator': 0.2},
        },
      });
      expect(buildMoodHeatmap([bad, noTime], _now).isEmpty, isTrue);
    });

    test('scans older than four weeks do not appear', () {
      final map =
          buildMoodHeatmap([_scan(DateTime(2026, 9, 1, 9), 0.2)], _now);
      expect(map.isEmpty, isTrue);
    });

    test('streak counts consecutive days and survives an unscanned today', () {
      final a = buildMoodHeatmap([
        _scan(DateTime(2026, 10, 16, 9), 0.2),
        _scan(DateTime(2026, 10, 17, 9), 0.2),
      ], _now);
      expect(a.streak, 2); // today has no scan yet, but the day is not over

      final b = buildMoodHeatmap([
        _scan(DateTime(2026, 10, 15, 9), 0.2),
        _scan(DateTime(2026, 10, 17, 9), 0.2),
        _scan(DateTime(2026, 10, 18, 9), 0.2),
      ], _now);
      expect(b.streak, 2); // the 16th is missing, so the run stops there
    });

    test('average stress is over the days that have a scan', () {
      final map = buildMoodHeatmap([
        _scan(DateTime(2026, 10, 13, 9), 0.2),
        _scan(DateTime(2026, 10, 14, 9), 0.4),
      ], _now);
      expect(map.averageStress, closeTo(0.3, 1e-9));
    });

    test('labels and reasons read well', () {
      final map = buildMoodHeatmap(
          [_scan(DateTime(2026, 10, 13, 9), 0.17, emotion: 'neutral')], _now);
      final cell =
          map.cells.firstWhere((c) => c.date == DateTime(2026, 10, 13));
      expect(heatDayLabel(cell), 'Tue 13 Oct');
      expect(heatReason(cell), 'Stress 17% · Neutral face');
      expect(heatDayLabel(map.cells.last), 'Sun 18 Oct (today)');
      expect(heatReason(map.cells[1]), 'No scan this day.');
    });
  });

  group('MoodHeatmapCard', () {
    Future<void> pump(WidgetTester tester, MoodHeatmap map) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: MoodHeatmapCard(heatmap: map),
                ),
              ),
            ),
          ),
        );

    testWidgets('tapping a day shows its reason, tapping again hides it',
        (tester) async {
      final map =
          buildMoodHeatmap([_scan(DateTime(2026, 10, 14, 9), 0.4)], _now);
      await pump(tester, map);
      final i = map.cells.indexWhere((c) => c.date == DateTime(2026, 10, 14));

      expect(find.byKey(const ValueKey('heat-popup')), findsNothing);
      await tester.tap(find.byKey(ValueKey('heat-cell-$i')));
      await tester.pump();
      expect(find.byKey(const ValueKey('heat-popup')), findsOneWidget);
      expect(find.textContaining('Wed 14 Oct'), findsOneWidget);
      expect(find.textContaining('Stress 40%'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('heat-cell-$i')));
      await tester.pump();
      expect(find.byKey(const ValueKey('heat-popup')), findsNothing);
    });

    testWidgets('a day with no scan says so, even in the first row',
        (tester) async {
      final map = buildMoodHeatmap([], _now);
      await pump(tester, map);
      await tester.tap(find.byKey(const ValueKey('heat-cell-0')));
      await tester.pump();
      expect(find.text('No scan this day.'), findsOneWidget);
      expect(find.text('Scan today to start your map.'), findsOneWidget);
    });

    testWidgets('future days cannot be tapped', (tester) async {
      // Wednesday: Thursday to Sunday are still to come.
      final map = buildMoodHeatmap([], DateTime(2026, 10, 14, 10));
      await pump(tester, map);
      await tester.tap(find.byKey(const ValueKey('heat-cell-27')),
          warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('heat-popup')), findsNothing);
    });

    testWidgets('shows scans, streak and average stress', (tester) async {
      final map = buildMoodHeatmap([
        _scan(DateTime(2026, 10, 17, 9), 0.1),
        _scan(DateTime(2026, 10, 18, 9), 0.1),
      ], _now);
      await pump(tester, map);
      expect(find.text('2 days'), findsOneWidget);
      expect(find.text('Low'), findsWidgets);
    });
  });
}
