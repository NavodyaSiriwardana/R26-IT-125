class PASCalculator:
    """Perception Alignment Score (0-100): how closely a student's diary claim
    matches what the sensors observed. Higher means better alignment.

    Six components, each scored 0-100:
      duration, focus, activity, location, calendar  -> claim vs behaviour
      stress                                         -> self-reported mood vs
                                                        the facial stress signal

    The weights below were chosen by judgement, not fitted to data (the
    original five keep their relative order and sum to 0.90; stress takes 0.10).
    `evaluation/pas_sensitivity.py` tests how much the score depends on them.

    A component that could not be verified for an entry (see
    comparator.MultiSignalComparator) is left out and the remaining weights
    are renormalised, so "could not check" never lowers or raises the score.
    """

    WEIGHTS = {
        "duration": 0.270,
        "focus": 0.225,
        "activity": 0.180,
        "location": 0.135,
        "calendar": 0.090,
        "stress": 0.100,
    }
    # focus has no *_checked flag: app switching is always measured.
    CHECKABLE = ("duration", "activity", "location", "calendar", "stress")

    def calculate(self, features: dict,
                  claimed_duration: int = 0) -> dict:

        scores = {
            "duration": min(features["duration_match_ratio"] * 100, 100),
            "focus": features["focus_quality_score"] * 100,
            "activity": 100 if features["activity_match"] == 1 else 25,
            "location": 100 if features["location_match"] == 1 else 30,
            "calendar": 100 if features["calendar_match"] == 1 else 50,
            "stress": 30 if features.get("stress_mismatch", 0) == 1 else 100,
        }

        included = [
            name for name in self.WEIGHTS
            if name not in self.CHECKABLE
            or features.get(f"{name}_checked", True)
        ]
        total_weight = sum(self.WEIGHTS[n] for n in included)
        pas_score = round(
            sum(scores[n] * self.WEIGHTS[n] for n in included) / total_weight
        )

        return {
            "pas_score": pas_score,
            "level": self._get_level(pas_score),
            "breakdown": {n: round(s) for n, s in scores.items()},
            "not_scored": [n for n in self.WEIGHTS if n not in included],
        }

    def _get_level(self, score: int) -> str:
        if score >= 85:
            return "Excellent Alignment"
        elif score >= 70:
            return "Good Alignment"
        elif score >= 50:
            return "Mild Bias"
        elif score >= 30:
            return "Moderate Bias"
        else:
            return "Severe Bias"
