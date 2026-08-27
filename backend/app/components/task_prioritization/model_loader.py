import hashlib
import json
import os
from pathlib import Path

import numpy as np
from xgboost import XGBRanker


BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"

MODEL_PATH = MODELS_DIR / "xgb_ranker_model.json"
FEATURES_PATH = MODELS_DIR / "feature_names.json"
CALIBRATOR_PATH = MODELS_DIR / "stage2_score_calibrator.json"
PRIORITY_CONFIG_PATH = (
    MODELS_DIR
    / "stage2_priority_tier_config.json"
)
EXPLANATION_CONFIG_PATH = (
    MODELS_DIR
    / "stage2_final_explanation_config.json"
)
HASH_MANIFEST_PATH = (
    MODELS_DIR
    / "stage2_backend_sha256.json"
)


REQUIRED_FILES = [
    MODEL_PATH,
    FEATURES_PATH,
    CALIBRATOR_PATH,
    PRIORITY_CONFIG_PATH,
    EXPLANATION_CONFIG_PATH,
    HASH_MANIFEST_PATH,
]


def _calculate_sha256(file_path: Path) -> str:
    digest = hashlib.sha256()

    with file_path.open("rb") as file:
        for block in iter(
            lambda: file.read(1024 * 1024),
            b"",
        ):
            digest.update(block)

    return digest.hexdigest()


def _load_json(file_path: Path):
    with file_path.open(
        "r",
        encoding="utf-8",
    ) as file:
        return json.load(file)


# ------------------------------------------------------------
# Validate required files
# ------------------------------------------------------------

missing_files = [
    str(path)
    for path in REQUIRED_FILES
    if not path.exists()
]

if missing_files:
    raise FileNotFoundError(
        "Missing Stage 2 deployment files:\n"
        + "\n".join(missing_files)
    )


# ------------------------------------------------------------
# Verify artifact hashes before loading
# ------------------------------------------------------------

hash_manifest = _load_json(
    HASH_MANIFEST_PATH
)

for filename, expected_hash in (
    hash_manifest.items()
):
    artifact_path = MODELS_DIR / filename

    if not artifact_path.exists():
        raise FileNotFoundError(
            f"Hashed Stage 2 artifact missing: "
            f"{artifact_path}"
        )

    actual_hash = _calculate_sha256(
        artifact_path
    )

    if actual_hash != expected_hash:
        raise ValueError(
            "Stage 2 artifact hash mismatch: "
            f"{filename}"
        )


# ------------------------------------------------------------
# Load XGBRanker
# ------------------------------------------------------------

model = XGBRanker()
model.load_model(MODEL_PATH)


# ------------------------------------------------------------
# Load and validate feature names
# ------------------------------------------------------------

feature_names = _load_json(
    FEATURES_PATH
)

if not isinstance(feature_names, list):
    raise ValueError(
        "feature_names.json must contain "
        "a JSON list."
    )

expected_features = [
    "category",
    "deadline_hours",
    "time_pressure",
    "task_duration",
    "time_of_day",
    "day_of_week",
    "urgency",
    "importance_score",
    "severity",
    "cognitive_load",
    "energy_level",
]

if feature_names != expected_features:
    raise ValueError(
        "Unexpected Stage 2 feature order.\n"
        f"Loaded: {feature_names}\n"
        f"Expected: {expected_features}"
    )

booster_feature_names = (
    model.get_booster().feature_names
)

if booster_feature_names != feature_names:
    raise ValueError(
        "Stage 2 model feature order does "
        "not match feature_names.json.\n"
        f"Model: {booster_feature_names}\n"
        f"JSON: {feature_names}"
    )


# ------------------------------------------------------------
# Load portable isotonic calibrator
# ------------------------------------------------------------

score_calibrator = _load_json(
    CALIBRATOR_PATH
)

if (
    score_calibrator.get("method")
    != "isotonic_regression"
):
    raise ValueError(
        "Unsupported Stage 2 calibrator."
    )

calibrator_x = np.asarray(
    score_calibrator["x_thresholds"],
    dtype=float,
)

calibrator_y = np.asarray(
    score_calibrator["y_thresholds"],
    dtype=float,
)

if (
    calibrator_x.ndim != 1
    or calibrator_y.ndim != 1
    or len(calibrator_x)
    != len(calibrator_y)
    or len(calibrator_x) < 2
):
    raise ValueError(
        "Invalid Stage 2 calibrator arrays."
    )

if not np.all(
    np.diff(calibrator_x) > 0
):
    raise ValueError(
        "Calibrator x-thresholds must be "
        "strictly increasing."
    )

if not np.all(
    np.diff(calibrator_y) >= 0
):
    raise ValueError(
        "Calibrator y-thresholds must be "
        "monotonically increasing."
    )

if not np.all(
    (calibrator_y >= 0.0)
    & (calibrator_y <= 1.0)
):
    raise ValueError(
        "Calibrator outputs must remain "
        "between zero and one."
    )


def calibrate_raw_scores(
    raw_scores,
) -> np.ndarray:
    """
    Convert raw XGBoost ranking margins into
    calibrated relative-priority scores from 0–100.

    These values are not probabilities.
    """

    raw_array = np.asarray(
        raw_scores,
        dtype=float,
    )

    if not np.isfinite(raw_array).all():
        raise ValueError(
            "Raw ranking scores contain "
            "non-finite values."
        )

    calibrated_0_1 = np.interp(
        raw_array,
        calibrator_x,
        calibrator_y,
        left=calibrator_y[0],
        right=calibrator_y[-1],
    )

    return np.clip(
        calibrated_0_1 * 100.0,
        0.0,
        100.0,
    )


# ------------------------------------------------------------
# Load priority/explanation configuration
# ------------------------------------------------------------

priority_config = _load_json(
    PRIORITY_CONFIG_PATH
)

explanation_config = _load_json(
    EXPLANATION_CONFIG_PATH
)


print("✅ Stage 2 deployment artifacts loaded")
print("XGBoost model format: JSON")
print("Model features:", feature_names)
print("Score calibration: isotonic, 0–100")
print(
    "Score interpretation: "
    "relative priority, not probability"
)
print(
    "Artifact integrity: SHA-256 verified"
)