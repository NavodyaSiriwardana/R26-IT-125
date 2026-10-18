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

    def classify(self, features: dict, exclude=()) -> dict:
        """The model's verdict. [exclude] lists bias types that must not be
        chosen (see classify_with_rules); the best of the rest is used instead
        and the confidence is re-scaled over what is left, so it still reads
        as "how sure among the possible answers"."""
        feature_vector = np.array([[
            features[name] for name in FEATURE_ORDER
        ]])

        scaled = self.scaler.transform(feature_vector)
        probabilities = self.model.predict_proba(scaled)[0].copy()
        classes = list(self.label_encoder.classes_)

        all_probs = {
            classes[i]: round(float(p), 4)
            for i, p in enumerate(probabilities)
        }

        allowed = [i for i, name in enumerate(classes) if name not in exclude]
        if not allowed:
            allowed = list(range(len(classes)))
        prediction = max(allowed, key=lambda i: probabilities[i])
        mass = float(sum(probabilities[i] for i in allowed)) or 1.0
        confidence = float(probabilities[prediction]) / mass

        return {
            "bias_type": classes[prediction],
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
                             facial_emotion: dict = None,
                             mood_after: str = "") -> dict:
        # Step 1: XGBoost primary
        primary = self.classify(features)

        # The model learned "a stressed face means stress underestimation"
        # because in its training data a stressed face always came with a
        # mismatch. In the app a student who says "I feel stressed, tired or
        # bored" is being honest, and the comparator then sets
        # stress_mismatch to 0. That student must not be told they
        # underestimate their stress, so the next best answer is used instead.
        if (primary["bias_type"] == "stress_underestimation"
                and features.get("stress_mismatch", 0) == 0):
            primary = self.classify(features, exclude=("stress_underestimation",))
            primary["adjusted"] = (
                "Stress underestimation was ruled out: no stress was hidden "
                "(the student's own report matches, or there was no scan)."
            )

        # Step 2: Rule-based additional indicators. Each rule fires only when
        # its signal was actually verified (see comparator *_checked flags),
        # so "could not check" is never reported as a mismatch.
        additional = []

        # stress_mismatch is already 1 only when the face shows stress the
        # student's own mood report does not (comparator.py), so an honest
        # "I feel stressed" never triggers this.
        if (features["stress_mismatch"] == 1 and facial_emotion
                and facial_emotion.get("status") == "success"):
            pct = round(facial_emotion.get("stress_indicator", 0) * 100)
            reported = f" while you reported feeling {mood_after}" if mood_after else ""
            additional.append({
                "type": "facial_stress_mismatch",
                "reason": (
                    f"Facial expression suggests {facial_emotion.get('dominant_emotion')} "
                    f"({pct}% stress signal){reported}"
                )
            })

        if (features["app_switch_count"] > 35 and
                primary["bias_type"] != "focus_mismatch"):
            additional.append({
                "type": "focus_mismatch",
                "reason": f"High app switches detected: {features['app_switch_count']}"
            })

        if (features.get("location_checked", True) and
                features["location_match"] == 0 and
                primary["bias_type"] != "context_mismatch"):
            additional.append({
                "type": "context_mismatch",
                "reason": "Location does not match claim"
            })

        if (features.get("calendar_checked", True) and
                features["calendar_match"] == 0):
            additional.append({
                "type": "schedule_mismatch",
                "reason": "No calendar event scheduled"
            })

        return {
            "primary_bias": primary,
            "additional_indicators": additional
        }
