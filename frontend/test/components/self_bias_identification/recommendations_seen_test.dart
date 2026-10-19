import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/app_state.dart';
import 'package:frontend/components/self_bias_identification/services/recommendations_seen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.userId = 'alice';
  });

  test('a result whose recommendations were never opened is new', () async {
    expect(await RecommendationsSeen.isNew('ENT_1'), isTrue);
  });

  test('opening them marks that result as seen', () async {
    await RecommendationsSeen.markSeen('ENT_1');
    expect(await RecommendationsSeen.isNew('ENT_1'), isFalse);
  });

  test('a newer result is new again', () async {
    await RecommendationsSeen.markSeen('ENT_1');
    expect(await RecommendationsSeen.isNew('ENT_2'), isTrue);
  });

  test('there is nothing new when there is no result', () async {
    expect(await RecommendationsSeen.isNew(''), isFalse);
    await RecommendationsSeen.markSeen('');
    expect(await RecommendationsSeen.isNew('ENT_1'), isTrue);
  });

  test('each student has their own', () async {
    await RecommendationsSeen.markSeen('ENT_1');
    AppState.userId = 'bob';
    expect(await RecommendationsSeen.isNew('ENT_1'), isTrue);
    AppState.userId = 'alice';
    expect(await RecommendationsSeen.isNew('ENT_1'), isFalse);
  });
}
