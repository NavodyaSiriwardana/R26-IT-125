import json
import os

from xgboost import XGBRanker


BASE_DIR = os.path.dirname(__file__)
MODELS_DIR = os.path.join(BASE_DIR, "models")

MODEL_PATH = os.path.join(
    MODELS_DIR,
    "xgb_ranker_model.json",
)

FEATURES_PATH = os.path.join(
    MODELS_DIR,
    "feature_names.json",
)


if not os.path.exists(MODEL_PATH):
    raise FileNotFoundError(
        f"Stage 2 model not found: {MODEL_PATH}"
    )

if not os.path.exists(FEATURES_PATH):
    raise FileNotFoundError(
        f"Stage 2 feature names not found: {FEATURES_PATH}"
    )


model = XGBRanker()
model.load_model(MODEL_PATH)

with open(FEATURES_PATH, "r", encoding="utf-8") as file:
    feature_names = json.load(file)


if not isinstance(feature_names, list):
    raise ValueError(
        "feature_names.json must contain a JSON list."
    )

booster_feature_names = model.get_booster().feature_names

if booster_feature_names != feature_names:
    raise ValueError(
        "Stage 2 model feature order does not match "
        "feature_names.json.\n"
        f"Model: {booster_feature_names}\n"
        f"JSON: {feature_names}"
    )


print("✅ Stage 2 XGBRanker loaded successfully")
print("XGBoost model format: JSON")
print("Features:", feature_names)