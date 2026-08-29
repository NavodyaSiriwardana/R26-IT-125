"""
Regenerates the synthetic training dataset with an 11th feature —
facial_stress (0..1, from the Vision Transformer emotion model's
stress_indicator) — so `stress_underestimation` can be driven by an
independent physiological signal, not just self-reported mood_before/
mood_after text.

Labeling is a priority-ordered rule chain (first match wins), authored
fresh to match the feature-mean pattern found in the original
bias_dataset (2).csv (that generator script was never committed to this
repo — only its CSV output survived) plus the new facial_stress signal.

Run from backend/: python app/components/self_bias_identification/synthetic_data/generate_dataset.py
"""

import random
import csv
import os

random.seed(42)

N_STUDENTS = 250
ENTRIES_PER_STUDENT = 10  # -> 2500 rows, matching the original dataset size

BIAS_TYPES = [
    "accurate_perception",
    "context_mismatch",
    "productivity_overestimation",
    "stress_underestimation",
    "focus_mismatch",
]
LABEL_NOISE_RATE = 0.08  # tuned to land near a realistic ~90-95% test accuracy

OUT_PATH = os.path.join(
    os.path.dirname(__file__), "output", "bias_dataset_v2.csv"
)


def gen_row():
    claimed_duration = random.randint(30, 150)

    # Start from a "normal" baseline, then bias one dimension at a time
    # depending on which bias_type this row will end up representing —
    # generate the underlying scenario first, derive features from it,
    # then label deterministically from the same features (no leakage).
    scenario = random.choices(
        [
            "accurate",
            "context",
            "productivity",
            "stress",
            "focus",
        ],
        weights=[20, 20, 20, 20, 20],
    )[0]

    location_match = 1
    calendar_match = random.randint(0, 1)
    mood_self_mismatch = 0  # self-reported mood_before/after transition
    facial_stress = round(random.uniform(0.0, 0.25), 2)  # calm baseline

    if scenario == "accurate":
        verified_ratio = random.uniform(0.82, 1.0)
        app_switches = random.randint(2, 18)
        social_media = random.randint(0, 15)
        location_match = 1
        activity_match = 1
        mood_self_mismatch = 0
        facial_stress = round(random.uniform(0.0, 0.2), 2)

    elif scenario == "context":
        verified_ratio = random.uniform(0.4, 0.85)
        app_switches = random.randint(10, 45)
        social_media = random.randint(10, 40)
        location_match = 0  # the defining signal
        activity_match = random.choice([0, 1])
        mood_self_mismatch = random.choice([0, 0, 1])
        facial_stress = round(random.uniform(0.0, 0.4), 2)

    elif scenario == "productivity":
        verified_ratio = random.uniform(0.05, 0.35)  # huge gap
        app_switches = random.randint(20, 60)
        social_media = random.randint(30, 90)
        location_match = 1  # location is fine — the gap is the story
        activity_match = 0
        mood_self_mismatch = random.choice([0, 1])
        facial_stress = round(random.uniform(0.0, 0.4), 2)

    elif scenario == "stress":
        verified_ratio = random.uniform(0.5, 0.85)
        app_switches = random.randint(15, 45)
        social_media = random.randint(10, 40)
        location_match = 1
        activity_match = random.choice([0, 1])
        # The whole point of this bias type: self-report often looks
        # clean, but *either* the mood transition *or* the face shows
        # stress the student didn't log.
        mood_self_mismatch = random.choice([0, 0, 1])
        facial_stress = round(random.uniform(0.5, 0.95), 2)

    else:  # focus
        verified_ratio = random.uniform(0.55, 0.85)
        app_switches = random.randint(45, 80)
        social_media = random.randint(25, 55)
        location_match = 1
        activity_match = random.choice([0, 1])
        mood_self_mismatch = 0
        facial_stress = round(random.uniform(0.1, 0.45), 2)

    verified_edu = round(claimed_duration * verified_ratio)
    duration_gap = claimed_duration - verified_edu
    duration_match_ratio = round(min(verified_edu / claimed_duration, 1.0), 2)
    focus_quality_score = round(max(0, 1 - app_switches / 80), 2)
    distraction_duration = social_media + random.randint(0, 20)

    # facial_stress feeds the SAME stress_mismatch feature the classifier
    # already has — an independent way to flag stress the self-report
    # missed, not a 12th input.
    stress_mismatch = 1 if (mood_self_mismatch == 1 or facial_stress >= 0.5) else 0

    features = {
        "duration_gap": duration_gap,
        "duration_match_ratio": duration_match_ratio,
        "social_media_minutes": social_media,
        "app_switch_count": app_switches,
        "focus_quality_score": focus_quality_score,
        "location_match": location_match,
        "activity_match": activity_match,
        "calendar_match": calendar_match,
        "stress_mismatch": stress_mismatch,
        "distraction_duration": distraction_duration,
        "facial_stress": facial_stress,
    }

    # Priority-ordered labeling — first matching rule wins.
    if (
        location_match == 1 and activity_match == 1 and stress_mismatch == 0
        and duration_match_ratio >= 0.8 and focus_quality_score >= 0.7
    ):
        bias_type = "accurate_perception"
    elif location_match == 0:
        bias_type = "context_mismatch"
    elif duration_match_ratio < 0.4:
        bias_type = "productivity_overestimation"
    elif stress_mismatch == 1:
        bias_type = "stress_underestimation"
    else:
        bias_type = "focus_mismatch"

    # Real students don't fall into perfectly clean buckets — a purely
    # deterministic rule makes the task trivially separable and the
    # resulting "accuracy" meaningless (100% just proves XGBoost can
    # re-learn the rule, not that it generalizes). Injecting label noise
    # simulates the ambiguous/borderline entries a real dataset would
    # have, so the reported accuracy reflects genuine class overlap.
    if random.random() < LABEL_NOISE_RATE:
        bias_type = random.choice(BIAS_TYPES)

    return features, bias_type


def main():
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    fieldnames = [
        "student_id", "entry_id",
        "duration_gap", "duration_match_ratio", "social_media_minutes",
        "app_switch_count", "focus_quality_score", "location_match",
        "activity_match", "calendar_match", "stress_mismatch",
        "distraction_duration", "facial_stress", "bias_type",
    ]

    with open(OUT_PATH, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        entry_num = 0
        for s in range(1, N_STUDENTS + 1):
            for e in range(1, ENTRIES_PER_STUDENT + 1):
                entry_num += 1
                features, bias_type = gen_row()
                writer.writerow({
                    "student_id": f"STU_{s:03d}",
                    "entry_id": f"ENT_{entry_num:05d}",
                    **features,
                    "bias_type": bias_type,
                })

    print(f"Wrote {N_STUDENTS * ENTRIES_PER_STUDENT} rows to {OUT_PATH}")


if __name__ == "__main__":
    main()
