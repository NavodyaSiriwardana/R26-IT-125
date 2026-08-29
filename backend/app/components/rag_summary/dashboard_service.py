from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from pydantic import ValidationError

from .date_utils import validate_week_range
from .firestore_store import (
    get_latest_summary_for_week,
    list_diary_entries_for_week,
    list_recent_diary_entries,
)
from .schemas import (
    DashboardBreakdownItem,
    DashboardCategoryBreakdown,
    DashboardDailyActivity,
    DashboardInsight,
    DashboardLatestSummaryPreview,
    DashboardMoodBreakdown,
    DashboardOutcomeBreakdown,
    DashboardOverview,
    DashboardResponse,
    DiaryEntryResponse,
    WeeklySummaryResponse,
)


POSITIVE_MOODS = {
    "happy",
    "motivated",
    "calm",
    "relaxed",
    "focused",
    "confident",
    "good",
    "excited",
}

NEGATIVE_MOODS = {
    "sad",
    "stressed",
    "tired",
    "bored",
    "angry",
    "anxious",
    "worried",
    "frustrated",
    "low",
}

PRODUCTIVITY_ORDER = ("High", "Medium", "Low")
OUTCOME_ORDER = ("Completed", "Partially Completed", "Postponed", "Incomplete")
TIME_BUCKET_ORDER = ("morning", "afternoon", "evening", "night")


def _normalize(value: Optional[str]) -> str:
    return " ".join(value.strip().lower().split()) if value else ""


def _display_label(value: str, fallback: str) -> str:
    normalized = _normalize(value)
    return normalized.title() if normalized else fallback


def _percentage(numerator: int | float, denominator: int | float) -> float:
    if denominator <= 0:
        return 0.0

    return round((numerator / denominator) * 100, 1)


def resolve_dashboard_week(
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
) -> tuple[str, str]:
    """Resolves and validates a complete Monday-to-Sunday dashboard week."""

    return validate_week_range(week_start, week_end)


def _parse_entries(raw_entries: List[Dict[str, Any]]) -> List[DiaryEntryResponse]:
    entries = []

    for raw_entry in raw_entries:
        try:
            entries.append(DiaryEntryResponse(**raw_entry))
        except (TypeError, ValueError):
            # A malformed legacy document should not make the entire dashboard fail.
            continue

    return entries


def _entry_sort_key(entry: DiaryEntryResponse) -> tuple[str, str, str]:
    created_at = entry.created_at.isoformat() if entry.created_at else ""
    return entry.entry_date, entry.start_time, created_at


def _mood_score(mood: str) -> int:
    normalized = _normalize(mood)

    if normalized in POSITIVE_MOODS:
        return 1

    if normalized in NEGATIVE_MOODS:
        return -1

    return 0


def _mood_direction(entry: DiaryEntryResponse) -> int:
    after_score = _mood_score(entry.mood_after)
    before_score = _mood_score(entry.mood_before)

    if after_score > before_score:
        return 1

    if after_score < before_score:
        return -1

    return 0


def _build_daily_activity(
    entries: List[DiaryEntryResponse],
    week_start: str,
) -> List[DashboardDailyActivity]:
    start_date = date.fromisoformat(week_start)
    totals_by_date = defaultdict(lambda: {"minutes": 0, "count": 0})

    for entry in entries:
        if entry.entry_date not in {
            (start_date + timedelta(days=offset)).isoformat()
            for offset in range(7)
        }:
            continue

        totals_by_date[entry.entry_date]["minutes"] += max(entry.duration_minutes, 0)
        totals_by_date[entry.entry_date]["count"] += 1

    daily_activity = []

    for offset in range(7):
        activity_date = start_date + timedelta(days=offset)
        date_key = activity_date.isoformat()
        daily_totals = totals_by_date[date_key]
        daily_activity.append(
            DashboardDailyActivity(
                date=date_key,
                day_label=activity_date.strftime("%a"),
                total_minutes=daily_totals["minutes"],
                entry_count=daily_totals["count"],
            )
        )

    return daily_activity


def _build_category_breakdown(
    entries: List[DiaryEntryResponse],
    total_minutes: int,
) -> List[DashboardCategoryBreakdown]:
    grouped = defaultdict(lambda: {"label": "Uncategorized", "minutes": 0, "count": 0})

    for entry in entries:
        key = _normalize(entry.activity_category) or "uncategorized"
        group = grouped[key]
        group["label"] = _display_label(entry.activity_category, "Uncategorized")
        group["minutes"] += max(entry.duration_minutes, 0)
        group["count"] += 1

    breakdown = [
        DashboardCategoryBreakdown(
            category=group["label"],
            total_minutes=group["minutes"],
            entry_count=group["count"],
            percentage=_percentage(group["minutes"], total_minutes),
        )
        for group in grouped.values()
    ]

    return sorted(
        breakdown,
        key=lambda item: (-item.total_minutes, -item.entry_count, item.category.lower()),
    )


def _ordered_counts(
    values: List[str],
    preferred_order: tuple[str, ...],
) -> List[tuple[str, int]]:
    counts = Counter(_normalize(value) or "unknown" for value in values)
    preferred_keys = [_normalize(label) for label in preferred_order]
    result = []

    for label, key in zip(preferred_order, preferred_keys):
        result.append((label, counts.pop(key, 0)))

    for key in sorted(counts):
        result.append((_display_label(key, "Unknown"), counts[key]))

    return result


def _build_productivity_breakdown(
    entries: List[DiaryEntryResponse],
) -> List[DashboardBreakdownItem]:
    total_entries = len(entries)

    return [
        DashboardBreakdownItem(
            label=label,
            count=count,
            percentage=_percentage(count, total_entries),
        )
        for label, count in _ordered_counts(
            [entry.productivity_level for entry in entries],
            PRODUCTIVITY_ORDER,
        )
    ]


def _build_outcome_breakdown(
    entries: List[DiaryEntryResponse],
) -> List[DashboardOutcomeBreakdown]:
    total_entries = len(entries)

    return [
        DashboardOutcomeBreakdown(
            outcome=label,
            count=count,
            percentage=_percentage(count, total_entries),
        )
        for label, count in _ordered_counts(
            [entry.task_outcome for entry in entries],
            OUTCOME_ORDER,
        )
    ]


def _build_mood_breakdown(
    entries: List[DiaryEntryResponse],
) -> DashboardMoodBreakdown:
    directions = [_mood_direction(entry) for entry in entries]
    improved_count = directions.count(1)

    return DashboardMoodBreakdown(
        improved_count=improved_count,
        stable_count=directions.count(0),
        declined_count=directions.count(-1),
        improved_percentage=_percentage(improved_count, len(entries)),
    )


def _parse_start_hour(time_value: str) -> int:
    try:
        hour_text, _ = time_value.split(":", maxsplit=1)
        return int(hour_text)
    except (AttributeError, TypeError, ValueError):
        return 0


def _time_bucket(entry: DiaryEntryResponse) -> str:
    hour = _parse_start_hour(entry.start_time)

    if 5 <= hour < 12:
        return "morning"

    if 12 <= hour < 17:
        return "afternoon"

    if 17 <= hour < 21:
        return "evening"

    return "night"


def _productivity_score(productivity_level: str) -> int:
    return {"high": 3, "medium": 2, "low": 1}.get(
        _normalize(productivity_level),
        0,
    )


def _unique_evidence_ids(entries: List[DiaryEntryResponse]) -> List[str]:
    return list(dict.fromkeys(entry.evidence_id for entry in entries if entry.evidence_id))


def _build_productivity_insight(
    entries: List[DiaryEntryResponse],
) -> Optional[DashboardInsight]:
    grouped = defaultdict(list)

    for entry in entries:
        if _productivity_score(entry.productivity_level) > 0:
            grouped[_time_bucket(entry)].append(entry)

    if not grouped:
        return None

    def ranking(bucket: str) -> tuple[float, int, int]:
        bucket_entries = grouped[bucket]
        average_score = sum(
            _productivity_score(entry.productivity_level)
            for entry in bucket_entries
        ) / len(bucket_entries)
        return average_score, len(bucket_entries), -TIME_BUCKET_ORDER.index(bucket)

    best_bucket = max(grouped, key=ranking)
    supporting_entries = grouped[best_bucket]
    sample_size = len(supporting_entries)
    activity_word = "activity" if sample_size == 1 else "activities"

    return DashboardInsight(
        title="Strongest productivity window",
        message=(
            f"Your highest average recorded productivity was during the {best_bucket}, "
            f"based on {sample_size} {activity_word}."
        ),
        evidence_ids=_unique_evidence_ids(supporting_entries),
        sample_size=sample_size,
    )


def _build_pattern_insight(
    entries: List[DiaryEntryResponse],
) -> Optional[DashboardInsight]:
    by_category = defaultdict(list)

    for entry in entries:
        key = _normalize(entry.activity_category) or "uncategorized"
        by_category[key].append(entry)

    mood_candidates = []

    for key, category_entries in by_category.items():
        improved_count = sum(
            1 for entry in category_entries if _mood_direction(entry) > 0
        )

        if improved_count == 0:
            continue

        mood_candidates.append(
            (
                improved_count / len(category_entries),
                improved_count,
                len(category_entries),
                key,
                category_entries,
            )
        )

    if mood_candidates:
        _, improved_count, sample_size, key, supporting_entries = max(
            mood_candidates,
            key=lambda item: (item[0], item[2], item[1], item[3]),
        )
        category = _display_label(key, "Uncategorized")
        improvement_rate = _percentage(improved_count, sample_size)

        return DashboardInsight(
            title="Mood-supporting activity",
            message=(
                f"{category} was associated with mood improvement in {improved_count} of "
                f"{sample_size} recorded activities ({improvement_rate:.0f}%)."
            ),
            evidence_ids=_unique_evidence_ids(supporting_entries),
            sample_size=sample_size,
        )

    unfinished_entries = [
        entry
        for entry in entries
        if _normalize(entry.task_outcome) not in {"completed", "done", "finished", "success"}
    ]

    if unfinished_entries:
        return DashboardInsight(
            title="Unfinished activity load",
            message=(
                f"{len(unfinished_entries)} of {len(entries)} recorded activities were not marked "
                "completed. Consider choosing one unfinished activity and reducing it to a smaller step."
            ),
            evidence_ids=_unique_evidence_ids(entries),
            sample_size=len(entries),
        )

    if entries:
        return DashboardInsight(
            title="Completion consistency",
            message=f"All {len(entries)} recorded activities were marked completed this week.",
            evidence_ids=_unique_evidence_ids(entries),
            sample_size=len(entries),
        )

    return None


def _build_insights(entries: List[DiaryEntryResponse]) -> List[DashboardInsight]:
    insights = [
        _build_productivity_insight(entries),
        _build_pattern_insight(entries),
    ]
    return [insight for insight in insights if insight is not None]


def _as_iso_string(value: Any) -> str:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.isoformat()

    if isinstance(value, str):
        try:
            parsed_value = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value

        if parsed_value.tzinfo is None:
            parsed_value = parsed_value.replace(tzinfo=timezone.utc)
        return parsed_value.isoformat()

    return str(value) if value is not None else ""


def _is_entailed_claim(claim: Any) -> bool:
    return (
        isinstance(claim, dict)
        and _normalize(str(claim.get("classification") or "")) == "entailed"
    )


def _summary_points_to_text(condition: Any) -> str:
    """Build the dashboard preview from supported RAG claims only."""

    if not isinstance(condition, dict):
        return ""
    points = condition.get("summary_points")
    evaluation = condition.get("evaluation")
    if not isinstance(points, list) or not isinstance(evaluation, dict):
        return ""

    claims = evaluation.get("per_claim") or evaluation.get("claim_details")
    if not isinstance(claims, list):
        return ""

    claims_by_id: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for claim in claims:
        if not isinstance(claim, dict):
            continue
        claim_id = str(claim.get("claim_id") or "").strip()
        if claim_id:
            claims_by_id[claim_id].append(claim)

    supported_text = []
    safe_index_fallback = len(claims) == len(points)
    for index, point in enumerate(points):
        if not isinstance(point, dict):
            continue
        claim_id = str(point.get("claim_id") or "").strip()
        matching_claims = claims_by_id.get(claim_id) if claim_id else None
        supported_by_id = bool(matching_claims) and all(
            _is_entailed_claim(claim) for claim in matching_claims or []
        )
        supported_by_index = (
            safe_index_fallback
            and index < len(claims)
            and _is_entailed_claim(claims[index])
        )
        if not supported_by_id and not (
            matching_claims is None and supported_by_index
        ):
            continue
        text = str(point.get("text") or "").strip()
        if text:
            supported_text.append(text)

    return " ".join(supported_text).strip()


def _optional_number(value: Any) -> Optional[float]:
    if isinstance(value, dict):
        value = value.get("value")

    if value is None:
        return None

    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return None

    return parsed


def _optional_metric(value: Any) -> Optional[float]:
    parsed = _optional_number(value)
    return max(0.0, min(1.0, parsed)) if parsed is not None else None


def _build_latest_summary_preview(
    summary: Optional[Dict[str, Any]],
) -> Optional[DashboardLatestSummaryPreview]:
    if not summary:
        return None

    additional_data = summary.get("additional_data", {})
    feedback = summary.get("feedback") or additional_data.get("feedback", {})
    rag_condition = additional_data.get("rag")
    if isinstance(rag_condition, dict) and any(
        key in rag_condition
        for key in ("status", "summary_points", "generation", "evaluation")
    ):
        condition = rag_condition
    else:
        # Backward compatibility for schema-v2 saved summaries where ``rag``
        # could contain only a legacy score and the displayed output was stored
        # under ``verified_rag``.
        condition = additional_data.get("verified_rag", {})
    evaluation = condition.get("evaluation", {}) if isinstance(condition, dict) else {}
    citation_metrics = evaluation.get("citation_metrics", {})
    reference_metrics = condition.get("metrics", {}) if isinstance(condition, dict) else {}
    retrieval = condition.get("retrieval", additional_data.get("retrieval", {}))
    generation = condition.get("generation", {}) if isinstance(condition, dict) else {}

    grounded_claim_rate = _optional_metric(
        evaluation.get("grounded_claim_rate", condition.get("grounded_claim_rate"))
    )
    unsupported_claim_rate = _optional_metric(
        evaluation.get("unsupported_claim_rate", condition.get("unsupported_claim_rate"))
    )
    citation_precision = _optional_metric(
        citation_metrics.get("citation_precision", evaluation.get("citation_precision"))
    )
    citation_completeness = _optional_metric(
        citation_metrics.get("citation_completeness", evaluation.get("citation_completeness"))
    )
    retrieval_coverage = _optional_metric(
        retrieval.get("retrieval_coverage") if isinstance(retrieval, dict) else None
    )

    # Read an old stored value only for legacy display compatibility. New
    # summaries never write or derive Evidence Accuracy.
    legacy_rag = additional_data.get("rag", {})
    evidence_accuracy = _optional_metric(legacy_rag.get("evidence_accuracy_normalized"))

    return DashboardLatestSummaryPreview(
        summary_id=str(summary.get("summary_id") or summary.get("saved_summary_id") or ""),
        generated_at=_as_iso_string(summary.get("generated_at")),
        summary_text=_summary_points_to_text(condition),
        feedback_message=str(feedback.get("message", "")) if isinstance(feedback, dict) else "",
        grounded_claim_rate=grounded_claim_rate,
        unsupported_claim_rate=unsupported_claim_rate,
        citation_precision=citation_precision,
        citation_completeness=citation_completeness,
        retrieval_coverage=retrieval_coverage,
        bertscore=_optional_metric(reference_metrics.get("bertscore")),
        rouge_l=_optional_metric(reference_metrics.get("rouge_l")),
        generation_latency_ms=_optional_number(
            condition.get("generation_latency_ms", generation.get("latency_ms"))
        ),
        evaluation_status=str(evaluation.get("status") or condition.get("status") or "unavailable"),
        evidence_accuracy=evidence_accuracy,
    )


def get_latest_weekly_summary(
    user_id: str,
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
) -> Optional[WeeklySummaryResponse]:
    user_id = user_id.strip()
    if not user_id:
        raise ValueError("user_id cannot be empty.")

    resolved_start, resolved_end = resolve_dashboard_week(week_start, week_end)
    raw_summary = get_latest_summary_for_week(
        user_id=user_id,
        week_start=resolved_start,
        week_end=resolved_end,
    )

    if raw_summary is None:
        return None

    normalized_summary = dict(raw_summary)
    normalized_summary.setdefault(
        "saved_summary_id",
        normalized_summary.get("summary_id", ""),
    )
    try:
        return WeeklySummaryResponse(**normalized_summary)
    except ValidationError as error:
        raise RuntimeError("The latest saved summary has invalid data.") from error


def build_weekly_dashboard(
    user_id: str,
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
    recent_entry_limit: int = 5,
) -> DashboardResponse:
    user_id = user_id.strip()
    if not user_id:
        raise ValueError("user_id cannot be empty.")

    resolved_start, resolved_end = resolve_dashboard_week(week_start, week_end)
    raw_week_entries = list_diary_entries_for_week(
        user_id=user_id,
        week_start=resolved_start,
        week_end=resolved_end,
        limit=500,
    )
    entries = sorted(_parse_entries(raw_week_entries), key=_entry_sort_key)

    raw_recent_entries = list_recent_diary_entries(
        user_id=user_id,
        limit=max(1, min(recent_entry_limit, 10)),
    )
    recent_entries = _parse_entries(raw_recent_entries)

    total_entries = len(entries)
    total_minutes = sum(max(entry.duration_minutes, 0) for entry in entries)
    completed_count = sum(
        1
        for entry in entries
        if _normalize(entry.task_outcome) in {"completed", "done", "finished", "success"}
    )
    mood_improved_count = sum(1 for entry in entries if _mood_direction(entry) > 0)

    latest_summary_data = get_latest_summary_for_week(
        user_id=user_id,
        week_start=resolved_start,
        week_end=resolved_end,
    )

    return DashboardResponse(
        user_id=user_id,
        week_start=resolved_start,
        week_end=resolved_end,
        evidence_entry_count=total_entries,
        overview=DashboardOverview(
            activity_count=total_entries,
            logged_minutes=total_minutes,
            completion_rate=_percentage(completed_count, total_entries),
            mood_improved_rate=_percentage(mood_improved_count, total_entries),
        ),
        daily_activity=_build_daily_activity(entries, resolved_start),
        category_breakdown=_build_category_breakdown(entries, total_minutes),
        productivity_breakdown=_build_productivity_breakdown(entries),
        mood_breakdown=_build_mood_breakdown(entries),
        outcome_breakdown=_build_outcome_breakdown(entries),
        insights=_build_insights(entries),
        recent_entries=recent_entries,
        latest_summary=_build_latest_summary_preview(latest_summary_data),
    )
