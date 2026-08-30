class PASCalculator:

    def calculate(self, features: dict,
                  claimed_duration: int = 0) -> dict:

        duration_score = min(
            features["duration_match_ratio"] * 100, 100)
        focus_score = features["focus_quality_score"] * 100
        activity_score = (
            100 if features["activity_match"] == 1 else 25)
        location_score = (
            100 if features["location_match"] == 1 else 30)
        calendar_score = (
            100 if features["calendar_match"] == 1 else 50)

        pas_score = round(
            duration_score  * 0.30 +
            focus_score     * 0.25 +
            activity_score  * 0.20 +
            location_score  * 0.15 +
            calendar_score  * 0.10
        )

        return {
            "pas_score": pas_score,
            "level": self._get_level(pas_score),
            "breakdown": {
                "duration":  round(duration_score),
                "focus":     round(focus_score),
                "activity":  round(activity_score),
                "location":  round(location_score),
                "calendar":  round(calendar_score),
            }
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