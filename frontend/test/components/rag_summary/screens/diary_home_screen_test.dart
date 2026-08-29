import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/rag_summary/models/Diary_entry.dart';
import 'package:frontend/components/rag_summary/screens/Diary_home_screen.dart';
import 'package:frontend/components/rag_summary/services/Rag_diary_service.dart';
import 'package:frontend/core/network/dio_client.dart';

void main() {
  testWidgets('shows diary entries inside friendly week sections', (
    tester,
  ) async {
    final entries = [
      _entry(
        id: 1,
        activity: 'Morning walk',
        entryDate: '2026-08-26',
        weekStart: '2026-08-24',
        weekEnd: '2026-08-30',
      ),
      _entry(
        id: 2,
        activity: 'Project planning',
        entryDate: '2026-08-25',
        weekStart: '2026-08-24',
        weekEnd: '2026-08-30',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: DiaryHomeScreen(
          userId: 'test-user',
          service: _FakeDiaryService(entries),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your diary, week by week'), findsOneWidget);
    expect(find.text('Aug 24-30, 2026'), findsOneWidget);
    expect(find.text('2 entries'), findsWidgets);
    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.text('Project planning'), findsOneWidget);

    expect(find.text('EV-1'), findsNothing);
    expect(find.text('EV-2'), findsNothing);
    expect(find.textContaining('evidence'), findsNothing);
  });
}

class _FakeDiaryService extends RagDiaryService {
  final List<DiaryEntry> entries;

  _FakeDiaryService(this.entries) : super(DioClient());

  @override
  Future<List<DiaryEntry>> getDiaryEntries({
    required String userId,
    int limit = 50,
  }) async {
    return entries;
  }
}

DiaryEntry _entry({
  required int id,
  required String activity,
  required String entryDate,
  required String weekStart,
  required String weekEnd,
}) {
  return DiaryEntry(
    id: id,
    userId: 'test-user',
    evidenceId: 'EV-$id',
    activityName: activity,
    activityCategory: 'Health',
    startTime: '08:00',
    endTime: '09:00',
    durationMinutes: 60,
    productivityLevel: 'High',
    moodBefore: 'Neutral',
    moodAfter: 'Happy',
    taskOutcome: 'Completed',
    personNames: null,
    healthStatus: 'Normal',
    location: 'Home',
    withWhom: 'Alone',
    notes: 'A good start to the day.',
    entryDate: entryDate,
    weekStart: weekStart,
    weekEnd: weekEnd,
    createdAt: '${entryDate}T08:00:00',
    updatedAt: '${entryDate}T08:00:00',
  );
}
