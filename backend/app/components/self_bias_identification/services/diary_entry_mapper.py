import re
import time

# Translates a document from the team's shared `diaryEntries` collection
# (owned by the group leader's component — camelCase fields, different
# value formats) into the internal snake_case shape this component's
# pipeline (comparator.py / classifier.py / pas_calculator.py /
# reflection_bot.py) already expects. Those files are untouched — they
# only ever see the mapped dict, never the leader's raw schema.

_DURATION_PATTERN = re.compile(
    r"(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?", re.IGNORECASE
)


def parse_duration_to_minutes(duration_str: str) -> int:
    """"1h 30m" -> 90, "15h" -> 900, "45m" -> 45, "" -> 0.
    Falls back to treating the string as a plain number of minutes if it
    doesn't match the "Xh Ym" shape at all (defensive — the leader's
    TimeUtils.calculateDuration always produces "Xh Ym"/"Xh"/"Ym", but a
    manually-created test document might not)."""
    if not duration_str:
        return 0
    match = _DURATION_PATTERN.search(duration_str)
    if match and (match.group(1) or match.group(2)):
        hours = int(match.group(1) or 0)
        minutes = int(match.group(2) or 0)
        return hours * 60 + minutes
    digits = re.sub(r"[^\d]", "", duration_str)
    return int(digits) if digits else 0


def _combine_date_time(entry_date: str, time_str: str) -> str:
    """"2026-08-29" + "09:00" -> "2026-08-29T09:00:00.000" — matches the
    ISO-ish format this component's own form already produced, so
    comparator.py's date handling elsewhere doesn't need to branch on
    source."""
    date_part = entry_date or time.strftime("%Y-%m-%d")
    time_part = time_str or "00:00"
    return f"{date_part}T{time_part}:00.000"


def map_leader_entry(doc: dict) -> dict:
    location_type = doc.get("locationType", "") or ""
    custom_location = doc.get("customLocation", "") or ""
    claimed_location = (
        custom_location
        if location_type.lower() == "other" and custom_location
        else location_type
    )

    with_whom = doc.get("withWhom", "") or ""
    specific_person = doc.get("specificPerson", "") or ""

    entry_date = doc.get("entryDate", "")
    start_time = doc.get("startTime", "")
    end_time = doc.get("endTime", "")

    return {
        "entry_id": f"ENT_LEADER_{int(time.time() * 1000)}",
        "user_id": doc.get("userId", ""),
        "claimed_activity": doc.get("activityName", ""),
        "activity_category": doc.get("activityCategory", ""),
        "claimed_start_time": _combine_date_time(entry_date, start_time),
        "claimed_end_time": _combine_date_time(entry_date, end_time),
        "claimed_duration_minutes": parse_duration_to_minutes(
            doc.get("duration", "")
        ),
        "claimed_location": claimed_location,
        "productivity_level": doc.get("productivityLevel", ""),
        "completion_status": doc.get("taskOutcome", ""),
        "with_whom": f"{with_whom} ({specific_person})"
        if specific_person
        else with_whom,
        "mood_before": doc.get("moodBefore", ""),
        "mood_after": doc.get("moodAfter", ""),
        "health_status": doc.get("healthStatus", ""),
        "diary_text": doc.get("notes", ""),
    }
