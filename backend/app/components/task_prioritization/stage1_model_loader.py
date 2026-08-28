import os
import joblib


BASE_DIR = os.path.dirname(__file__)

MODEL_PATH = os.path.join(
    BASE_DIR,
    "models",
    "stage1_attribute_predictor.pkl",
)

if not os.path.exists(MODEL_PATH):
    raise FileNotFoundError(
        f"Stage 1 model was not found: {MODEL_PATH}"
    )

stage1_model = joblib.load(MODEL_PATH)

print("✅ Stage 1 attribute predictor loaded successfully")