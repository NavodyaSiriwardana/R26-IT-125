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
                "Write down what you learned at the end of each session",
                "Keep your phone in another room while you study",
            ],
            [
                "Set a specific page/topic goal before you start",
                "Log study time with an app that verifies activity",
                "Study in a location without your phone nearby",
                "Review what you covered before you stop for the day",
                "Start with the hardest topic while your energy is high",
            ],
        ],
        "focus_mismatch": [
            [
                "Enable Do Not Disturb during study",
                "Use single-app focus mode",
                "Take scheduled breaks every 25 minutes",
                "Silence group chats while you study",
                "Put your phone face down, out of reach",
            ],
            [
                "Turn off non-essential notifications before starting",
                "Keep only the study app open, close the rest",
                "Batch quick app checks into one 5-minute window per hour",
                "Write down distracting thoughts and deal with them later",
                "Plan the next session before you finish this one",
            ],
        ],
        "context_mismatch": [
            [
                "Study in your planned location",
                "Create a dedicated study environment",
                "Track your actual study locations",
                "Plan your route and travel time before you leave",
                "Tell a friend where you plan to study",
            ],
            [
                "Pick one consistent study spot for this week",
                "If plans change, update your claimed location honestly",
                "Note what made the planned location hard to reach",
                "Keep a backup study spot close by",
                "Check the location is open before you go",
            ],
        ],
        "stress_underestimation": [
            [
                "Take 5-minute breaks every hour",
                "Practice deep breathing exercises",
                "Reduce your daily task load",
                "Drink water and step into daylight between sessions",
                "Sleep at a regular time to help recovery",
            ],
            [
                "Try a short walk before your next session",
                "Check in with how you actually feel, not just the plan",
                "Consider talking to someone about your workload",
                "Drop one task from today if you can",
                "Write down what is worrying you before you start",
            ],
        ],
        "accurate_perception": [
            [
                "Continue your current study habits",
                "Share your strategies with peers",
                "Set progressively challenging goals",
                "Keep logging every entry to track your progress",
                "Reward yourself after a good session",
            ],
            [
                "Keep logging honestly — it's working",
                "Try slightly longer sessions if energy allows",
                "Mentor someone struggling with focus",
                "Review your best session and repeat what worked",
                "Plan a rest day so you stay consistent",
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
            "accurate_perception": self._accurate_text(pas_score),
        }

        reflection_text = templates.get(
            bias_type,
            "Analysis complete. Review your study patterns."
        )

        reflection_text += self._unscored_note(comparison)

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

    @staticmethod
    def _accurate_text(pas_score: int) -> str:
        """No single bias stood out, but the praise must match the PAS level."""
        if pas_score >= 70:
            return (
                f"Excellent self-awareness! Your PAS score of "
                f"{pas_score}/100 shows strong alignment. "
                f"Keep this momentum going!"
            )
        if pas_score >= 50:
            return (
                f"No single bias stood out, but your PAS score of "
                f"{pas_score}/100 shows only partial alignment between your "
                f"entry and what was observed. Check the details below."
            )
        return (
            f"No single bias stood out, but your PAS score of "
            f"{pas_score}/100 shows a large gap between your entry and what "
            f"was observed. Review the details below."
        )

    @staticmethod
    def _unscored_note(comparison: dict) -> str:
        """Tell the student which signals could not be checked, so a missing
        check is never mistaken for a clean (or failed) one."""
        notes = []
        if comparison.get("is_study_category") and comparison.get("duration_checked") is False:
            notes.append("your entry had no duration, so study time was not scored")
        if comparison.get("location_checked") is False:
            notes.append("your location could not be verified, so it was not scored")
        if not notes:
            return ""
        return " Note: " + " and ".join(notes) + "."

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
