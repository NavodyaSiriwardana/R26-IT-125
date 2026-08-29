class MultiSignalComparator:

    def compare(self, diary_entry: dict,
                sensor_data: dict) -> dict:

        claimed_duration = diary_entry.get(
            "claimed_duration_minutes", 0)
        verified_edu = sensor_data.get(
            "verified_educational_minutes", 0)
        
        social_media = sensor_data.get(
            "social_media_minutes", 0)
        distraction = sensor_data.get(
            "distraction_duration", 0)
        app_switches = sensor_data.get(
            "app_switch_count", 0)
        claimed_location = diary_entry.get(
            "claimed_location", "")
        actual_location = sensor_data.get(
            "gps_location", "")
        has_calendar = sensor_data.get(
            "calendar_match", 0)

        # Fix 1: mood_before + mood_after
        mood_before = diary_entry.get(
            "mood_before", "")
        mood_after = diary_entry.get(
            "mood_after", "")

        # Signal 1: Duration
        duration_gap = claimed_duration - verified_edu
        duration_match_ratio = round(
            min(verified_edu / claimed_duration, 1.0), 2
        ) if claimed_duration > 0 else 0

        # Signal 2: Location
        location_match = 1 if (
            claimed_location.lower() ==
            actual_location.lower()
        ) else 0

        # Signal 3: Focus
        focus_quality_score = round(
            max(0, 1 - (app_switches / 80)), 2)

        # Signal 4: Activity
        activity_match = 1 if (
            verified_edu > social_media) else 0

        # Fix 2: Stress mismatch
        positive_moods = [
            "motivated", "happy", "normal"]
        negative_moods = [
            "stressed", "tired", "bored"]

        self_reported_mismatch = (
            mood_before.lower() in positive_moods and
            mood_after.lower() in negative_moods
        )

        # Signal 7: Facial stress (from the Vision Transformer emotion
        # model) — an independent check for stress the self-report
        # missed, since a student underestimating their own stress will
        # naturally also under-report it in mood_before/mood_after.
        facial_emotion = sensor_data.get("facial_emotion") or {}
        facial_stress = (
            facial_emotion.get("stress_indicator", 0)
            if facial_emotion.get("status") == "success"
            else 0
        )

        stress_mismatch = 1 if (
            self_reported_mismatch or facial_stress >= 0.5
        ) else 0

        # Signal 6: Calendar
        calendar_match = int(has_calendar)

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
        }

        comparison = {
            "claimed_duration": claimed_duration,
            "verified_educational": verified_edu,
            "duration_gap": duration_gap,
            "claimed_location": claimed_location,
            "actual_location": actual_location,
            "location_match": location_match,
            "app_switches": app_switches,
            "social_media_minutes": social_media,
            "entertainment_minutes": sensor_data.get("entertainment_minutes", 0),
            "mood_before": mood_before,
            "mood_after": mood_after,
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