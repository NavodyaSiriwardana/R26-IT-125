import pandas as pd
import math
import numpy as np
import shap
from .model_loader import model, feature_names

from .urgency_calculator import calculate_temporal_urgency

explainer = shap.Explainer(model)

# ── Developer debugging ──────────────────────────────────────────────────────
# True  = print ranking inputs/scores to backend terminal
# False = production mode, no ranking debug output
DEBUG_RANKING = True

# ── Feature label maps — used for tag WORDING based on actual value ──────────
# Each feature has 3 levels: high / moderate / low
FEATURE_LABELS = {
    "urgency": {
        "high":     "High urgency",
        "moderate": "Moderate urgency",
        "low":      "Low urgency",
    },
    "importance_score": {
        "high":     "High importance",
        "moderate": "Moderate importance",
        "low":      "Low importance",
    },
    "severity": {
        "high":     "High severity",
        "moderate": "Moderate severity",
        "low":      "Low severity",
    },
    "cognitive_load": {
        "high":     "Requires significant effort",
        "moderate": "Moderate workload",
        "low":      "Low effort task",
    },
    "energy_level": {
        "high":     "High energy demand",
        "moderate": "Moderate energy required",
        "low":      "Low energy required",
    },
    "deadline_hours": {
        "high":     "Deadline is far",       # high hours = far deadline = negative for priority
        "moderate": "Approaching deadline",
        "low":      "Close deadline",         # low hours = close deadline = positive for priority
    },
    "time_pressure": {
        "high":     "Plenty of time available",   # high ratio = lots of time = negative
        "moderate": "Moderate time pressure",
        "low":      "High time pressure",          # low ratio = tight = positive
    },
    "task_duration": {
        "high":     "Long task duration",
        "moderate": "Moderate task duration",
        "low":      "Short task",
    },
}



# ── Number of SHAP-ranked feature tags to show per task ──────────────────────
# Was 3 — bumped to 4 to surface secondary influential features (e.g.
# cognitive_load, time_pressure) more often, without touching the SHAP
# ranking logic itself. This is still 100% faithful to true SHAP magnitude —
# we're just widening the cutoff, not injecting or reordering anything.
TOP_N_TAGS = 5

# Derived from development-set predictions produced by the
# XGBoost 3.2.0 Stage 2 training notebook.
SCORE_CENTER = 0.03685249201953411
SCORE_SCALE = 1.0446737801327481

CATEGORY_MAP = {
    "academic":        0,
    "health":          1,
    "personal":        2,
    "finance":         3,
    "social":          4,
    "extracurricular": 5,
}


def normalize_score(score: float) -> float:
    z = (score - SCORE_CENTER) / SCORE_SCALE
    normalized = 1.0 / (1.0 + math.exp(-z))
    return round(normalized * 100, 1)



def get_priority(normalized: float) -> str:
    if normalized >= 85:
        return "Critical"
    if normalized >= 70:
        return "High"
    if normalized >= 50:
        return "Medium"
    return "Low"

def _value_level(feature: str, value: float) -> str:
    """
    Return 'high', 'moderate', or 'low' for a feature based on its actual value.
    Thresholds: >= 0.65 → high, >= 0.35 → moderate, < 0.35 → low
    For inverted features (deadline_hours, time_pressure) we use absolute value
    but the LABEL meanings are already flipped in FEATURE_LABELS.
    """
    if feature == "deadline_hours":
        # Normalize deadline_hours: < 12h = low (close), 12-72h = moderate, > 72h = high (far)
        if value < 12:   return "low"
        if value < 72:   return "moderate"
        return "high"
    if feature == "time_pressure":
        # time_pressure = deadline_hours / task_hours
        # Low ratio = tight pressure, high ratio = plenty of time
        if value < 3:    return "low"
        if value < 10:   return "moderate"
        return "high"
    if feature == "task_duration":
        # task_duration is code 1-5
        if value >= 4:   return "high"
        if value >= 2:   return "moderate"
        return "low"
    # All other features are 0-1 scale
    if value >= 0.65:  return "high"
    if value >= 0.35:  return "moderate"
    return "low"


def generate_reason_tags(
    shap_vals,
    feature_names,
    feature_values,
    normalized_score
):
    """
    Generate reason tags using SHAP contribution strength.

    SHAP determines which features influenced the prediction.
    Actual feature values determine whether the wording is
    high, moderate, or low.
    """

    feature_contrib = list(zip(feature_names, shap_vals))

    # Most influential feature first.
    sorted_by_impact = sorted(
        feature_contrib,
        key=lambda x: abs(x[1]),
        reverse=True
    )

    tags = []

    # Use exactly the same thresholds as get_priority().
    if normalized_score >= 85:
        # Critical: show features that positively increased priority.
        for feature, shap_value in sorted_by_impact:
            if feature not in FEATURE_LABELS:
                continue

            if shap_value <= 0.01:
                continue

            value = feature_values.get(feature, 0.5)
            level = _value_level(feature, value)

            tags.append(FEATURE_LABELS[feature][level])

            if len(tags) >= TOP_N_TAGS:
                break

        if not tags:
            tags = ["Very high overall priority"]

        tags.append("Requires immediate attention")

    elif normalized_score >= 70:
        # High: primarily show positive contributors.
        for feature, shap_value in sorted_by_impact:
            if feature not in FEATURE_LABELS:
                continue

            if shap_value <= 0.01:
                continue

            value = feature_values.get(feature, 0.5)
            level = _value_level(feature, value)

            tags.append(FEATURE_LABELS[feature][level])

            if len(tags) >= TOP_N_TAGS:
                break

        if not tags:
            tags = ["High overall priority"]

    elif normalized_score >= 50:
        # Medium: show the strongest overall influences.
        for feature, shap_value in sorted_by_impact:
            if feature not in FEATURE_LABELS:
                continue

            if abs(shap_value) <= 0.01:
                continue

            value = feature_values.get(feature, 0.5)
            level = _value_level(feature, value)

            tags.append(FEATURE_LABELS[feature][level])

            if len(tags) >= TOP_N_TAGS:
                break

        if not tags:
            tags = ["Moderate task priority"]

    else:
        # Low: show features that reduced priority.
        for feature, shap_value in sorted_by_impact:
            if feature not in FEATURE_LABELS:
                continue

            if shap_value >= -0.01:
                continue

            value = feature_values.get(feature, 0.5)
            level = _value_level(feature, value)

            tags.append(FEATURE_LABELS[feature][level])

            if len(tags) >= TOP_N_TAGS:
                break

        if not tags:
            tags = ["Low overall priority"]

    return tags


def clamp01(value):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return 0.5

    return max(0.0, min(1.0, value))

def rank_tasks(tasks: list) -> list:
    """
    Rank a list of tasks using XGBRanker + SHAP explanations.

    Each task dict must contain:
      urgency, importance_score, severity, cognitive_load, energy_level,
      deadline_hours, time_pressure, category (string), task_duration,
      time_of_day, day_of_week

    Returns the same list sorted by pred_score descending,
    with normalized_score, priority, and reason_tags added.
    """
    if not tasks:
        return []

    records = []

    for t in tasks:
        cat = t.get("category", "academic")

        cat_id = CATEGORY_MAP.get(
            str(cat).lower(),
            int(cat) if str(cat).isdigit() else 0,
        )

        deadline_hours = max(
            float(t.get("deadline_hours", 24.0)),
            0.0,
        )

        time_pressure = max(
            float(t.get("time_pressure", 1.0)),
            0.0,
        )

        urgency_source = str(
            t.get("urgency_source", "calculated")
        ).lower()

        if urgency_source == "user_adjusted":
            final_urgency = clamp01(
                t.get("urgency", 0.5)
            )
        else:
            final_urgency = calculate_temporal_urgency(
                deadline_hours=deadline_hours,
                time_pressure=time_pressure,
            )

        records.append({
            "deadline_hours": deadline_hours,
            "time_pressure": time_pressure,
            "urgency": final_urgency,
            "importance_score": clamp01(
                t.get("importance_score", 0.5)
            ),
            "severity": clamp01(
                t.get("severity", 0.5)
            ),
            "cognitive_load": clamp01(
                t.get("cognitive_load", 0.5)
            ),
            "energy_level": clamp01(
                t.get("energy_level", 0.5)
            ),
            "category": cat_id,
            "task_duration": int(
                t.get("task_duration", 3)
            ),
            "time_of_day": int(
                t.get("time_of_day", 9)
            ),
            "day_of_week": int(
                t.get("day_of_week", 0)
            ),
        })

    df = pd.DataFrame(records)[feature_names]

    # ── DEBUG: exact features entering XGBRanker ────────────────────────────────
    if DEBUG_RANKING:
        print("\n")
        print("=" * 70)
        print("              XGBRANKER INPUT")
        print("=" * 70)

        for i, task in enumerate(tasks):

            print(f"\nTASK {i + 1}")

            print(f"ID:    {task.get('_doc_id', 'N/A')}")
            print(f"Title: {task.get('title', 'Title not sent')}")

            print("-" * 50)

            for feature in feature_names:
                print(
                    f"{feature:<20} = "
                    f"{df.iloc[i][feature]}"
                )

            print("-" * 50)

        print("=" * 70)

    # ── XGBRanker prediction ──────────────────────────────────────────────────
    print("\n========== XGBRANKER INPUT ==========")

    for i, task in enumerate(tasks):
        print(f"\nTask {i + 1}:")
        print("ID:", task.get("_doc_id"))
        print(df.iloc[i].to_dict())

    print("=====================================\n")    

    preds = model.predict(df)

    if DEBUG_RANKING:

        print("\n")
        print("=" * 70)
        print("              XGBRANKER RAW PREDICTIONS")
        print("=" * 70)

        for i, score in enumerate(preds):

            task = tasks[i]

            print(
                f"Task {i + 1} | "
                f"ID={task.get('_doc_id', 'N/A')} | "
                f"Title={task.get('title', 'N/A')} | "
                f"Raw Score={float(score):.6f}"
            )

        print("=" * 70)

    for i, score in enumerate(preds):
        print(
            f"Task {i + 1} | "
            f"ID={tasks[i].get('_doc_id')} | "
            f"Raw XGB score={float(score):.6f}"
        )

    # ── SHAP explanations ─────────────────────────────────────────────────────
    shap_values = explainer(df)

    results = []
    for i, task in enumerate(tasks):
        pred_score  = float(preds[i])
        normalized  = normalize_score(pred_score)
        priority    = get_priority(normalized)

        if DEBUG_RANKING:
            print(
                f"\nFINAL → "
                f"{task.get('title', task.get('_doc_id', 'Unknown Task'))}"
                f" | raw={pred_score:.6f}"
                f" | normalized={normalized}/100"
                f" | priority={priority}"
            )

        # Build feature value dict for this task (for value-based tag wording)
        feature_values = {fn: float(df.iloc[i][fn]) for fn in feature_names}

        reason_tags = generate_reason_tags(
            shap_values.values[i],
            feature_names,
            feature_values,
            normalized,
        )

        results.append({
            **task,

            # Return current calculated/user-preserved ranking features.
            "deadline_hours": float(
                df.iloc[i]["deadline_hours"]
            ),
            "time_pressure": float(
                df.iloc[i]["time_pressure"]
            ),
            "urgency": float(
                df.iloc[i]["urgency"]
            ),

            "pred_score": pred_score,
            "normalized_score": normalized,
            "priority": priority,
            "reason_tags": reason_tags,
        })

    # Sort by pred_score descending
    results.sort(key=lambda x: x["pred_score"], reverse=True)
    return results