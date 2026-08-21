from datetime import datetime

import numpy as np
import pandas as pd

from .stage1_model_loader import stage1_model

from datetime import datetime

from .stage1_model_loader import stage1_model
from .urgency_calculator import (
    calculate_temporal_urgency,
    clamp01,
)


# The Stage 1 model was trained using these synthetic category codes.
CATEGORY_MAP = {
    "academic": "0",
    "health": "1",
    "personal": "2",
    "finance": "3",
    "social": "4",
    "extracurricular": "5",
}


def predict_scores(
    title: str,
    description: str,
    category: str,
    start_time: str,
    end_time: str,
    task_duration: int,
    estimated_duration_minutes: int,
) -> dict:
    """
    Stage 1 hybrid feature generation:

    - Urgency: calculated from deadline and time pressure.
    - Cognitive load: predicted by the trained regression model.
    - Energy required: predicted by the trained regression model.
    - Importance: entered by the student.
    - Severity/consequence: entered by the student.
    """

    # Validate timestamps.
    start_dt = datetime.fromisoformat(start_time)
    end_dt = datetime.fromisoformat(end_time)

    # Use a compatible current time for timezone-aware timestamps.
    if end_dt.tzinfo is not None:
        now = datetime.now(end_dt.tzinfo)
    else:
        now = datetime.now()

    if not end_dt > start_dt:
        raise ValueError(
            "The task end time must be after the start time."
        )

    if estimated_duration_minutes <= 0:
        raise ValueError(
            "Estimated duration must be greater than zero."
        )

    # Objective timing features.
    deadline_hours = max(
        (end_dt - now).total_seconds() / 3600.0,
        0.0,
    )

    task_hours = max(
        estimated_duration_minutes / 60.0,
        0.25,
    )

    time_pressure = min(
        deadline_hours / task_hours,
        200.0,
    )

    normalized_category = category.strip().lower()

    if normalized_category not in CATEGORY_MAP:
        raise ValueError(
            f"Unsupported task category: {category}"
        )

    # Keep the duration code within the range used during training.
    safe_duration_code = max(
        1,
        min(5, int(task_duration)),
    )

    # This exact separator was used during Stage 1 training.
    combined_text = (
        f"{title.strip()} "
        f"[DESCRIPTION] "
        f"{description.strip()}"
    )

    model_input = pd.DataFrame([
        {
            "combined_text": combined_text,
            "category": CATEGORY_MAP[normalized_category],
            "task_duration": safe_duration_code,
        }
    ])

    prediction = stage1_model.predict(model_input)[0]

    cognitive_load = round(
        clamp01(np.clip(prediction[0], 0.0, 1.0)),
        4,
    )

    energy_required = round(
        clamp01(np.clip(prediction[1], 0.0, 1.0)),
        4,
    )

    temporal_urgency = calculate_temporal_urgency(
        deadline_hours=deadline_hours,
        time_pressure=time_pressure,
    )

    return {
        "predicted_scores": {
            "urgency": temporal_urgency,
            "cognitive_load": cognitive_load,

            # Keep the existing internal name for XGBRanker compatibility.
            "energy_level": energy_required,
        },

        "score_sources": {
            "urgency": "calculated",
            "importance_score": "student_input",
            "severity": "student_input",
            "cognitive_load": "model_predicted",
            "energy_level": "model_predicted",
        },

        "deadline_hours": round(deadline_hours, 2),
        "time_pressure": round(time_pressure, 2),
    }