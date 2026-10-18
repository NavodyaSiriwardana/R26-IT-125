class MoodSupport:
    """Rule-based mood-fix engine — not an LLM.

    Turns the facial-analysis result (emotion scores + stress_indicator from
    facial_service.py) plus the self-reported mood into:
      * a mood state ("stressed", "uneasy", "low", "tired", "calm", "positive")
      * a short, personalised action list that rotates away from what the
        user was shown last time
      * a stress trend over the user's recent entries
      * an escalation flag after repeated high stress

    The 2-minute in-app breathing reset itself is not one of the "actions" —
    the frontend offers it as a dedicated button whenever `needs_reset`.
    """

    STRESS_HIGH = 0.5
    STRESS_UNEASY = 0.3
    SAD_LOW = 0.3
    MIN_CONFIDENCE = 0.35
    ESCALATE_STREAK = 3

    NEGATIVE_REPORTED = {"stressed": "stressed", "tired": "tired", "bored": "low"}
    POSITIVE_REPORTED = {"motivated", "happy", "normal"}

    LABELS = {
        "stressed": "Stressed",
        "uneasy": "Uneasy",
        "low": "Feeling low",
        "tired": "Tired",
        "calm": "Calm",
        "positive": "Positive",
    }
    RESET_STATES = {"stressed", "uneasy", "low", "tired"}

    BREATHING = {"inhale": 4, "hold": 7, "exhale": 8, "rounds": 6}

    # id -> (title, detail, minutes, kind, states it fits)
    ACTIONS = {
        "walk": ("Walk away from the screen",
                 "Water and daylight, leave your phone behind.", 5, "break",
                 {"stressed", "uneasy", "tired", "low"}),
        "split": ("Split your next block in two",
                  "Two shorter focus blocks with a break between them.", 0, "plan",
                  {"stressed", "uneasy"}),
        "music": ("Low-tempo music, no lyrics",
                  "Let your heart rate settle before you restart.", 10, "music",
                  {"stressed", "uneasy", "low"}),
        "stretch": ("Neck and shoulder stretch",
                    "Release the tension that builds up from screen posture.", 3, "body",
                    {"stressed", "tired", "uneasy"}),
        "journal": ("Write down one thing that went well",
                    "Shifts attention from what is draining you.", 3, "reflect",
                    {"low", "uneasy"}),
        "rest": ("Close your eyes and rest",
                 "Short rest, no screens, no scrolling.", 5, "rest",
                 {"tired", "low"}),
        "easy_task": ("Pick the easiest task first",
                      "A quick win rebuilds momentum when energy is low.", 0, "plan",
                      {"low", "tired"}),
        "focus_window": ("Use this focus window",
                         "Start your hardest task while you feel settled.", 0, "plan",
                         {"calm", "positive"}),
        "log_working": ("Note what is working today",
                        "One line in your diary helps you repeat it.", 2, "reflect",
                        {"calm", "positive"}),
        "talk": ("Talk to someone about your workload",
                 "A friend, a lecturer or a counsellor. You do not have to carry it alone.",
                 0, "social", {"stressed", "uneasy", "low"}),
    }
    PRIORITY = ["walk", "stretch", "music", "split", "journal", "rest",
                "easy_task", "focus_window", "log_working"]

    # ------------------------------------------------------------------
    # Mood derivation
    # ------------------------------------------------------------------

    def derive_mood(self, facial_emotion: dict | None,
                    mood_after: str = "") -> dict:
        reported = (mood_after or "").lower()
        facial_ok = bool(facial_emotion) and facial_emotion.get("status") == "success"

        if facial_ok and facial_emotion.get("confidence", 1) >= self.MIN_CONFIDENCE:
            stress = float(facial_emotion.get("stress_indicator", 0) or 0)
            scores = facial_emotion.get("emotion_scores") or {}
            dominant = facial_emotion.get("dominant_emotion", "")
            if stress >= self.STRESS_HIGH:
                state = "stressed"
            elif scores.get("sad", 0) >= self.SAD_LOW:
                state = "low"
            elif stress >= self.STRESS_UNEASY:
                state = "uneasy"
            elif dominant in ("happy", "surprise"):
                state = "positive"
            else:
                state = "calm"
            mismatch = (
                state in self.RESET_STATES and reported in self.POSITIVE_REPORTED
            )
            return {
                "state": state, "label": self.LABELS[state],
                "stress": round(stress, 2), "source": "camera",
                "reported": mood_after, "mismatch": mismatch,
            }

        # No usable camera reading — fall back to what the user reported.
        if reported in self.NEGATIVE_REPORTED:
            state = self.NEGATIVE_REPORTED[reported]
            return {"state": state, "label": self.LABELS[state], "stress": None,
                    "source": "self_report", "reported": mood_after, "mismatch": False}
        state = "positive" if reported in ("happy", "motivated") else "calm"
        return {"state": state, "label": self.LABELS[state], "stress": None,
                "source": "self_report" if reported else "none",
                "reported": mood_after, "mismatch": False}

    # ------------------------------------------------------------------
    # Trend / history helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _stress_of(entry: dict):
        facial = (entry.get("comparison") or {}).get("facial_emotion") or {}
        if facial.get("status") != "success":
            return None
        return float(facial.get("stress_indicator", 0) or 0)

    def _trend(self, current_stress, history: list) -> dict:
        """history is newest-first, not including the current entry."""
        past = [s for s in (self._stress_of(h) for h in history) if s is not None]
        values = list(reversed(past[:4]))
        if current_stress is not None:
            values.append(current_stress)
        values = [round(v, 2) for v in values]

        direction = "steady"
        if len(values) >= 3:
            delta = values[-1] - values[0]
            if delta >= 0.1 and values[-1] >= values[-2]:
                direction = "rising"
            elif delta <= -0.1 and values[-1] <= values[-2]:
                direction = "falling"
        return {"values": values, "direction": direction}

    def _high_stress_streak(self, current_stress, history: list) -> int:
        if current_stress is None or current_stress < self.STRESS_HIGH:
            return 0
        streak = 1
        for h in history:
            s = self._stress_of(h)
            if s is not None and s >= self.STRESS_HIGH:
                streak += 1
            else:
                break
        return streak

    @staticmethod
    def _last_action_ids(history: list) -> set:
        if not history:
            return set()
        ms = history[0].get("mood_support") or {}
        return {a.get("id") for a in ms.get("actions", [])}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def build(self, facial_emotion: dict | None, mood_before: str,
              mood_after: str, claimed_duration: int,
              history: list | None = None) -> dict:
        history = history or []
        mood = self.derive_mood(facial_emotion, mood_after)
        state = mood["state"]
        trend = self._trend(mood["stress"], history)
        streak = self._high_stress_streak(mood["stress"], history)
        escalate = streak >= self.ESCALATE_STREAK
        needs_reset = state in self.RESET_STATES

        actions = self._pick_actions(state, escalate, claimed_duration,
                                     self._last_action_ids(history))
        return {
            "mood": mood,
            "needs_reset": needs_reset,
            "reason": self._reason(mood, trend, streak),
            "actions": actions,
            "trend": trend,
            "escalate": escalate,
            "breathing": self.BREATHING,
        }

    def _pick_actions(self, state: str, escalate: bool,
                      claimed_duration: int, last_ids: set) -> list:
        fits = [i for i in self.PRIORITY if state in self.ACTIONS[i][4]]
        fresh = [i for i in fits if i not in last_ids]
        # Fall back to repeats only when there are not enough fresh options.
        ordered = fresh + [i for i in fits if i in last_ids]
        chosen = ordered[:4]
        if escalate:
            chosen = ["talk"] + chosen[:3]

        out = []
        for action_id in chosen:
            title, detail, minutes, kind, _ = self.ACTIONS[action_id]
            if action_id == "split" and claimed_duration >= 50:
                half = max(25, round(claimed_duration / 2 / 5) * 5)
                detail = (f"Two {half}-minute blocks instead of "
                          f"{claimed_duration} minutes straight.")
            out.append({"id": action_id, "title": title, "detail": detail,
                        "minutes": minutes, "kind": kind})
        return out

    def _reason(self, mood: dict, trend: dict, streak: int) -> str:
        state, stress = mood["state"], mood["stress"]
        if mood["source"] == "camera" and state in self.RESET_STATES:
            pct = round((stress or 0) * 100)
            text = f"Your camera reading shows a {pct}% stress signal"
            if mood["mismatch"]:
                text += f" while you reported feeling {mood['reported']}"
            text += "."
            if streak >= 2:
                text += f" This is high stress for the {streak} entries in a row."
            elif trend["direction"] == "rising":
                text += " Your stress signal has been rising across recent entries."
            return text
        if mood["source"] == "self_report" and state in self.RESET_STATES:
            return ("No camera reading for this entry, so this is based on how "
                    f"you reported feeling ({mood['reported']}).")
        return "Your mood looks settled. Keep your routine going."

    def evaluate_reset(self, before_stress: float, after_facial: dict | None) -> dict:
        """Compare a before stress value with a fresh post-reset camera reading."""
        after_mood = self.derive_mood(after_facial)
        after_stress = after_mood["stress"]
        if after_stress is None:
            return {"outcome": "unknown", "delta_points": None,
                    "after_mood": after_mood,
                    "message": "We could not read your face after the reset, so there is nothing to compare."}

        delta = before_stress - after_stress
        points = round(delta * 100)
        if delta >= 0.05:
            outcome = "improved"
            message = f"Your stress signal is {points} points lower than before."
        elif delta <= -0.05:
            outcome = "worse"
            message = "Your stress signal is higher than before. Try another round or take a longer break."
        else:
            outcome = "no_change"
            message = "Your stress signal did not change much. Another round may help."
        return {"outcome": outcome, "delta_points": points,
                "after_mood": after_mood, "message": message}
