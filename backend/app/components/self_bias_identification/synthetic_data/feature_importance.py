"""
Reports global feature importance for the production bias classifier —
which of the 11 features matter most to the model overall, as opposed
to classifier.py's per-prediction SHAP explanation (which only explains
one entry at a time).

Run from backend/:
    python app/components/self_bias_identification/synthetic_data/feature_importance.py
"""

import os
import joblib
import numpy as np
import pandas as pd
import shap

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(HERE, "output", "bias_dataset_v2.csv")
MODEL_DIR = os.path.join(os.path.dirname(HERE), "ml_models", "trained")

FEATURES = [
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


def main():
    model = joblib.load(os.path.join(MODEL_DIR, "xgboost_model.pkl"))
    scaler = joblib.load(os.path.join(MODEL_DIR, "scaler.pkl"))

    df = pd.read_csv(DATA_PATH)
    X = df[FEATURES]
    X_scaled = scaler.transform(X)

    print("=== XGBoost built-in feature importance (gain) ===\n")
    booster_importance = model.get_booster().get_score(importance_type="gain")
    ranked = sorted(
        ((FEATURES[int(k[1:])], v) for k, v in booster_importance.items()),
        key=lambda pair: pair[1],
        reverse=True,
    )
    for name, score in ranked:
        print(f"  {name:<25} {score:.2f}")

    print("\n=== Mean |SHAP value| across the dataset (per class, averaged) ===\n")
    explainer = shap.TreeExplainer(model)
    shap_values = explainer.shap_values(X_scaled)

    # shap_values shape for multiclass: (n_samples, n_features, n_classes)
    if isinstance(shap_values, list):
        mean_abs = np.mean([np.abs(sv).mean(axis=0) for sv in shap_values], axis=0)
    else:
        mean_abs = np.abs(shap_values).mean(axis=(0, 2)) if shap_values.ndim == 3 else np.abs(shap_values).mean(axis=0)

    ranked_shap = sorted(zip(FEATURES, mean_abs), key=lambda pair: pair[1], reverse=True)
    for name, score in ranked_shap:
        print(f"  {name:<25} {score:.4f}")


if __name__ == "__main__":
    main()
