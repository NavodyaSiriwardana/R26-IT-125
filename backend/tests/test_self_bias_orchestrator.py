import unittest

from app.components.self_bias_identification.services.orchestrator import (
    BiasDetectionOrchestrator,
)


class TestBiasDetectionOrchestrator(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.orchestrator = BiasDetectionOrchestrator()

    def test_full_pipeline_returns_expected_shape(self):
        diary_entry = {
            "activity_category": "Self-study",
            "claimed_duration_minutes": 120,
            "claimed_location": "Library",
            "mood_before": "Motivated",
            "mood_after": "Tired",
        }
        sensor_data = {
            "verified_educational_minutes": 20,
            "social_media_minutes": 90,
            "gps_location": "Library",
            "calendar_match": 1,
            "app_switch_count": 40,
        }

        result = self.orchestrator.analyze(diary_entry, sensor_data)

        for key in (
            "primary_bias",
            "additional_indicators",
            "pas_score",
            "pas_level",
            "pas_breakdown",
            "comparison",
        ):
            self.assertIn(key, result)

        self.assertIsInstance(result["pas_score"], int)
        self.assertGreaterEqual(result["pas_score"], 0)
        self.assertLessEqual(result["pas_score"], 100)

    def test_leisure_entry_does_not_get_flagged_purely_for_zero_screen_time(self):
        """End-to-end regression test for the category-awareness fix —
        exercises comparator -> classifier -> pas_calculator together."""
        diary_entry = {
            "activity_category": "Play",
            "claimed_duration_minutes": 180,
            "claimed_location": "Gym",
            "mood_before": "Happy",
            "mood_after": "Tired",
        }
        sensor_data = {
            "verified_educational_minutes": 0,
            "social_media_minutes": 20,
            "gps_location": "Gym",
            "calendar_match": 1,
            "app_switch_count": 5,
        }

        result = self.orchestrator.analyze(diary_entry, sensor_data)

        self.assertEqual(result["comparison"]["is_study_category"], False)
        self.assertEqual(result["comparison"]["duration_gap"], 0)
        # A genuinely well-matched leisure entry (location + calendar OK,
        # low distraction) should score comfortably above "Severe Bias".
        self.assertGreaterEqual(result["pas_score"], 50)


if __name__ == "__main__":
    unittest.main()
