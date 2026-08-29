from datetime import datetime, timezone
from typing import Dict, Iterable, List, Optional

from .schemas import DiaryEntryCreate, DiaryEntryResponse
from .date_utils import get_today_iso, parse_duration_minutes, validate_iso_date
from .firestore_store import (
    save_diary_entry,
    list_diary_entries,
    get_diary_entry_by_evidence_id,
    get_diary_entries_by_evidence_ids,
)
from .chroma_store import index_diary_entry


def _model_to_dict(model):
    if hasattr(model, "model_dump"):
        return model.model_dump()

    return model.dict()


def _parse_time_to_minutes(time_value: str) -> int:
    try:
        hour, minute = time_value.split(":")
        return int(hour) * 60 + int(minute)
    except ValueError:
        raise ValueError("Time must be in HH:MM format.")


def _calculate_duration_minutes(start_time: str, end_time: str) -> int:
    start_minutes = _parse_time_to_minutes(start_time)
    end_minutes = _parse_time_to_minutes(end_time)

    duration = end_minutes - start_minutes

    if duration < 0:
        duration += 24 * 60

    return duration


def _format_duration(minutes: int) -> str:
    hours, remainder = divmod(minutes, 60)
    if hours and remainder:
        return f"{hours}h {remainder}m"
    if hours:
        return f"{hours}h"
    return f"{remainder}m"


def _derive_time_period(start_time: str) -> str:
    hour = _parse_time_to_minutes(start_time) // 60
    if 5 <= hour < 12:
        return "Morning"
    if 12 <= hour < 17:
        return "Afternoon"
    if 17 <= hour < 21:
        return "Evening"
    return "Night"


def create_user_diary_entry(entry_data: DiaryEntryCreate) -> DiaryEntryResponse:
    """
    Saves diary entry to Firestore and indexes it in ChromaDB.
    """

    raw_data = _model_to_dict(entry_data)

    user_id = raw_data["user_id"]

    entry_date = raw_data.get("entry_date") or get_today_iso()
    entry_date = validate_iso_date(entry_date)

    duration = (raw_data.get("duration") or "").strip()
    if duration:
        parse_duration_minutes(duration)
    else:
        duration = _format_duration(
            _calculate_duration_minutes(
                raw_data["start_time"],
                raw_data["end_time"],
            )
        )

    with_whom = raw_data["with_whom"]
    specific_person = (raw_data.get("specific_person") or "").strip()
    if with_whom.strip().casefold() == "alone":
        specific_person = ""

    saved_data = {
        "activityCategory": raw_data["activity_category"],
        "activityName": raw_data["activity_name"],
        "createdAt": datetime.now(timezone.utc),
        "customLocation": (raw_data.get("custom_location") or "").strip(),
        "duration": duration,
        "endTime": raw_data["end_time"],
        "entryDate": entry_date,
        "healthStatus": raw_data["health_status"],
        "locationType": raw_data["location_type"],
        "moodAfter": raw_data["mood_after"],
        "moodBefore": raw_data["mood_before"],
        "notes": raw_data.get("notes") or "",
        "productivityLevel": raw_data["productivity_level"],
        "specificPerson": specific_person,
        "startTime": raw_data["start_time"],
        "taskOutcome": raw_data["task_outcome"],
        "timePeriod": (raw_data.get("time_period") or "").strip()
        or _derive_time_period(raw_data["start_time"]),
        "userId": user_id,
        "withWhom": with_whom,
    }

    saved_entry = save_diary_entry(
        user_id=user_id,
        entry_data=saved_data,
    )

    response = DiaryEntryResponse(**saved_entry)

    index_diary_entry(response)

    return response


def list_user_diary_entries(
    user_id: str,
    limit: int = 50,
) -> List[DiaryEntryResponse]:
    entries = list_diary_entries(
        user_id=user_id,
        limit=limit,
    )

    return [DiaryEntryResponse(**entry) for entry in entries]


def get_user_evidence_entry(
    user_id: str,
    evidence_id: str,
) -> DiaryEntryResponse | None:
    entry = get_diary_entry_by_evidence_id(
        user_id=user_id,
        evidence_id=evidence_id,
    )

    if entry is None:
        return None

    return DiaryEntryResponse(**entry)


def get_user_evidence_entries(
    user_id: str,
    evidence_ids: Iterable[str],
    *,
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
) -> List[DiaryEntryResponse]:
    """Resolve canonical evidence records with explicit user/week scope."""

    entries = get_diary_entries_by_evidence_ids(
        user_id=user_id,
        evidence_ids=evidence_ids,
        week_start=week_start,
        week_end=week_end,
    )
    return [DiaryEntryResponse(**entry) for entry in entries]


def resolve_user_week_evidence_entries(
    user_id: str,
    evidence_ids: Iterable[str],
    *,
    week_start: str,
    week_end: str,
) -> Dict[str, DiaryEntryResponse]:
    """Return an Evidence-ID map suitable for citation validation/evaluation."""

    entries = get_user_evidence_entries(
        user_id=user_id,
        evidence_ids=evidence_ids,
        week_start=week_start,
        week_end=week_end,
    )
    return {entry.evidence_id: entry for entry in entries}
