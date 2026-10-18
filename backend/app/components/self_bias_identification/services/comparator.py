class MultiSignalComparator:
    """Compares what the student claimed in the diary with what the sensors
    observed, and turns the gap into the features the classifier and the PAS
    score use.

    A signal that cannot be verified (no calendar access, an unknown GPS place,
    a diary entry with no duration, no usable photo) is NOT scored as a
    mismatch. It gets a neutral feature value for the model and a
    `*_checked = False` flag, so PAS leaves it out and the UI never accuses the
    student of something the system simply could not check.
    """

    # Categories where "verified educational app usage" is a meaningful
    # ground truth for the claimed time (the student would plausibly be
    # on a phone/laptop doing that work). For everything else (Play,
    # Trips, Entertainment, Meeting, Internship — offline/physical or
    # non-study activities), phone educational-app time is expected to
    # be ~0 regardless of whether the entry is truthful, so scoring the
    # duration/activity signals against it would falsely flag every
    # honest leisure entry as "productivity overestimation".
    STUDY_CATEGORIES = {"Lecture", "Self-study", "Assignment", "Group work"}

    NEGATIVE_MOODS = {"stressed", "tired", "bored"}
    POSITIVE_MOODS = {"motivated", "happy", "normal"}
    UNKNOWN_LOCATIONS = {"", "unknown"}
    FACIAL_STRESS_THRESHOLD = 0.5

    @staticmethod
    def _norm(text) -> str:
        return (text or "").strip().lower()

    def compare(self, diary_entry: dict,
                sensor_data: dict) -> dict:

        activity_category = diary_entry.get(
            "activity_category", "")
        is_study_category = activity_category in self.STUDY_CATEGORIES

        claimed_duration = diary_entry.get(
            "claimed_duration_minutes") or 0
        verified_edu = sensor_data.get(
            "verified_educational_minutes", 0) or 0

        social_media = sensor_data.get(
            "social_media_minutes", 0) or 0
        distraction = sensor_data.get(
            "distraction_duration", 0) or 0
        app_switches = sensor_data.get(
            "app_switch_count", 0) or 0
        claimed_location = diary_entry.get(
            "claimed_location") or ""
        actual_location = sensor_data.get(
            "gps_location") or ""

        mood_before = diary_entry.get(
            "mood_before") or ""
        mood_after = diary_entry.get(
            "mood_after") or ""

        # Signal 1: Duration
        # Only scored against verified educational app time for
        # study-type categories, and only when the entry actually claims a
        # duration. A leisure entry (e.g. "Play") expects ~0 minutes of
        # educational app usage, and a 0-minute claim gives nothing to compare,
        # so in both cases the signal is neutral (no gap, perfect match) and
        # left out of PAS rather than scored as a mismatch.
        duration_checked = is_study_category and claimed_duration > 0
        if duration_checked:
            duration_gap = claimed_duration - verified_edu
            duration_match_ratio = round(
                min(verified_edu / claimed_duration, 1.0), 2
            )
        else:
            duration_gap = 0
            duration_match_ratio = 1.0

        # Signal 2: Location
        # Comparable only when the student stated a place AND the device
        # resolved one. "Unknown" means location is off or no saved place is
        # near, which says nothing about whether the claim is true.
        location_checked = (
            bool(self._norm(claimed_location))
            and self._norm(actual_location) not in self.UNKNOWN_LOCATIONS
        )
        location_match = 1 if (
            not location_checked
            or self._norm(claimed_location) == self._norm(actual_location)
        ) else 0

        # Signal 3: Focus
        focus_quality_score = round(
            max(0, 1 - (app_switches / 80)), 2)

        # Signal 4: Activity
        # Same reasoning as Signal 1 — "educational app time > social
        # media time" only makes sense to check for study categories, and
        # only when the entry claims it studied at all.
        activity_checked = duration_checked
        activity_match = (
            1 if (verified_edu > social_media) else 0
        ) if activity_checked else 1

        # Signal 5: Calendar
        # calendar_match is 1 (event found), 0 (checked, no event) or -1
        # (not checked: feature off, permission denied, or error).
        raw_calendar = sensor_data.get("calendar_match")
        raw_calendar = -1 if raw_calendar is None else int(raw_calendar)
        calendar_checked = raw_calendar in (0, 1)
        calendar_match = 0 if raw_calendar == 0 else 1

        # Signal 6: Stress
        # Stress underestimation = an independent signal (the face) shows
        # stress that the student's own mood report does not. A student who
        # honestly reports feeling stressed or tired is NOT underestimating,
        # even if their mood dropped during the session.
        facial_emotion = sensor_data.get("facial_emotion") or {}
        stress_checked = facial_emotion.get("status") == "success"
        facial_stress = (
            float(facial_emotion.get("stress_indicator", 0) or 0)
            if stress_checked
            else 0.0
        )
        reported_stressed = self._norm(mood_after) in self.NEGATIVE_MOODS
        stress_mismatch = 1 if (
            stress_checked
            and facial_stress >= self.FACIAL_STRESS_THRESHOLD
            and not reported_stressed
        ) else 0

        mood_declined = (
            self._norm(mood_before) in self.POSITIVE_MOODS
            and self._norm(mood_after) in self.NEGATIVE_MOODS
        )

        features = {
            "duration_gap": duration_gap,
            "duration_match_ratio": duration_match_ratio,
            "location_match": location_match,
            "focus_quality_score": focus_quality_score,
            "activity_match": activity_match,
            "stress_mismatch": stress_mismatch,
            "app_switch_count": app_switches,
            "social_media_minutes": social_media,
            "distraction_duration": distraction,
            "calendar_match": calendar_match,
            "facial_stress": round(facial_stress, 2),
            # Not model inputs: which signals could actually be verified.
            "duration_checked": duration_checked,
            "location_checked": location_checked,
            "activity_checked": activity_checked,
            "calendar_checked": calendar_checked,
            "stress_checked": stress_checked,
        }

        comparison = {
            "activity_category": activity_category,
            "is_study_category": is_study_category,
            "claimed_duration": claimed_duration,
            "verified_educational": verified_edu,
            "duration_gap": duration_gap,
            "duration_checked": duration_checked,
            "claimed_location": claimed_location,
            "actual_location": actual_location,
            "location_match": location_match,
            "location_checked": location_checked,
            "calendar_match": calendar_match,
            "calendar_checked": calendar_checked,
            "app_switches": app_switches,
            "social_media_minutes": social_media,
            "entertainment_minutes": sensor_data.get("entertainment_minutes", 0),
            "mood_before": mood_before,
            "mood_after": mood_after,
            "mood_declined": mood_declined,
            # Per-app source breakdown, for display only (see SensorData schema)
            "educational_breakdown": sensor_data.get("educational_breakdown", {}),
            "entertainment_breakdown": sensor_data.get("entertainment_breakdown", {}),
            "social_media_breakdown": sensor_data.get("social_media_breakdown", {}),
            # Raw facial-analysis result, for display. Its stress_indicator
            # also feeds the "facial_stress" feature above and the
            # classify_with_rules rule-based cross-check.
            "facial_emotion": sensor_data.get("facial_emotion"),
        }

        return {
            "features": features,
            "comparison": comparison
        }
