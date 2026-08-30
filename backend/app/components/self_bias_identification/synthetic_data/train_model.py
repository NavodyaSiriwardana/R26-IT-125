"""
Trains the XGBoost bias classifier on bias_dataset_v2.csv (11 features,
including facial_stress) and reports held-out test accuracy — backs up
the current production model files first, only overwrites them if run
with --apply.

Run from backend/:
    python app/components/self_bias_identification/synthetic_data/train_model.py            # dry run, reports metrics only
    python app/components/self_bias_identification/synthetic_data/train_model.py --apply     # also replaces the production .pkl files
"""

import os
import sys
import shutil
import time
import joblib
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.metrics import accuracy_score, classification_report
from xgboost import XGBClassifier

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_PATH = os.path.join(HERE, "output", "bias_dataset_v2.csv")

MODEL_DIR = os.path.join(
    os.path.dirname(HERE), "ml_models", "trained"
)

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
    "facial_stress",  # new, 11th feature
]


def main():
    apply_changes = "--apply" in sys.argv

    df = pd.read_csv(DATA_PATH)
    X = df[FEATURES]
    y_raw = df["bias_type"]

    encoder = LabelEncoder()
    y = encoder.fit_transform(y_raw)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    model = XGBClassifier(
        n_estimators=200,
        max_depth=5,
        learning_rate=0.1,
        eval_metric="mlogloss",
        random_state=42,
    )
    model.fit(X_train_scaled, y_train)

    preds = model.predict(X_test_scaled)
    acc = accuracy_score(y_test, preds)

    print(f"\nTest accuracy: {acc * 100:.2f}%  ({len(y_test)} held-out rows)\n")
    print(classification_report(y_test, preds, target_names=encoder.classes_))

    if not apply_changes:
        print("Dry run only — pass --apply to replace the production model files.")
        return

    # Back up the current production files before overwriting — a fresh,
    # timestamped folder every run, so re-running --apply never clobbers
    # an earlier backup (that bug cost us the true pre-facial-stress
    # model once already).
    backup_dir = os.path.join(
        MODEL_DIR, f"backup_{time.strftime('%Y%m%d_%H%M%S')}"
    )
    os.makedirs(backup_dir, exist_ok=True)
    for fname in ["xgboost_model.pkl", "scaler.pkl", "label_encoder.pkl"]:
        src = os.path.join(MODEL_DIR, fname)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(backup_dir, fname))
    print(f"Backed up previous model files to {backup_dir}")

    joblib.dump(model, os.path.join(MODEL_DIR, "xgboost_model.pkl"))
    joblib.dump(scaler, os.path.join(MODEL_DIR, "scaler.pkl"))
    joblib.dump(encoder, os.path.join(MODEL_DIR, "label_encoder.pkl"))
    print(f"Wrote new model files to {MODEL_DIR}")


if __name__ == "__main__":
    main()
