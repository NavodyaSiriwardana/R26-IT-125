import joblib
import numpy as np
import os
import xgboost as xgb

BASE_DIR = os.path.dirname(
    os.path.dirname(os.path.abspath(__file__))
)
MODEL_DIR = os.path.join(BASE_DIR, "ml_models", "trained")

FEATURE_ORDER = [
    "duration_gap",
    "duration_match_ratio",
    "location_match",
    "focus_quality_score",
    "activity_match",
    "stress_mismatch",
    "app_switch_count",
    "social_media_minutes",
    "distraction_duration",
    "calendar_match",
    "facial_stress",
]

# Human-readable labels for the explanation card — the UI shouldn't have
# to know the raw feature/column names.
FEATURE_LABELS = {
    "duration_gap": "Claimed vs verified duration gap",
    "duration_match_ratio": "Study duration match",
    "location_match": "Location match",
    "focus_quality_score": "Focus quality (app switching)",
    "activity_match": "Educational vs social media time",
    "stress_mismatch": "Self-reported / detected stress mismatch",
    "app_switch_count": "App switch count",
    "social_media_minutes": "Social media usage",
    "distraction_duration": "Distraction time",
    "calendar_match": "Calendar event match",
    "facial_stress": "Facial stress signal",
}


class BiasClassifier:

    def __init__(self):
        self.model = joblib.load(
            os.path.join(MODEL_DIR, "xgboost_model.pkl")
        )
        self.scaler = joblib.load(
            os.path.join(MODEL_DIR, "scaler.pkl")
        )
        self.label_encoder = joblib.load(
            os.path.join(MODEL_DIR, "label_encoder.pkl")
        )
        print("Bias classifier loaded!")

    def classify(self, features: dict) -> dict:
        feature_vector = np.array([[
            features[name] for name in FEATURE_ORDER
        ]])

        scaled = self.scaler.transform(feature_vector)
        prediction = self.model.predict(scaled)[0]
        probabilities = self.model.predict_proba(scaled)[0]
        bias_type = self.label_encoder.inverse_transform(
            [prediction]
        )[0]
        confidence = float(max(probabilities))

        all_probs = {
            self.label_encoder.classes_[i]: round(float(p), 4)
            for i, p in enumerate(probabilities)
        }

        return {
            "bias_type": bias_type,
            "confidence": round(confidence, 4),
            "all_probabilities": all_probs,
            "explanation": self._explain(scaled, int(prediction)),
        }

    def _explain(self, scaled_features, predicted_class_idx: int) -> list:
        """Per-prediction feature contributions (SHAP values) for the
        class that was actually predicted — "why did THIS entry get
        this label", not the model's general feature importance."""
        dmatrix = xgb.DMatrix(scaled_features, feature_names=FEATURE_ORDER)
        contribs = self.model.get_booster().predict(dmatrix, pred_contribs=True)
        # shape: (1, n_classes, n_features + 1) — last column is the bias term.
        class_contribs = contribs[0][predicted_class_idx][:-1]

        total_weight = float(sum(abs(v) for v in class_contribs)) or 1.0
        ranked = sorted(
            zip(FEATURE_ORDER, class_contribs),
            key=lambda pair: abs(pair[1]),
            reverse=True,
        )[:3]

        return [
            {
                "feature": FEATURE_LABELS.get(name, name),
                "direction": "increased" if value > 0 else "decreased",
                "weight": float(round(abs(float(value)) / total_weight, 3)),
            }
            for name, value in ranked
        ]

    def classify_with_rules(self, features: dict,
                             facial_emotion: dict = None) -> dict:
        # Step 1: XGBoost primary
        primary = self.classify(features)

        # Step 2: Rule-based additional
        additional = []

        # facial_stress already feeds the primary XGBoost classification
        # (see comparator.py / FEATURE_ORDER above). This is a *separate*,
        # rule-based cross-check: it only fires when the self-report alone
        # didn't already flag a mismatch, so it doesn't duplicate what the
        # model already caught.
        if (facial_emotion and facial_emotion.get("status") == "success" and
                facial_emotion.get("stress_indicator", 0) >= 0.5 and
                features["stress_mismatch"] == 0):
            additional.append({
                "type": "facial_stress_mismatch",
                "reason": (
                    f"Facial expression suggests {facial_emotion.get('dominant_emotion')} "
                    f"({round(facial_emotion.get('stress_indicator', 0) * 100)}% stress signal) "
                    "not reflected in your self-reported mood"
                )
            })

        if (features["app_switch_count"] > 35 and
                primary["bias_type"] != "focus_mismatch"):
            additional.append({
                "type": "focus_mismatch",
                "reason": f"High app switches detected: {features['app_switch_count']}"
            })

        if (features["location_match"] == 0 and
                primary["bias_type"] != "context_mismatch"):
            additional.append({
                "type": "context_mismatch",
                "reason": "Location does not match claim"
            })

        if features["calendar_match"] == 0:
            additional.append({
                "type": "schedule_mismatch",
                "reason": "No calendar event scheduled"
            })

        if (features["stress_mismatch"] == 1 and
                primary["bias_type"] != "stress_underestimation"):
            additional.append({
                "type": "stress_underestimation",
                "reason": "Mood claim contradicts behavior signals"
            })

        return {
            "primary_bias": primary,
            "additional_indicators": additional
        }