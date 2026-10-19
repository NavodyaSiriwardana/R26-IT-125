import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/services/consent_service.dart';
import 'package:frontend/components/self_bias_identification/services/data_refresh.dart';
import 'package:frontend/components/self_bias_identification/services/entry_time.dart';
import 'package:frontend/components/self_bias_identification/services/privacy_helper.dart';
import 'package:frontend/components/self_bias_identification/services/study_service.dart';

void main() {
  // Nothing listens here, so server look-ups fail instantly instead of hanging.
  setUpAll(() => ApiService.baseUrl = 'http://127.0.0.1:1');

  group('entryTimestampMs', () {
    test('reads manual entry ids', () {
      expect(entryTimestampMs('ENT_1727000000000'), 1727000000000);
    });

    test('reads ids mapped from the shared diary', () {
      expect(entryTimestampMs('ENT_LEADER_1727000000123'), 1727000000123);
    });

    test('returns null when there is no trailing number', () {
      expect(entryTimestampMs('ENT_'), isNull);
      expect(entryTimestampMs(''), isNull);
      expect(entryTimestampMs(null), isNull);
    });

    test('sorts newest first across both id shapes', () {
      final ids = ['ENT_100', 'ENT_LEADER_300', 'ENT_200'];
      ids.sort((a, b) => entryTimestampMs(b)!.compareTo(entryTimestampMs(a)!));
      expect(ids, ['ENT_LEADER_300', 'ENT_200', 'ENT_100']);
    });
  });

  group('withoutFaceImage', () {
    test('removes the face photo and keeps everything else', () {
      final input = {
        'status': 'success',
        'stress_indicator': 0.4,
        'cropped_face_base64': 'AAAA',
      };
      final out = withoutFaceImage(input)!;
      expect(out.containsKey('cropped_face_base64'), isFalse);
      expect(out['stress_indicator'], 0.4);
      // the original, which the scan screen still displays, is untouched
      expect(input.containsKey('cropped_face_base64'), isTrue);
    });

    test('passes null through', () {
      expect(withoutFaceImage(null), isNull);
    });
  });

  group('StudyService', () {
    setUp(() {
      AppState.userId = 'tester';
      SharedPreferences.setMockInitialValues({});
    });

    test('study mode is off by default', () async {
      expect(await StudyService.isStudyMode(), isFalse);
    });

    test('assigns the condition completed fewer times', () async {
      await StudyService.recordCompleted(StudyService.breathing);
      expect(await StudyService.nextCondition(), StudyService.control);

      await StudyService.recordCompleted(StudyService.control);
      await StudyService.recordCompleted(StudyService.control);
      expect(await StudyService.nextCondition(), StudyService.breathing);
    });

    test('is balanced and both orders occur over many fresh participants',
        () async {
      AppState.userId = ''; // no server look-up for an anonymous participant
      var breathingFirst = 0;
      for (var i = 0; i < 60; i++) {
        SharedPreferences.setMockInitialValues({});
        if (await StudyService.nextCondition() == StudyService.breathing) {
          breathingFirst++;
        }
      }
      expect(breathingFirst, greaterThan(10));
      expect(breathingFirst, lessThan(50));
    });

    test('after four resets each condition was done twice', () async {
      for (var i = 0; i < 4; i++) {
        await StudyService.recordCompleted(await StudyService.nextCondition());
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('study_count_breathing_tester'), 2);
      expect(prefs.getInt('study_count_control_tester'), 2);
    });

    test('clearLocal forgets study state', () async {
      await StudyService.recordCompleted(StudyService.breathing);
      await StudyService.clearLocal();
      expect(await StudyService.isStudyMode(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('study_count_breathing_tester'), isNull);
    });
  });

  group('DataRefresh', () {
    test('notifies every listener each time data is saved', () {
      var calls = 0;
      void listener() => calls++;
      DataRefresh.tick.addListener(listener);
      DataRefresh.notify();
      DataRefresh.notify();
      DataRefresh.tick.removeListener(listener);
      DataRefresh.notify();
      expect(calls, 2);
    });
  });

  group('ConsentService', () {
    setUp(() => AppState.userId = 'tester');

    test('no consent until the user agrees', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ConsentService.hasConsent(), isFalse);
    });

    test('consent is stored per user', () async {
      SharedPreferences.setMockInitialValues({
        'research_consent_v1_tester': true,
      });
      expect(await ConsentService.hasConsent(), isTrue);
      AppState.userId = 'someone_else';
      expect(await ConsentService.hasConsent(), isFalse);
    });

    test('clearLocal removes consent', () async {
      SharedPreferences.setMockInitialValues({
        'research_consent_v1_tester': true,
      });
      await ConsentService.clearLocal();
      expect(await ConsentService.hasConsent(), isFalse);
    });
  });
}
