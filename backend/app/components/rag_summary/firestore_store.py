from datetime import datetime, timezone
from typing import Dict, Any, Iterable, List, Optional
from google.cloud.firestore_v1 import FieldFilter

from app.firebase.firebase_client import get_firestore_client
from .date_utils import (
    get_week_bounds,
    parse_duration_minutes,
    validate_iso_date,
    validate_week_range,
)


USERS_COLLECTION = "users"
DIARY_ENTRIES_COLLECTION = "diaryEntries"
SUMMARIES_COLLECTION = "summaries"

FINAL_DIARY_FIELDS = (
    "activityCategory",
    "activityName",
    "createdAt",
    "customLocation",
    "duration",
    "endTime",
    "entryDate",
    "healthStatus",
    "locationType",
    "moodAfter",
    "moodBefore",
    "notes",
    "productivityLevel",
    "specificPerson",
    "startTime",
    "taskOutcome",
    "timePeriod",
    "userId",
    "withWhom",
)


def _string_value(value: Any) -> str:
    return value if isinstance(value, str) else "" if value is None else str(value)


def _firestore_datetime(value: Any) -> Optional[datetime]:
    """Normalize a Firestore Timestamp/datetime without assuming an ISO string."""

    if isinstance(value, datetime):
        return value

    for method_name in ("to_datetime", "ToDatetime"):
        converter = getattr(value, method_name, None)
        if callable(converter):
            converted = converter()
            if isinstance(converted, datetime):
                return converted

    # String support is retained only for API-created values already in memory;
    # final Firestore documents are expected to provide Timestamp values.
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None

    return None


def _resolved_location(location_type: str, custom_location: str) -> str:
    if location_type.strip().casefold() == "other" and custom_location.strip():
        return custom_location.strip()
    return location_type.strip()


def _firestore_diary_to_domain(
    document_id: str,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    """Map one fixed-schema Firestore document into the stable API/domain shape."""

    entry_date = validate_iso_date(_string_value(data.get("entryDate")))
    week_start, week_end = get_week_bounds(entry_date)
    duration = _string_value(data.get("duration"))
    try:
        duration_minutes = parse_duration_minutes(duration)
    except ValueError:
        # A malformed value must not make every other entry/dashboard row
        # unreadable. The original value remains exposed for diagnosis.
        duration_minutes = 0

    location_type = _string_value(data.get("locationType"))
    custom_location = _string_value(data.get("customLocation"))
    specific_person = _string_value(data.get("specificPerson"))

    return {
        "id": document_id,
        "user_id": _string_value(data.get("userId")),
        "evidence_id": document_id,
        "activity_name": _string_value(data.get("activityName")),
        "activity_category": _string_value(data.get("activityCategory")),
        "start_time": _string_value(data.get("startTime")),
        "end_time": _string_value(data.get("endTime")),
        "duration": duration,
        "duration_minutes": duration_minutes,
        "time_period": _string_value(data.get("timePeriod")),
        "productivity_level": _string_value(data.get("productivityLevel")),
        "mood_before": _string_value(data.get("moodBefore")),
        "mood_after": _string_value(data.get("moodAfter")),
        "task_outcome": _string_value(data.get("taskOutcome")),
        "specific_person": specific_person,
        "person_names": specific_person or None,
        "health_status": _string_value(data.get("healthStatus")),
        "location_type": location_type,
        "custom_location": custom_location,
        "location": _resolved_location(location_type, custom_location),
        "with_whom": _string_value(data.get("withWhom")),
        "notes": _string_value(data.get("notes")) or None,
        "entry_date": entry_date,
        "week_start": week_start,
        "week_end": week_end,
        "created_at": _firestore_datetime(data.get("createdAt")),
        "updated_at": None,
    }


def _snapshot_to_diary_entry(snapshot: Any) -> Dict[str, Any]:
    data = snapshot.to_dict() or {}
    return _firestore_diary_to_domain(str(snapshot.id), data)


def _user_diary_snapshots(db: Any, user_id: str):
    return (
        db.collection(DIARY_ENTRIES_COLLECTION)
        .where(filter=FieldFilter("userId", "==", user_id))
        .stream()
    )


def _entry_sort_key(entry: Dict[str, Any]) -> tuple[str, str, float, str]:
    return (
        entry.get("entry_date", ""),
        entry.get("start_time", ""),
        _datetime_sort_key(entry.get("created_at")),
        str(entry.get("evidence_id", "")),
    )


def save_user_profile(
    user_id: str,
    profile_data: Dict[str, Any],
) -> Dict[str, Any]:
    db = get_firestore_client()

    user_ref = db.collection(USERS_COLLECTION).document(user_id)

    user_ref.set(
        {
            **profile_data,
            "user_id": user_id,
        },
        merge=True,
    )

    return {
        **profile_data,
        "user_id": user_id,
    }


def count_user_diary_entries(user_id: str) -> int:
    db = get_firestore_client()
    return sum(1 for _ in _user_diary_snapshots(db, user_id))


def save_diary_entry(
    user_id: str,
    entry_data: Dict[str, Any],
) -> Dict[str, Any]:
    """Save one exact final-schema diary document with a Firestore-generated ID."""

    db = get_firestore_client()
    data = {
        field: entry_data.get(field)
        for field in FINAL_DIARY_FIELDS
    }
    data["userId"] = user_id
    data["createdAt"] = _firestore_datetime(data.get("createdAt")) or datetime.now(
        timezone.utc
    )
    for field in FINAL_DIARY_FIELDS:
        if field != "createdAt":
            data[field] = _string_value(data.get(field))

    document_ref = db.collection(DIARY_ENTRIES_COLLECTION).document()
    document_ref.set(data)
    return _firestore_diary_to_domain(document_ref.id, data)


def list_diary_entries(
    user_id: str,
    limit: int = 50,
) -> List[Dict[str, Any]]:
    if limit <= 0:
        raise ValueError("limit must be greater than zero.")

    db = get_firestore_client()
    entries = [
        _snapshot_to_diary_entry(doc)
        for doc in _user_diary_snapshots(db, user_id)
    ]
    entries.sort(key=_entry_sort_key)
    return entries[:limit]


def list_recent_diary_entries(
    user_id: str,
    limit: int = 5,
) -> List[Dict[str, Any]]:
    """Returns the user's newest diary entries without constraining the week."""

    if limit <= 0:
        raise ValueError("limit must be greater than zero.")

    db = get_firestore_client()
    entries = [
        _snapshot_to_diary_entry(doc)
        for doc in _user_diary_snapshots(db, user_id)
    ]
    entries.sort(key=_entry_sort_key, reverse=True)
    return entries[:limit]

def list_diary_entries_for_week(
    user_id: str,
    week_start: str,
    week_end: str,
    limit: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Return canonical entries for a complete week without an implicit cap."""

    resolved_start, resolved_end = validate_week_range(week_start, week_end)

    if limit is not None and limit <= 0:
        raise ValueError("limit must be greater than zero when provided.")

    db = get_firestore_client()

    entries = []
    for doc in _user_diary_snapshots(db, user_id):
        entry = _snapshot_to_diary_entry(doc)
        if resolved_start <= entry["entry_date"] <= resolved_end:
            entries.append(entry)
    entries.sort(key=_entry_sort_key)

    if limit is None:
        return entries

    return entries[:limit]


def list_diary_entries_before_date(
    user_id: str,
    before_date: str,
    limit: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Return canonical entries for this user that predate ``before_date``.

    Filtering is deliberately performed after the indexed userId query. This
    avoids a project-specific composite-index requirement.
    """

    resolved_before = validate_iso_date(before_date)
    if limit is not None and limit <= 0:
        raise ValueError("limit must be greater than zero when provided.")

    db = get_firestore_client()
    docs = _user_diary_snapshots(db, user_id)
    entries = []
    for doc in docs:
        entry = _snapshot_to_diary_entry(doc)
        if entry["entry_date"] < resolved_before:
            entries.append(entry)
    entries.sort(key=_entry_sort_key, reverse=True)
    return entries if limit is None else entries[:limit]

def get_diary_entry_by_evidence_id(
    user_id: str,
    evidence_id: str,
) -> Optional[Dict[str, Any]]:
    db = get_firestore_client()

    doc = (
        db.collection(DIARY_ENTRIES_COLLECTION)
        .document(evidence_id)
        .get()
    )

    if not doc.exists:
        return None

    entry = _snapshot_to_diary_entry(doc)
    if entry["user_id"] != user_id:
        return None
    return entry


def get_diary_entries_by_evidence_ids(
    user_id: str,
    evidence_ids: Iterable[str],
    *,
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Resolve Evidence IDs from canonical Firestore documents.

    Resolution is always scoped by the final document's userId. When a week is
    supplied, derived boundaries from entryDate must match. Unknown, mismatched,
    and duplicate IDs are omitted rather than remapped.
    """

    resolved_week = None
    if week_start is not None or week_end is not None:
        resolved_week = validate_week_range(week_start, week_end)

    requested_ids = list(
        dict.fromkeys(
            evidence_id
            for evidence_id in evidence_ids
            if isinstance(evidence_id, str) and evidence_id
        )
    )
    if not requested_ids:
        return []

    db = get_firestore_client()
    entries_collection = db.collection(DIARY_ENTRIES_COLLECTION)
    document_refs = [
        entries_collection.document(evidence_id)
        for evidence_id in requested_ids
    ]
    requested_id_set = set(requested_ids)
    entries_by_id = {}

    for doc in db.get_all(document_refs):
        if not doc.exists:
            continue

        evidence_id = str(doc.id)
        if evidence_id not in requested_id_set:
            continue

        entry = _snapshot_to_diary_entry(doc)
        if entry["user_id"] != user_id:
            continue

        if resolved_week is not None:
            resolved_start, resolved_end = resolved_week
            if entry["week_start"] != resolved_start:
                continue
            if entry["week_end"] != resolved_end:
                continue

        entries_by_id[evidence_id] = entry

    return [
        entries_by_id[evidence_id]
        for evidence_id in requested_ids
        if evidence_id in entries_by_id
    ]


def save_summary(
    user_id: str,
    summary_id: str,
    summary_data: Dict[str, Any],
) -> Dict[str, Any]:
    db = get_firestore_client()

    data = {
        **summary_data,
        "user_id": user_id,
        "summary_id": summary_id,
    }

    (
        db.collection(USERS_COLLECTION)
        .document(user_id)
        .collection(SUMMARIES_COLLECTION)
        .document(summary_id)
        .set(data)
    )

    return data


def _datetime_sort_key(value: Any) -> float:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.timestamp()

    if isinstance(value, str):
        try:
            parsed_value = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed_value.tzinfo is None:
                parsed_value = parsed_value.replace(tzinfo=timezone.utc)
            return parsed_value.timestamp()
        except ValueError:
            return 0.0

    return 0.0


def _generated_at_sort_key(summary: Dict[str, Any]) -> float:
    return _datetime_sort_key(summary.get("generated_at"))


def get_latest_summary_for_week(
    user_id: str,
    week_start: str,
    week_end: str,
) -> Optional[Dict[str, Any]]:
    """
    Returns the newest already-generated summary for a week.

    Filtering and ordering are deliberately performed in Python. The demo has a
    small summary collection, and this avoids requiring an additional Firestore
    composite index merely to load the dashboard.
    """

    db = get_firestore_client()

    docs = (
        db.collection(USERS_COLLECTION)
        .document(user_id)
        .collection(SUMMARIES_COLLECTION)
        .stream()
    )

    matching_summaries = []

    for doc in docs:
        summary = doc.to_dict() or {}

        if summary.get("week_start") != week_start:
            continue

        if summary.get("week_end") != week_end:
            continue

        summary.setdefault("summary_id", doc.id)
        matching_summaries.append(summary)

    if not matching_summaries:
        return None

    return max(matching_summaries, key=_generated_at_sort_key)
