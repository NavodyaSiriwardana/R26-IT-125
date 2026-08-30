import unittest

from app.components.self_bias_identification.services.pas_calculator import (
    PASCalculator,
)


def _features(**overrides):
    base = {
        "duration_match_ratio": 1.0,
        "focus_quality_score": 1.0,
        "activity_match": 1,
        "location_match": 1,
        "calendar_match": 1,
    }
    base.update(overrides)
    return base


class TestPASCalculator(unittest.TestCase):
    def setUp(self):
        self.calculator = PASCalculator()

    def test_perfect_alignment_scores_100(self):
        result = self.calculator.calculate(_features(), claimed_duration=60)
        self.assertEqual(result["pas_score"], 100)
        self.assertEqual(result["level"], "Excellent Alignment")

    def test_complete_mismatch_scores_low(self):
        features = _features(
            duration_match_ratio=0.0,
            focus_quality_score=0.0,
            activity_match=0,
            location_match=0,
            calendar_match=0,
        )
        result = self.calculator.calculate(features, claimed_duration=60)
        # activity/location/calendar all carry a non-zero floor score even
        # on mismatch (25/30/50), so a complete mismatch doesn't hit 0.
        self.assertEqual(result["pas_score"], 14)
        self.assertEqual(result["level"], "Severe Bias")

    def test_breakdown_matches_weighted_components(self):
        result = self.calculator.calculate(_features(), claimed_duration=60)
        breakdown = result["breakdown"]
        self.assertEqual(breakdown["duration"], 100)
        self.assertEqual(breakdown["focus"], 100)
        self.assertEqual(breakdown["activity"], 100)
        self.assertEqual(breakdown["location"], 100)
        self.assertEqual(breakdown["calendar"], 100)

    def test_level_thresholds(self):
        cases = [
            (90, "Excellent Alignment"),
            (85, "Excellent Alignment"),
            (84, "Good Alignment"),
            (70, "Good Alignment"),
            (69, "Mild Bias"),
            (50, "Mild Bias"),
            (49, "Moderate Bias"),
            (30, "Moderate Bias"),
            (29, "Severe Bias"),
            (0, "Severe Bias"),
        ]
        for score, expected_level in cases:
            with self.subTest(score=score):
                self.assertEqual(self.calculator._get_level(score), expected_level)


if __name__ == "__main__":
    unittest.main()
