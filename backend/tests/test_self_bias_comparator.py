import unittest

from app.components.self_bias_identification.services.comparator import (
    MultiSignalComparator,
)


class TestMultiSignalComparatorCategoryAwareness(unittest.TestCase):
    """Covers the bug found in production: non-study activities (Play,
    Trips, Entertainment, Meeting, Internship) were always scored against
    verified educational app usage, which is expected to be ~0 for those
    categories regardless of truthfulness — producing false bias flags on
    honest leisure entries."""

    def setUp(self):
        self.comparator = MultiSignalComparator()

    def test_leisure_category_is_not_penalised_for_zero_educational_usage(self):
        diary = {
            "activity_category": "Play",
            "claimed_duration_minutes": 180,
            "claimed_location": "Gym",
            "mood_before": "Happy",
            "mood_after": "Tired",
        }
        sensor = {
            "verified_educational_minutes": 0,
            "social_media_minutes": 118,
            "gps_location": "Gym",
            "calendar_match": 0,
            "app_switch_count": 5,
        }

        result = self.comparator.compare(diary, sensor)
        features = result["features"]

        self.assertEqual(features["duration_gap"], 0)
        self.assertEqual(features["duration_match_ratio"], 1.0)
        self.assertEqual(features["activity_match"], 1)

    def test_study_category_overestimation_is_still_caught(self):
        diary = {
            "activity_category": "Self-study",
            "claimed_duration_minutes": 120,
            "claimed_location": "Library",
            "mood_before": "Motivated",
            "mood_after": "Tired",
        }
        sensor = {
            "verified_educational_minutes": 20,
            "social_media_minutes": 90,
            "gps_location": "Library",
            "calendar_match": 1,
            "app_switch_count": 40,
        }

        result = self.comparator.compare(diary, sensor)
        features = result["features"]

        self.assertEqual(features["duration_gap"], 100)
        self.assertAlmostEqual(features["duration_match_ratio"], 0.17, places=2)
        self.assertEqual(features["activity_match"], 0)

    def test_all_study_categories_are_treated_as_study(self):
        for category in ("Lecture", "Self-study", "Assignment", "Group work"):
            with self.subTest(category=category):
                diary = {
                    "activity_category": category,
                    "claimed_duration_minutes": 100,
                }
                sensor = {"verified_educational_minutes": 0, "social_media_minutes": 0}

                result = self.comparator.compare(diary, sensor)
                # A study category with 0 verified minutes against a 100-minute
                # claim should show the real gap, not be neutralised.
                self.assertEqual(result["features"]["duration_gap"], 100)

    def test_non_study_categories_are_neutralised(self):
        for category in ("Play", "Trips", "Entertainment", "Meeting", "Internship"):
            with self.subTest(category=category):
                diary = {
                    "activity_category": category,
                    "claimed_duration_minutes": 100,
                }
                sensor = {"verified_educational_minutes": 0, "social_media_minutes": 0}

                result = self.comparator.compare(diary, sensor)
                self.assertEqual(result["features"]["duration_gap"], 0)
                self.assertEqual(result["features"]["duration_match_ratio"], 1.0)


class TestMultiSignalComparatorOtherSignals(unittest.TestCase):
    """Signals that apply the same way regardless of activity category."""

    def setUp(self):
        self.comparator = MultiSignalComparator()

    def test_location_mismatch_is_detected(self):
        diary = {
            "activity_category": "Play",
            "claimed_duration_minutes": 60,
            "claimed_location": "Gym",
        }
        sensor = {"gps_location": "Home"}

        result = self.comparator.compare(diary, sensor)
        self.assertEqual(result["features"]["location_match"], 0)

    def test_location_match_is_detected(self):
        diary = {
            "activity_category": "Play",
            "claimed_duration_minutes": 60,
            "claimed_location": "Gym",
        }
        sensor = {"gps_location": "Gym"}

        result = self.comparator.compare(diary, sensor)
        self.assertEqual(result["features"]["location_match"], 1)

    def test_mood_contradiction_triggers_stress_mismatch(self):
        diary = {
            "activity_category": "Play",
            "claimed_duration_minutes": 60,
            "mood_before": "Happy",
            "mood_after": "Stressed",
        }
        sensor = {}

        result = self.comparator.compare(diary, sensor)
        self.assertEqual(result["features"]["stress_mismatch"], 1)

    def test_high_facial_stress_triggers_stress_mismatch_independently(self):
        diary = {
            "activity_category": "Play",
            "claimed_duration_minutes": 60,
            "mood_before": "Happy",
            "mood_after": "Happy",
        }
        sensor = {
            "facial_emotion": {"status": "success", "stress_indicator": 0.8},
        }

        result = self.comparator.compare(diary, sensor)
        self.assertEqual(result["features"]["stress_mismatch"], 1)

    def test_missing_calendar_event_is_detected(self):
        diary = {"activity_category": "Play", "claimed_duration_minutes": 60}
        sensor = {"calendar_match": 0}

        result = self.comparator.compare(diary, sensor)
        self.assertEqual(result["features"]["calendar_match"], 0)


if __name__ == "__main__":
    unittest.main()
