import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/rag_summary/models/Diary_entry.dart';
import 'package:frontend/components/rag_summary/utils/diary_week_group.dart';

void main() {
  group('groupDiaryEntriesByWeek', () {
    test('groups and sorts weeks and entries newest first', () {
      final entries = [
        _entry(
          id: 1,
          activity: 'Monday planning',
          entryDate: '2026-08-24',
          weekStart: '2026-08-24',
          weekEnd: '2026-08-30',
          startTime: '09:00',
        ),
        _entry(
          id: 2,
          activity: 'Previous week review',
          entryDate: '2026-08-21',
          weekStart: '2026-08-17',
          weekEnd: '2026-08-23',
          startTime: '18:00',
        ),
        _entry(
          id: 3,
          activity: 'Wednesday exercise',
          entryDate: '2026-08-26',
          weekStart: '2026-08-24',
          weekEnd: '2026-08-30',
          startTime: '07:00',
        ),
      ];

      final groups = groupDiaryEntriesByWeek(entries);

      expect(groups, hasLength(2));
      expect(diaryWeekRange(groups[0]), 'Aug 24-30, 2026');
      expect(groups[0].entries.map((entry) => entry.activityName), [
        'Wednesday exercise',
        'Monday planning',
      ]);
      expect(diaryWeekRange(groups[1]), 'Aug 17-23, 2026');
    });

    test('derives a Monday-to-Sunday week when metadata is missing', () {
      final groups = groupDiaryEntriesByWeek([
        _entry(
          id: 1,
          activity: 'Midweek note',
          entryDate: '2026-09-02',
          weekStart: '',
          weekEnd: '',
          startTime: '12:00',
        ),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.weekStart, DateTime(2026, 8, 31));
      expect(groups.single.weekEnd, DateTime(2026, 9, 6));
      expect(diaryWeekRange(groups.single), 'Aug 31 - Sep 6, 2026');
    });

    test('uses friendly relative headings', () {
      final thisWeek = DiaryWeekGroup(
        weekStart: DateTime(2026, 8, 24),
        weekEnd: DateTime(2026, 8, 30),
        entries: const [],
      );
      final lastWeek = DiaryWeekGroup(
        weekStart: DateTime(2026, 8, 17),
        weekEnd: DateTime(2026, 8, 23),
        entries: const [],
      );

      expect(
        diaryWeekHeading(thisWeek, today: DateTime(2026, 8, 27)),
        'This week',
      );
      expect(
        diaryWeekHeading(lastWeek, today: DateTime(2026, 8, 27)),
        'Last week',
      );
    });
  });
}

DiaryEntry _entry({
  required int id,
  required String activity,
  required String entryDate,
  required String weekStart,
  required String weekEnd,
  required String startTime,
}) {
  return DiaryEntry(
    id: id,
    userId: 'test-user',
    evidenceId: 'EV-$id',
    activityName: activity,
    activityCategory: 'Personal',
    startTime: startTime,
    endTime: '13:00',
    durationMinutes: 60,
    productivityLevel: 'Medium',
    moodBefore: 'Neutral',
    moodAfter: 'Happy',
    taskOutcome: 'Completed',
    personNames: null,
    healthStatus: 'Normal',
    location: 'Home',
    withWhom: 'Alone',
    notes: 'A diary note.',
    entryDate: entryDate,
    weekStart: weekStart,
    weekEnd: weekEnd,
    createdAt: '${entryDate}T$startTime:00',
    updatedAt: '${entryDate}T$startTime:00',
  );
}
