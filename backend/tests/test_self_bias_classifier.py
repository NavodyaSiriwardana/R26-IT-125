import unittest

from app.components.self_bias_identification.services.classifier import (
    BiasClassifier,
    FEATURE_ORDER,
)

KNOWN_BIAS_TYPES = {
    "accurate_perception",
    "context_mismatch",
    "focus_mismatch",
    "productivity_overestimation",
    "stress_underestimation",
}


def _features(**overrides):
    base = {name: 0 for name in FEATURE_ORDER}
    base.update(
        {
            "duration_match_ratio": 1.0,
            "location_match": 1,
            "focus_quality_score": 1.0,
            "activity_match": 1,
            "calendar_match": 1,
        }
    )
    base.update(overrides)
    return base


class TestBiasClassifier(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Loads the real trained model files — shared across tests in this
        # class since construction is the expensive part.
        cls.classifier = BiasClassifier()

    def test_classify_returns_a_known_bias_type(self):
        result = self.classifier.classify(_features())
        self.assertIn(result["bias_type"], KNOWN_BIAS_TYPES)
        self.assertGreaterEqual(result["confidence"], 0.0)
        self.assertLessEqual(result["confidence"], 1.0)

    def test_all_probabilities_sum_to_one(self):
        result = self.classifier.classify(_features())
        total = sum(result["all_probabilities"].values())
        self.assertAlmostEqual(total, 1.0, places=3)

    def test_explanation_returns_top_three_features(self):
        result = self.classifier.classify(_features())
        self.assertEqual(len(result["explanation"]), 3)
        for item in result["explanation"]:
            self.assertIn("feature", item)
            self.assertIn("direction", item)
            self.assertIn(item["direction"], {"increased", "decreased"})

    def test_classify_with_rules_flags_context_mismatch_as_additional(self):
        features = _features(location_match=0)
        result = self.classifier.classify_with_rules(features)

        types = {item["type"] for item in result["additional_indicators"]}
        if result["primary_bias"]["bias_type"] != "context_mismatch":
            self.assertIn("context_mismatch", types)

    def test_classify_with_rules_flags_schedule_mismatch(self):
        features = _features(calendar_match=0)
        result = self.classifier.classify_with_rules(features)

        types = {item["type"] for item in result["additional_indicators"]}
        self.assertIn("schedule_mismatch", types)

    def test_classify_with_rules_flags_facial_stress_mismatch(self):
        features = _features(stress_mismatch=0)
        facial_emotion = {
            "status": "success",
            "dominant_emotion": "sad",
            "stress_indicator": 0.9,
        }
        result = self.classifier.classify_with_rules(
            features, facial_emotion=facial_emotion
        )

        types = {item["type"] for item in result["additional_indicators"]}
        self.assertIn("facial_stress_mismatch", types)


if __name__ == "__main__":
    unittest.main()
