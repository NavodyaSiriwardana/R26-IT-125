from app.components.self_bias_identification.services.comparator import MultiSignalComparator
from app.components.self_bias_identification.services.classifier import BiasClassifier
from app.components.self_bias_identification.services.pas_calculator import PASCalculator


class BiasDetectionOrchestrator:

    def __init__(self):
        self.comparator = MultiSignalComparator()
        self.classifier = BiasClassifier()
        self.pas_calculator = PASCalculator()

    def analyze(self, diary_entry: dict,
                sensor_data: dict) -> dict:
        # Step 1: Compare
        compared = self.comparator.compare(
            diary_entry, sensor_data)

        features = compared["features"]
        comparison = compared["comparison"]

        # Step 2: Classify
        classification = self.classifier.classify_with_rules(
            features, facial_emotion=sensor_data.get("facial_emotion"))

        # Step 3: PAS Score
        pas_result = self.pas_calculator.calculate(
            features,
            diary_entry.get("claimed_duration_minutes", 0)
        )

        return {
            "primary_bias": classification["primary_bias"],
            "additional_indicators": 
                classification["additional_indicators"],
            "pas_score": pas_result["pas_score"],
            "pas_level": pas_result["level"],
            "pas_breakdown": pas_result["breakdown"],
            "comparison": comparison,
        }