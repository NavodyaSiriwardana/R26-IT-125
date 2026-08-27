import math
from typing import Any

import numpy as np
import pandas as pd
import shap

from .model_loader import (
    calibrate_raw_scores,
    feature_names,
    model,
    priority_config,
)
from .urgency_calculator import (
    calculate_temporal_urgency,
)


# False for normal production use.
DEBUG_RANKING = False

MAX_REASON_TAGS = 2

CATEGORY_MAP = {
    "academic": 0,
    "health": 1,
    "personal": 2,
    "finance": 3,
    "social": 4,
    "extracurricular": 5,
}

EXPLANATION_GROUPS = {
    "timing": [
        "deadline_hours",
        "time_pressure",
        "urgency",
    ],
    "student_judgement": [
        "importance_score",
        "severity",
    ],
    "effort": [
        "cognitive_load",
        "energy_level",
        "task_duration",
    ],
    "availability_context": [
        "time_of_day",
    ],
}

explainer = shap.TreeExplainer(model)


def _safe_float(
    value: Any,
    default: float,
) -> float:
    try:
        converted = float(value)
    except (TypeError, ValueError):
        converted = default

    if not math.isfinite(converted):
        return default

    return converted


def _clamp(
    value: Any,
    minimum: float,
    maximum: float,
    default: float,
) -> float:
    converted = _safe_float(
        value,
        default,
    )

    return max(
        minimum,
        min(maximum, converted),
    )


def clamp01(value: Any) -> float:
    return _clamp(
        value=value,
        minimum=0.0,
        maximum=1.0,
        default=0.5,
    )


def _category_code(category: Any) -> int:
    normalized = str(
        category
    ).strip().lower()

    if normalized in CATEGORY_MAP:
        return CATEGORY_MAP[normalized]

    if normalized.isdigit():
        numeric_code = int(normalized)

        if 0 <= numeric_code <= 5:
            return numeric_code

    raise ValueError(
        f"Unsupported task category: {category}"
    )


def get_priority(
    normalized_score: float,
) -> str:
    """
    Convert the calibrated relative-priority
    score into the frozen priority tiers.
    """

    score = _clamp(
        normalized_score,
        0.0,
        100.0,
        0.0,
    )

    critical_min = float(
        priority_config[
            "tiers"
        ][
            "Critical"
        ][
            "minimum_inclusive"
        ]
    )

    high_min = float(
        priority_config[
            "tiers"
        ][
            "High"
        ][
            "minimum_inclusive"
        ]
    )

    medium_min = float(
        priority_config[
            "tiers"
        ][
            "Medium"
        ][
            "minimum_inclusive"
        ]
    )

    if score >= critical_min:
        return "Critical"

    if score >= high_min:
        return "High"

    if score >= medium_min:
        return "Medium"

    return "Low"


def _build_contrastive_reason(
    feature: str,
    direction: str,
    feature_value: float,
    query_median: float,
) -> str:
    moved_higher = (
        direction == "raised"
    )

    if feature == "deadline_hours":
        return (
            "Closer deadline than the other tasks"
            if moved_higher
            else "More time remains before its deadline"
        )

    if feature == "time_pressure":
        return (
            "Tighter completion window than the other tasks"
            if moved_higher
            else "More scheduling flexibility than the other tasks"
        )

    if feature == "urgency":
        return (
            "Higher calculated urgency than the other tasks"
            if moved_higher
            else "Lower calculated urgency than the other tasks"
        )

    if feature == "importance_score":
        return (
            "Higher importance rating than the other tasks"
            if moved_higher
            else "Lower importance rating than the other tasks"
        )

    if feature == "severity":
        return (
            "Stronger consequences if delayed"
            if moved_higher
            else "Lower consequences if delayed"
        )

    if feature == "cognitive_load":
        return (
            "Mental-effort estimate helped move it higher"
            if moved_higher
            else "Mental-effort estimate kept it lower"
        )

    if feature == "energy_level":
        return (
            "Energy requirement helped move it higher"
            if moved_higher
            else "Energy requirement kept it lower"
        )

    if feature == "task_duration":
        relative_duration = (
            "shorter"
            if feature_value
            < query_median
            else "longer"
        )

        return (
            f"Its {relative_duration} duration "
            "helped move it higher"
            if moved_higher
            else
            f"Its {relative_duration} duration "
            "kept it lower"
        )

    if feature == "time_of_day":
        relative_time = (
            "earlier"
            if feature_value
            < query_median
            else "later"
        )

        return (
            f"Its {relative_time} availability "
            "helped move it higher"
            if moved_higher
            else
            f"Its {relative_time} availability "
            "kept it lower"
        )

    return (
        "Overall task context helped move it higher"
        if moved_higher
        else "Overall task context kept it lower"
    )


def _generate_contrastive_reasons(
    row_position: int,
    predicted_rank: int,
    dataframe: pd.DataFrame,
    contrastive_shap: np.ndarray,
) -> tuple[list[str], list[dict[str, Any]]]:
    """
    Explain why a task ranked above or below
    the other tasks in the current request.
    """

    task_count = len(dataframe)

    upper_group_size = max(
        1,
        math.ceil(task_count / 2),
    )

    desired_direction = (
        "raised"
        if predicted_rank
        <= upper_group_size
        else "reduced"
    )

    row = dataframe.iloc[
        row_position
    ]

    query_medians = dataframe[
        feature_names
    ].median()

    contribution_map = {
        feature:
            float(
                contrastive_shap[
                    row_position,
                    feature_index,
                ]
            )
        for feature_index, feature
        in enumerate(feature_names)
    }

    grouped_candidates = []

    for (
        group_name,
        group_features,
    ) in EXPLANATION_GROUPS.items():
        matching_features = []

        for feature in group_features:
            contribution = (
                contribution_map[
                    feature
                ]
            )

            if (
                desired_direction == "raised"
                and contribution > 1e-8
            ):
                matching_features.append(
                    feature
                )

            elif (
                desired_direction == "reduced"
                and contribution < -1e-8
            ):
                matching_features.append(
                    feature
                )

        if not matching_features:
            continue

        strongest_feature = max(
            matching_features,
            key=lambda name:
                abs(
                    contribution_map[
                        name
                    ]
                ),
        )

        feature_value = float(
            row[strongest_feature]
        )

        contribution = float(
            contribution_map[
                strongest_feature
            ]
        )

        grouped_candidates.append({
            "group": group_name,
            "feature": strongest_feature,
            "direction": desired_direction,
            "contribution": contribution,
            "reason":
                _build_contrastive_reason(
                    feature=strongest_feature,
                    direction=desired_direction,
                    feature_value=feature_value,
                    query_median=float(
                        query_medians[
                            strongest_feature
                        ]
                    ),
                ),
        })

    grouped_candidates.sort(
        key=lambda item:
            abs(item["contribution"]),
        reverse=True,
    )

    selected = grouped_candidates[
        :MAX_REASON_TAGS
    ]

    if not selected:
        selected = [{
            "group": "overall",
            "feature": "overall_context",
            "direction": desired_direction,
            "contribution": 0.0,
            "reason": (
                "Overall task context helped move it higher"
                if desired_direction == "raised"
                else "Overall task context kept it lower"
            ),
        }]

    reason_tags = [
        item["reason"]
        for item in selected
    ]

    return reason_tags, selected


def _build_feature_record(
    task: dict[str, Any],
) -> dict[str, float | int]:
    category = _category_code(
        task.get(
            "category",
            "academic",
        )
    )

    deadline_hours = max(
        _safe_float(
            task.get(
                "deadline_hours",
                24.0,
            ),
            24.0,
        ),
        0.0,
    )

    time_pressure = _clamp(
        value=task.get(
            "time_pressure",
            1.0,
        ),
        minimum=0.0,
        maximum=200.0,
        default=1.0,
    )

    urgency_source = str(
        task.get(
            "urgency_source",
            "calculated",
        )
    ).strip().lower()

    if urgency_source == "user_adjusted":
        final_urgency = clamp01(
            task.get(
                "urgency",
                0.5,
            )
        )
    else:
        final_urgency = (
            calculate_temporal_urgency(
                deadline_hours=
                    deadline_hours,
                time_pressure=
                    time_pressure,
            )
        )

    return {
        "category": category,

        "deadline_hours":
            deadline_hours,

        "time_pressure":
            time_pressure,

        "task_duration": int(
            _clamp(
                task.get(
                    "task_duration",
                    3,
                ),
                1,
                5,
                3,
            )
        ),

        "time_of_day": int(
            _clamp(
                task.get(
                    "time_of_day",
                    9,
                ),
                0,
                23,
                9,
            )
        ),

        # Monday=0, ..., Sunday=6.
        "day_of_week": int(
            _clamp(
                task.get(
                    "day_of_week",
                    0,
                ),
                0,
                6,
                0,
            )
        ),

        "urgency":
            clamp01(final_urgency),

        "importance_score":
            clamp01(
                task.get(
                    "importance_score",
                    0.5,
                )
            ),

        "severity":
            clamp01(
                task.get(
                    "severity",
                    0.5,
                )
            ),

        "cognitive_load":
            clamp01(
                task.get(
                    "cognitive_load",
                    0.5,
                )
            ),

        "energy_level":
            clamp01(
                task.get(
                    "energy_level",
                    0.5,
                )
            ),
    }


def rank_tasks(
    tasks: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """
    Rank one current list of student tasks.

    The calibrated score is a relative-priority
    score, not a probability.
    """

    if not tasks:
        return []

    records = [
        _build_feature_record(task)
        for task in tasks
    ]

    dataframe = pd.DataFrame(
        records,
        columns=feature_names,
    )

    if dataframe.empty:
        return []

    if not np.isfinite(
        dataframe.to_numpy(
            dtype=float
        )
    ).all():
        raise ValueError(
            "Stage 2 input contains "
            "non-finite feature values."
        )

    raw_predictions = np.asarray(
        model.predict(dataframe),
        dtype=float,
    )

    if not np.isfinite(
        raw_predictions
    ).all():
        raise ValueError(
            "Stage 2 produced non-finite "
            "ranking scores."
        )

    normalized_scores = (
        calibrate_raw_scores(
            raw_predictions
        )
    )

    predicted_order = np.argsort(
        -raw_predictions,
        kind="stable",
    )

    predicted_ranks = np.empty(
        len(tasks),
        dtype=int,
    )

    predicted_ranks[
        predicted_order
    ] = np.arange(
        1,
        len(tasks) + 1,
    )

    shap_values = np.asarray(
        explainer.shap_values(
            dataframe,
            check_additivity=True,
        ),
        dtype=float,
    )

    if shap_values.shape != (
        len(tasks),
        len(feature_names),
    ):
        raise ValueError(
            "Unexpected Stage 2 SHAP shape: "
            f"{shap_values.shape}"
        )

    # Query-centred contrastive SHAP.
    contrastive_shap = (
        shap_values
        - shap_values.mean(
            axis=0,
            keepdims=True,
        )
    )

    # Verify contrastive explanation fidelity.
    actual_deviation = (
        raw_predictions
        - raw_predictions.mean()
    )

    reconstructed_deviation = (
        contrastive_shap.sum(
            axis=1
        )
    )

    maximum_explanation_error = float(
        np.max(
            np.abs(
                actual_deviation
                - reconstructed_deviation
            )
        )
    )

    if maximum_explanation_error > 1e-4:
        raise ValueError(
            "Contrastive SHAP additivity "
            "validation failed: "
            f"{maximum_explanation_error}"
        )

    results = []

    for index, task in enumerate(tasks):
        pred_score = float(
            raw_predictions[index]
        )

        normalized_score = round(
            float(
                normalized_scores[index]
            ),
            1,
        )

        priority = get_priority(
            normalized_score
        )

        predicted_rank = int(
            predicted_ranks[index]
        )

        (
            reason_tags,
            reason_details,
        ) = _generate_contrastive_reasons(
            row_position=index,
            predicted_rank=predicted_rank,
            dataframe=dataframe,
            contrastive_shap=
                contrastive_shap,
        )

        result = {
            **task,

            "deadline_hours": float(
                dataframe.iloc[
                    index
                ][
                    "deadline_hours"
                ]
            ),

            "time_pressure": float(
                dataframe.iloc[
                    index
                ][
                    "time_pressure"
                ]
            ),

            "urgency": float(
                dataframe.iloc[
                    index
                ][
                    "urgency"
                ]
            ),

            "pred_score": pred_score,

            "normalized_score":
                normalized_score,

            "score_interpretation":
                "relative_priority_not_probability",

            "priority": priority,

            "rank_position":
                predicted_rank,

            "reason_tags":
                reason_tags,

            "reason_details":
                reason_details,
        }

        results.append(result)

    results.sort(
        key=lambda item:
            item["pred_score"],
        reverse=True,
    )

    if DEBUG_RANKING:
        print(
            "\nStage 2 ranking result:"
        )

        for result in results:
            print({
                "title":
                    result.get("title"),
                "raw_score":
                    result["pred_score"],
                "normalized_score":
                    result[
                        "normalized_score"
                    ],
                "priority":
                    result["priority"],
                "rank_position":
                    result[
                        "rank_position"
                    ],
                "reason_tags":
                    result["reason_tags"],
            })

        print(
            "Maximum contrastive SHAP error:",
            maximum_explanation_error,
        )

    return results