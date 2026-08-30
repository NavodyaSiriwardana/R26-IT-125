class ReflectionBot:
    """Rule-based, template-driven reflection engine — not an LLM.

    Picks a reflection string and action list per bias_type, filled in with
    real claimed-vs-verified numbers from `comparison`. When `history` (the
    user's past bias_results, most-recent-first) shows the same bias_type
    repeating, the action set rotates to a different variation and the
    reflection text acknowledges the recurring pattern, so a repeat
    occurrence doesn't show the exact same advice as last time.
    """

    ACTION_POOLS = {
        "productivity_overestimation": [
            [
                "Block social media during study sessions",
                "Use Pomodoro technique (25 min focus blocks)",
                "Track actual learning outcomes not just time",
            ],
            [
                "Set a specific page/topic goal before you start",
                "Log study time with an app that verifies activity",
                "Study in a location without your phone nearby",
            ],
        ],
        "focus_mismatch": [
            [
                "Enable Do Not Disturb during study",
                "Use single-app focus mode",
                "Take scheduled breaks every 25 minutes",
            ],
            [
                "Turn off non-essential notifications before starting",
                "Keep only the study app open, close the rest",
                "Batch quick app checks into one 5-minute window per hour",
            ],
        ],
        "context_mismatch": [
            [
                "Study in your planned location",
                "Create a dedicated study environment",
                "Track your actual study locations",
            ],
            [
                "Pick one consistent study spot for this week",
                "If plans change, update your claimed location honestly",
                "Note what made the planned location hard to reach",
            ],
        ],
        "stress_underestimation": [
            [
                "Take 5-minute breaks every hour",
                "Practice deep breathing exercises",
                "Reduce your daily task load",
            ],
            [
                "Try a short walk before your next session",
                "Check in with how you actually feel, not just the plan",
                "Consider talking to someone about your workload",
            ],
        ],
        "accurate_perception": [
            [
                "Continue your current study habits",
                "Share your strategies with peers",
                "Set progressively challenging goals",
            ],
            [
                "Keep logging honestly — it's working",
                "Try slightly longer sessions if energy allows",
                "Mentor someone struggling with focus",
            ],
        ],
    }

    def generate(self, bias_type: str,
                 comparison: dict,
                 pas_score: int,
                 history: list = None) -> dict:

        claimed_location = comparison.get("claimed_location", "")
        actual_location = comparison.get("actual_location", "")
        location_match = comparison.get("location_match", 0)

        if bias_type == "context_mismatch":
            if location_match == 0 and claimed_location.lower() != actual_location.lower():
                context_reflection = (
                    f"You claimed to be at {claimed_location} "
                    f"but were detected at {actual_location}. "
                    f"Study where you planned to study."
                )
            else:
                context_reflection = (
                    f"Your claimed location matched your detected location "
                    f"({claimed_location}). However, another context-related signal "
                    f"may have affected the analysis, such as schedule mismatch."
                )

        templates = {
            "productivity_overestimation": (
                f"Your claimed study duration of "
                f"{comparison.get('claimed_duration', 0)} minutes "
                f"was significantly higher than your verified "
                f"educational activity of "
                f"{comparison.get('verified_educational', 0)} "
                f"minutes. Social media usage was "
                f"{comparison.get('social_media_minutes', 0)} "
                f"minutes. Consider setting specific learning goals."
            ),
            "focus_mismatch": (
                f"While your study time was reasonable, "
                f"{comparison.get('app_switches', 0)} app switches "
                f"suggest divided attention. "
                f"Try 25-minute Pomodoro focus blocks."
            ),
            "context_mismatch": context_reflection if bias_type == "context_mismatch" else "",
            "stress_underestimation": (
                f"Despite reporting feeling focused, behavioral "
                f"signals suggest underlying stress. "
                f"Consider taking regular breaks."
            ),
            "accurate_perception": (
                f"Excellent self-awareness! Your PAS score of "
                f"{pas_score}/100 shows strong alignment. "
                f"Keep this momentum going!"
            ),
        }

        reflection_text = templates.get(
            bias_type,
            "Analysis complete. Review your study patterns."
        )

        streak = self._recent_streak(bias_type, history or [])
        pool = self.ACTION_POOLS.get(bias_type, [[]])
        suggested_actions = pool[streak % len(pool)]

        if streak >= 2 and bias_type != "accurate_perception":
            reflection_text += (
                f" This pattern has now shown up in your last "
                f"{streak + 1} entries in a row — since the same advice "
                f"hasn't helped yet, here's a different approach to try."
            )

        return {
            "reflection_text": reflection_text,
            "suggested_actions": suggested_actions,
            "is_recurring": streak >= 1,
            "streak_count": streak + 1,
        }

    def _recent_streak(self, bias_type: str, history: list) -> int:
        """Counts how many of the most recent past entries (newest first,
        not including the one being generated now) share this same
        bias_type consecutively — a run length, not a lifetime total."""
        streak = 0
        for entry in history:
            past_type = (entry.get("primary_bias") or {}).get("bias_type")
            if past_type == bias_type:
                streak += 1
            else:
                break
        return streak
