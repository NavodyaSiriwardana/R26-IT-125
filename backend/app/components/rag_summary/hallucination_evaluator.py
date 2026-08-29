"""Citation-validity and claim-groundedness evaluation.

This module deliberately has no lexical-overlap fallback for claim support.
Plain claims use overlap only to select a bounded NLI premise. Claim support is
still an NLI result, and a model/runtime failure therefore makes all NLI-derived
aggregate metrics unavailable instead of manufacturing a score.
"""

from __future__ import annotations

import math
import os
import re
import threading
from collections.abc import Callable, Mapping, Sequence
from datetime import date
from typing import Any, Dict, List, Optional, Tuple

from .date_utils import validate_week_range
from .schemas import DiaryEntryResponse


DEFAULT_NLI_MODEL = "cross-encoder/nli-deberta-v3-base"
DEFAULT_ENTAILMENT_THRESHOLD = 0.70
NLI_MODEL_ENV = "NLI_MODEL_NAME"
NLI_MODEL_REVISION_ENV = "NLI_MODEL_REVISION"
NLI_THRESHOLD_ENV = "NLI_ENTAILMENT_THRESHOLD"

_nli_pipeline: Any = None
_nli_pipeline_key: Optional[Tuple[str, Optional[str]]] = None
_nli_pipeline_lock = threading.Lock()

_SENTENCE_BOUNDARY_RE = re.compile(r"(?<=[.!?])\s+")
_BRACKETED_REFERENCE_RE = re.compile(r"\[\s*([^\[\]]+?)\s*\]")
_CITATION_PREFIX_RE = re.compile(r"^EVIDENCE(?:_ID)?\s*:\s*", re.IGNORECASE)
_LEXICAL_TOKEN_RE = re.compile(r"[a-z0-9]+")
_CLAIM_SEGMENT_RE = re.compile(
    r"\s*(?:[,;]|\band\b|\bthen\b|\bwhile\b|\bbut\b|\bplus\b)\s*",
    re.IGNORECASE,
)

# Plain summaries have no citations, so their NLI evidence must be selected from
# the canonical week. Keeping this premise small avoids the tokenizer silently
# dropping later records. Four entries still allow one compound sentence to
# name several distinct activities.
_PLAIN_EVIDENCE_SELECTION_METHOD = "deterministic_lexical_clause_coverage"
_PLAIN_MAX_EVIDENCE_ENTRIES = 4
_PLAIN_PREMISE_MAX_CHARS = 1800
_PLAIN_STOPWORDS = frozenset(
    {
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "activities",
        "activity",
        "be",
        "been",
        "by",
        "diary",
        "did",
        "do",
        "during",
        "for",
        "from",
        "had",
        "has",
        "have",
        "i",
        "in",
        "include",
        "included",
        "includes",
        "is",
        "it",
        "me",
        "my",
        "of",
        "on",
        "s",
        "that",
        "the",
        "their",
        "this",
        "to",
        "was",
        "week",
        "weekly",
        "were",
        "with",
    }
)


def split_into_claims(summary_text: str) -> List[str]:
    """Split non-empty summary text into sentence-like factual claims."""

    if not summary_text or not summary_text.strip():
        return []
    cleaned = re.sub(r"\s+", " ", summary_text).strip()
    return [part.strip() for part in _SENTENCE_BOUNDARY_RE.split(cleaned) if part.strip()]


def reset_nli_model_cache() -> None:
    """Clear the lazy NLI model cache (primarily useful for tests/config reloads)."""

    global _nli_pipeline, _nli_pipeline_key
    with _nli_pipeline_lock:
        _nli_pipeline = None
        _nli_pipeline_key = None


def _get_nli_pipeline(model_name: str, model_revision: Optional[str] = None) -> Any:
    """Lazy-load and cache one Hugging Face sequence-classification pipeline."""

    global _nli_pipeline, _nli_pipeline_key
    cache_key = (model_name, model_revision)
    if _nli_pipeline is not None and _nli_pipeline_key == cache_key:
        return _nli_pipeline
    with _nli_pipeline_lock:
        if _nli_pipeline is not None and _nli_pipeline_key == cache_key:
            return _nli_pipeline
        from transformers import pipeline

        model_kwargs: Dict[str, Any] = {
            "task": "text-classification",
            "model": model_name,
            "tokenizer": model_name,
            "top_k": None,
        }
        if model_revision:
            model_kwargs["revision"] = model_revision
        _nli_pipeline = pipeline(**model_kwargs)
        _nli_pipeline_key = cache_key
        return _nli_pipeline


def _resolve_model_name(model_name: Optional[str]) -> str:
    configured = model_name if model_name is not None else os.getenv(NLI_MODEL_ENV)
    return (configured or DEFAULT_NLI_MODEL).strip()


def _resolve_model_revision(model_revision: Optional[str]) -> Optional[str]:
    configured = (
        model_revision if model_revision is not None else os.getenv(NLI_MODEL_REVISION_ENV)
    )
    return configured.strip() if configured else None


def _resolve_threshold(threshold: Optional[float]) -> float:
    configured: Any = threshold
    if configured is None:
        configured = os.getenv(NLI_THRESHOLD_ENV, str(DEFAULT_ENTAILMENT_THRESHOLD))
    try:
        value = float(configured)
    except (TypeError, ValueError) as error:
        raise ValueError("The NLI entailment threshold must be numeric.") from error
    if not math.isfinite(value) or not 0.0 <= value <= 1.0:
        raise ValueError("The NLI entailment threshold must be between 0 and 1.")
    return value


def _coerce_entry(raw_entry: Any) -> Optional[DiaryEntryResponse]:
    if isinstance(raw_entry, DiaryEntryResponse):
        return raw_entry
    if not isinstance(raw_entry, Mapping):
        return None
    try:
        if hasattr(DiaryEntryResponse, "model_validate"):
            return DiaryEntryResponse.model_validate(dict(raw_entry))
        return DiaryEntryResponse.parse_obj(dict(raw_entry))
    except Exception:
        return None


def _coerce_entries(
    source_entries: Optional[Sequence[Any]],
) -> Tuple[List[DiaryEntryResponse], List[Any]]:
    canonical: List[DiaryEntryResponse] = []
    rejected: List[Any] = []
    for raw_entry in source_entries or []:
        entry = _coerce_entry(raw_entry)
        if entry is None:
            rejected.append(raw_entry)
        else:
            canonical.append(entry)
    return canonical, rejected


def _entry_matches_week(entry: DiaryEntryResponse, week_start: str, week_end: str) -> bool:
    if entry.week_start != week_start or entry.week_end != week_end:
        return False
    try:
        resolved_start, resolved_end = validate_week_range(week_start, week_end)
        entry_day = date.fromisoformat(entry.entry_date)
        start_day = date.fromisoformat(resolved_start)
        end_day = date.fromisoformat(resolved_end)
    except ValueError:
        return False
    return start_day <= entry_day <= end_day


def _resolve_scope(
    entries: Sequence[DiaryEntryResponse],
    user_id: Optional[str],
    week_start: Optional[str],
    week_end: Optional[str],
) -> Tuple[Optional[str], Optional[str], Optional[str], Optional[str]]:
    """Resolve omitted scope only when canonical records make it unambiguous."""

    if bool(week_start) != bool(week_end):
        return None, None, None, "week_start and week_end must be supplied together."
    resolved_user = user_id
    if resolved_user is None:
        candidate_users = {
            entry.user_id
            for entry in entries
            if not week_start
            or (entry.week_start == week_start and entry.week_end == week_end)
        }
        if len(candidate_users) != 1:
            return None, None, None, (
                "user_id is required when canonical entries do not identify one user."
            )
        resolved_user = next(iter(candidate_users))
    resolved_start = week_start
    resolved_end = week_end
    if resolved_start is None:
        candidate_weeks = {
            (entry.week_start, entry.week_end)
            for entry in entries
            if entry.user_id == resolved_user
        }
        if len(candidate_weeks) != 1:
            return None, None, None, (
                "week_start and week_end are required when canonical entries do not "
                "identify one week."
            )
        resolved_start, resolved_end = next(iter(candidate_weeks))
    try:
        resolved_start, resolved_end = validate_week_range(
            resolved_start,
            resolved_end,
        )
    except (TypeError, ValueError) as error:
        return None, None, None, str(error)
    return resolved_user, resolved_start, resolved_end, None


def _entry_to_evidence_text(entry: DiaryEntryResponse) -> str:
    """Serialize a canonical record without adding inferred facts."""

    fields = (
        ("Evidence ID", entry.evidence_id),
        ("Date", entry.entry_date),
        ("Activity", entry.activity_name),
        ("Category", entry.activity_category),
        ("Start time", entry.start_time),
        ("End time", entry.end_time),
        ("Duration", entry.duration or None),
        ("Duration minutes (derived)", entry.duration_minutes),
        ("Time period", entry.time_period or None),
        ("Productivity", entry.productivity_level),
        ("Mood before", entry.mood_before),
        ("Mood after", entry.mood_after),
        ("Task outcome", entry.task_outcome),
        ("Health status", entry.health_status),
        ("Location", entry.location),
        ("With whom", entry.with_whom),
        ("Specific person", entry.specific_person or None),
        ("Notes", entry.notes),
    )
    return "\n".join(f"{label}: {value}" for label, value in fields if value is not None)


def _join_evidence(entries: Sequence[DiaryEntryResponse]) -> str:
    ordered = sorted(entries, key=lambda item: (item.entry_date, item.start_time, item.evidence_id))
    return "\n\n--- CANONICAL DIARY ENTRY ---\n\n".join(
        _entry_to_evidence_text(entry) for entry in ordered
    )


def _normalize_lexical_token(token: str) -> str:
    """Apply small deterministic normalizations used only for evidence selection."""

    irregular = {
        "met": "meet",
        "studies": "study",
        "studied": "study",
    }
    if token in irregular:
        return irregular[token]
    if len(token) > 4 and token.endswith("ies"):
        return f"{token[:-3]}y"
    if len(token) > 4 and token.endswith("ied"):
        return f"{token[:-3]}y"
    if len(token) > 5 and token.endswith("ing"):
        stem = token[:-3]
        if len(stem) > 2 and stem[-1] == stem[-2]:
            stem = stem[:-1]
        return stem
    if len(token) > 4 and token.endswith("ed"):
        stem = token[:-2]
        if len(stem) > 2 and stem[-1] == stem[-2]:
            stem = stem[:-1]
        return stem
    if (
        len(token) > 3
        and token.endswith("s")
        and not token.endswith(("ss", "us", "is"))
    ):
        return token[:-1]
    return token


def _lexical_tokens(value: Any) -> List[str]:
    raw_tokens = _LEXICAL_TOKEN_RE.findall(str(value or "").casefold())
    tokens: List[str] = []
    for raw_token in raw_tokens:
        if raw_token in _PLAIN_STOPWORDS:
            continue
        token = _normalize_lexical_token(raw_token)
        if token and token not in _PLAIN_STOPWORDS:
            tokens.append(token)
    return tokens


def _entry_weekday(entry: DiaryEntryResponse) -> str:
    try:
        return date.fromisoformat(entry.entry_date).strftime("%A")
    except ValueError:
        return ""


def _entry_relevance_tokens(
    entry: DiaryEntryResponse,
) -> Tuple[Dict[str, int], set[str]]:
    """Return field-weighted tokens without treating overlap as claim support."""

    weighted_fields = (
        (entry.evidence_id, 8),
        (entry.activity_name, 6),
        (entry.notes, 5),
        (entry.activity_category, 3),
        (entry.task_outcome, 3),
        (entry.mood_before, 3),
        (entry.mood_after, 3),
        (entry.productivity_level, 2),
        (entry.health_status, 2),
        (entry.location, 2),
        (entry.with_whom, 2),
        (entry.specific_person, 2),
        (entry.duration, 1),
        (entry.time_period, 1),
        (entry.entry_date, 1),
        (_entry_weekday(entry), 2),
    )
    weights: Dict[str, int] = {}
    for value, weight in weighted_fields:
        for token in set(_lexical_tokens(value)):
            weights[token] = max(weights.get(token, 0), weight)
    return weights, set(_lexical_tokens(entry.activity_name))


def _plain_relevance_record(
    claim_text: str,
    entry: DiaryEntryResponse,
) -> Dict[str, Any]:
    claim_tokens = set(_lexical_tokens(claim_text))
    entry_weights, activity_tokens = _entry_relevance_tokens(entry)
    matched_tokens = sorted(claim_tokens.intersection(entry_weights))
    score = sum(entry_weights[token] for token in matched_tokens)
    if activity_tokens and activity_tokens.issubset(claim_tokens):
        score += 8 + len(activity_tokens)
    return {
        "entry": entry,
        "score": score,
        "matched_tokens": matched_tokens,
    }


def _rank_plain_evidence(
    claim_text: str,
    entries: Sequence[DiaryEntryResponse],
) -> List[Dict[str, Any]]:
    ranked = [_plain_relevance_record(claim_text, entry) for entry in entries]
    return sorted(
        ranked,
        key=lambda item: (
            -item["score"],
            item["entry"].entry_date,
            item["entry"].start_time,
            item["entry"].evidence_id,
        ),
    )


def _chronological_sample(
    entries: Sequence[DiaryEntryResponse],
    maximum: int,
) -> List[DiaryEntryResponse]:
    """Choose a deterministic, week-spanning fallback when words do not match."""

    ordered = sorted(
        entries,
        key=lambda item: (item.entry_date, item.start_time, item.evidence_id),
    )
    if len(ordered) <= maximum:
        return ordered
    if maximum == 1:
        return [ordered[0]]
    indices = [round(index * (len(ordered) - 1) / (maximum - 1)) for index in range(maximum)]
    return [ordered[index] for index in dict.fromkeys(indices)]


def _select_plain_claim_evidence(
    claim: str,
    entries: Sequence[DiaryEntryResponse],
) -> Tuple[List[DiaryEntryResponse], Dict[str, Any]]:
    """Select bounded claim-specific evidence, including compound-clause coverage."""

    ordered_candidates = sorted(
        entries,
        key=lambda item: (item.entry_date, item.start_time, item.evidence_id),
    )
    segments = [
        segment.strip()
        for segment in _CLAIM_SEGMENT_RE.split(claim)
        if _lexical_tokens(segment)
    ] or [claim]
    overall_ranking = _rank_plain_evidence(claim, entries)
    selected_by_id: Dict[str, DiaryEntryResponse] = {}
    matched_segments = 0

    # First reserve one best record for each clause. This prevents an activity
    # with many shared words from crowding out the other items in a list.
    for segment in segments:
        segment_ranking = _rank_plain_evidence(segment, entries)
        if not segment_ranking or segment_ranking[0]["score"] <= 0:
            continue
        matched_segments += 1
        entry = segment_ranking[0]["entry"]
        selected_by_id.setdefault(entry.evidence_id, entry)
        if len(selected_by_id) >= _PLAIN_MAX_EVIDENCE_ENTRIES:
            break

    # Fill remaining capacity with the strongest whole-claim matches.
    for record in overall_ranking:
        if len(selected_by_id) >= _PLAIN_MAX_EVIDENCE_ENTRIES:
            break
        if record["score"] <= 0:
            continue
        entry = record["entry"]
        selected_by_id.setdefault(entry.evidence_id, entry)

    fallback_used = not selected_by_id and bool(entries)
    if fallback_used:
        for entry in _chronological_sample(entries, _PLAIN_MAX_EVIDENCE_ENTRIES):
            selected_by_id[entry.evidence_id] = entry

    selected = sorted(
        selected_by_id.values(),
        key=lambda item: (item.entry_date, item.start_time, item.evidence_id),
    )
    scores_by_id = {
        record["entry"].evidence_id: {
            "score": record["score"],
            "matched_tokens": record["matched_tokens"],
        }
        for record in overall_ranking
    }
    metadata = {
        "status": "available",
        "method": _PLAIN_EVIDENCE_SELECTION_METHOD,
        "candidate_count": len(entries),
        "candidate_evidence_ids": [
            entry.evidence_id for entry in ordered_candidates
        ],
        "selected_count": len(selected),
        "selected_evidence_ids": [entry.evidence_id for entry in selected],
        "unselected_evidence_ids": [
            entry.evidence_id
            for entry in ordered_candidates
            if entry.evidence_id not in selected_by_id
        ],
        "max_selected_entries": _PLAIN_MAX_EVIDENCE_ENTRIES,
        "claim_segment_count": len(segments),
        "matched_claim_segment_count": matched_segments,
        "fallback_used": fallback_used,
        "selection_score_purpose": "evidence_routing_only",
        "selection_scores": [
            {
                "evidence_id": entry.evidence_id,
                **scores_by_id[entry.evidence_id],
            }
            for entry in selected
        ],
    }
    return selected, metadata


def _compact_evidence_value(value: Any, maximum: int = 240) -> str:
    compact = re.sub(r"\s+", " ", str(value or "")).strip()
    if len(compact) <= maximum:
        return compact
    return f"{compact[: maximum - 3].rstrip()}..."


def _bounded_plain_entry_text(
    entry: DiaryEntryResponse,
    claim_tokens: set[str],
    maximum: int,
) -> str:
    """Serialize one entry with claim-relevant fields first and a hard bound."""

    fields = (
        ("Evidence ID", entry.evidence_id),
        ("Date", entry.entry_date),
        ("Activity", entry.activity_name),
        ("Category", entry.activity_category),
        ("Notes", entry.notes),
        ("Productivity", entry.productivity_level),
        ("Mood before", entry.mood_before),
        ("Mood after", entry.mood_after),
        ("Task outcome", entry.task_outcome),
        ("Health status", entry.health_status),
        ("Location", entry.location),
        ("With whom", entry.with_whom),
        ("Specific person", entry.specific_person),
        ("Start time", entry.start_time),
        ("End time", entry.end_time),
        ("Duration", entry.duration),
        ("Time period", entry.time_period),
    )
    required = list(enumerate(fields[:3]))
    optional = list(enumerate(fields[3:], start=3))
    optional.sort(
        key=lambda item: (
            -len(claim_tokens.intersection(_lexical_tokens(item[1][1]))),
            item[0],
        )
    )
    ordered_fields = [field for _, field in required + optional]
    lines: List[str] = []
    used = 0
    for label, raw_value in ordered_fields:
        value = _compact_evidence_value(raw_value)
        if not value:
            continue
        line = f"{label}: {value}"
        prefix_length = 1 if lines else 0
        remaining = maximum - used - prefix_length
        if remaining <= 0:
            break
        if len(line) > remaining:
            if remaining > len(label) + 4:
                line = f"{line[: remaining - 3].rstrip()}..."
            else:
                continue
        lines.append(line)
        used += prefix_length + len(line)
    return "\n".join(lines)


def _join_bounded_claim_evidence(
    entries: Sequence[DiaryEntryResponse],
    claim: str,
) -> str:
    """Build a fair, bounded premise in which every selected record appears."""

    if not entries:
        return ""
    ordered = sorted(
        entries,
        key=lambda item: (item.entry_date, item.start_time, item.evidence_id),
    )
    separator = "\n\n--- CANONICAL DIARY ENTRY ---\n\n"
    available = _PLAIN_PREMISE_MAX_CHARS - len(separator) * (len(ordered) - 1)
    per_entry = max(1, available // len(ordered))
    remainder = max(0, available - per_entry * len(ordered))
    claim_tokens = set(_lexical_tokens(claim))
    blocks = [
        _bounded_plain_entry_text(
            entry,
            claim_tokens,
            per_entry + (1 if index < remainder else 0),
        )
        for index, entry in enumerate(ordered)
    ]
    return separator.join(blocks)[:_PLAIN_PREMISE_MAX_CHARS]


def _as_mapping(value: Any) -> Dict[str, Any]:
    if isinstance(value, Mapping):
        return dict(value)
    if hasattr(value, "model_dump"):
        return value.model_dump()
    if hasattr(value, "dict"):
        return value.dict()
    return {}


def _clean_reference_value(value: Any) -> Optional[str]:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _citation_objects(point: Mapping[str, Any]) -> List[Dict[str, Any]]:
    normalized: List[Dict[str, Any]] = []
    for raw_citation in point.get("citations") or []:
        citation = _as_mapping(raw_citation)
        normalized.append(
            {
                "label": _clean_reference_value(citation.get("label")),
                "evidence_id": _clean_reference_value(citation.get("evidence_id")),
                "parser_is_valid": citation.get("is_valid"),
                "parser_validation_error": _clean_reference_value(
                    citation.get("validation_error")
                ),
            }
        )
    return normalized


def _inline_references(text: str) -> List[Dict[str, Optional[str]]]:
    references: List[Dict[str, Optional[str]]] = []
    for match in _BRACKETED_REFERENCE_RE.finditer(text):
        raw_label = match.group(0)
        content = _CITATION_PREFIX_RE.sub("", match.group(1)).strip()
        parts = [part.strip() for part in re.split(r"[,;]", content) if part.strip()]
        for part in parts:
            references.append({"label": raw_label, "reference": part})
    return references


def _strip_citation_markers(claim: str) -> str:
    return re.sub(r"\s+", " ", _BRACKETED_REFERENCE_RE.sub("", claim)).strip()


def _point_claim_records(raw_point: Any) -> List[Dict[str, Any]]:
    point = _as_mapping(raw_point)
    text = str(point.get("text") or "").strip()
    if not text:
        return []
    citations = _citation_objects(point)
    claim_id = _clean_reference_value(point.get("claim_id"))
    inline = _inline_references(text)
    if not inline:
        hypothesis = _strip_citation_markers(text)
        if not hypothesis:
            return []
        return [
            {
                "claim_id": claim_id,
                "claim": text,
                "hypothesis": hypothesis,
                "citations": citations,
            }
        ]

    label_lookup: Dict[str, List[Dict[str, Optional[str]]]] = {}
    evidence_lookup: Dict[str, List[Dict[str, Optional[str]]]] = {}
    for citation in citations:
        if citation["label"]:
            label_lookup.setdefault(citation["label"], []).append(citation)
        if citation["evidence_id"]:
            evidence_lookup.setdefault(citation["evidence_id"], []).append(citation)

    records: List[Dict[str, Any]] = []
    for sentence in split_into_claims(text):
        sentence_citations: List[Dict[str, Optional[str]]] = []
        for reference in _inline_references(sentence):
            raw_label = reference["label"]
            reference_value = reference["reference"]
            matching = label_lookup.get(raw_label or "", [])
            if not matching and reference_value:
                matching = evidence_lookup.get(reference_value, [])
            if len(matching) == 1:
                sentence_citations.append(dict(matching[0]))
            elif len(matching) > 1:
                sentence_citations.append(
                    {"label": raw_label, "evidence_id": None, "parse_error": "ambiguous_citation_label"}
                )
            elif reference_value and not reference_value.isdigit():
                sentence_citations.append({"label": raw_label, "evidence_id": reference_value})
            else:
                sentence_citations.append(
                    {"label": raw_label, "evidence_id": None, "parse_error": "unmapped_citation_label"}
                )
        hypothesis = _strip_citation_markers(sentence)
        if hypothesis:
            records.append(
                {
                    "claim_id": claim_id,
                    "claim": sentence,
                    "hypothesis": hypothesis,
                    "citations": sentence_citations,
                }
            )
    return records


def _canonical_label(
    label: Any,
    runner: Any,
    *,
    allow_default_label_order: bool,
) -> Optional[str]:
    normalized = str(label or "").strip().lower()
    for expected in ("entailment", "contradiction", "neutral"):
        if expected in normalized:
            return expected
    generic_match = re.fullmatch(r"label[_-]?(\d+)", normalized)
    if not generic_match:
        return None
    label_id = int(generic_match.group(1))
    config = getattr(getattr(runner, "model", None), "config", None)
    id_to_label = getattr(config, "id2label", {}) if config is not None else {}
    configured_label = id_to_label.get(label_id, id_to_label.get(str(label_id)))
    if configured_label is not None:
        configured = str(configured_label).lower()
        for expected in ("entailment", "contradiction", "neutral"):
            if expected in configured:
                return expected
    if allow_default_label_order:
        # Documented label order for the required default model only. A custom
        # model with generic labels must expose a meaningful id2label mapping.
        return {0: "contradiction", 1: "entailment", 2: "neutral"}.get(label_id)
    return None


def _flatten_nli_output(value: Any) -> List[Mapping[str, Any]]:
    if isinstance(value, Mapping):
        return [value] if "label" in value and "score" in value else []
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        flattened: List[Mapping[str, Any]] = []
        for item in value:
            flattened.extend(_flatten_nli_output(item))
        return flattened
    return []


def _run_nli(
    runner: Any,
    premise: str,
    hypothesis: str,
    *,
    model_name: str,
) -> Dict[str, float]:
    raw_result = runner(
        {"text": premise, "text_pair": hypothesis}, truncation=True, top_k=None
    )
    scores: Dict[str, float] = {}
    for item in _flatten_nli_output(raw_result):
        label = _canonical_label(
            item.get("label"),
            runner,
            allow_default_label_order=model_name == DEFAULT_NLI_MODEL,
        )
        if label is None:
            continue
        score = float(item["score"])
        if not math.isfinite(score) or not 0.0 <= score <= 1.0:
            raise RuntimeError("The NLI model returned a non-probability score.")
        scores[label] = score
    if not {"entailment", "contradiction", "neutral"}.issubset(scores):
        raise RuntimeError("The NLI model did not return all three required labels.")
    return scores


def _classify_nli(scores: Mapping[str, float], threshold: float) -> str:
    if scores["entailment"] >= threshold:
        return "entailed"
    if (
        scores["contradiction"] >= scores["entailment"]
        and scores["contradiction"] >= scores["neutral"]
    ):
        return "contradicted"
    return "neutral"


def _observed_model_revision(runner: Any, configured_revision: Optional[str]) -> Optional[str]:
    if configured_revision:
        return configured_revision
    config = getattr(getattr(runner, "model", None), "config", None)
    revision = getattr(config, "_commit_hash", None) if config is not None else None
    return str(revision) if revision else None


def _citation_metrics_not_applicable() -> Dict[str, Any]:
    return {
        "status": "not_applicable",
        "reason": "The plain-SLM condition does not produce citations.",
        "total_citations": None,
        "valid_citations": None,
        "invalid_citations": None,
        "citation_precision": None,
        "claims_with_valid_citation": None,
        "citation_completeness": None,
    }


def _base_result(
    *,
    model_name: str,
    model_revision: Optional[str],
    threshold: Optional[float],
    total_claims: int,
    citation_metrics: Dict[str, Any],
    per_claim: List[Dict[str, Any]],
) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "status": "available",
        "reason": None,
        "evaluation_method": "natural_language_inference",
        "nli_model": model_name,
        "nli_model_revision": model_revision,
        "entailment_threshold": threshold,
        "total_factual_claims": total_claims,
        "total_claims": total_claims,
        "citation_metrics": citation_metrics,
        "per_claim": per_claim,
        "claim_details": per_claim,
    }
    for key in (
        "total_citations",
        "valid_citations",
        "invalid_citations",
        "citation_precision",
        "claims_with_valid_citation",
        "citation_completeness",
    ):
        result[key] = citation_metrics.get(key)
    return result


def _finalize_available(result: Dict[str, Any]) -> Dict[str, Any]:
    per_claim = result["per_claim"]
    total = result["total_factual_claims"]
    if total == 0:
        result.update(
            {
                "status": "not_applicable",
                "reason": "The summary contains no factual claims to evaluate.",
                "entailed_claim_count": 0,
                "contradicted_claim_count": 0,
                "neutral_claim_count": 0,
                "no_valid_evidence_claim_count": 0,
                "unsupported_claim_count": 0,
                "grounded_claim_rate": None,
                "unsupported_claim_rate": None,
                "hallucination_score": None,
                "supported_claims": 0,
                "unsupported_claims": 0,
                "unsupported_claim_details": [],
            }
        )
        return result
    entailed = sum(item["classification"] == "entailed" for item in per_claim)
    contradicted = sum(item["classification"] == "contradicted" for item in per_claim)
    neutral = sum(item["classification"] == "neutral" for item in per_claim)
    no_valid_evidence = sum(item["classification"] == "unsupported" for item in per_claim)
    unsupported = total - entailed
    grounded_rate = round(entailed / total, 4)
    unsupported_rate = round(unsupported / total, 4)
    unsupported_details = [
        {
            "claim": item["claim"],
            "classification": item["classification"],
            "reason": item["reason"],
            "evidence_ids": item["valid_evidence_ids"],
            "entailment_score": item["entailment_score"],
        }
        for item in per_claim
        if item["classification"] != "entailed"
    ]
    result.update(
        {
            "entailed_claim_count": entailed,
            "contradicted_claim_count": contradicted,
            "neutral_claim_count": neutral,
            "no_valid_evidence_claim_count": no_valid_evidence,
            "unsupported_claim_count": unsupported,
            "grounded_claim_rate": grounded_rate,
            "unsupported_claim_rate": unsupported_rate,
            "hallucination_score": unsupported_rate,
            "supported_claims": entailed,
            "unsupported_claims": unsupported,
            "unsupported_claim_details": unsupported_details,
        }
    )
    return result


def _finalize_unavailable(result: Dict[str, Any], reason: str) -> Dict[str, Any]:
    for item in result["per_claim"]:
        if item.pop("_requires_nli", False):
            item.update(
                {
                    "classification": None,
                    "entailment_score": None,
                    "contradiction_score": None,
                    "neutral_score": None,
                    "reason": "NLI evaluation is unavailable for this claim.",
                }
            )
        item.pop("hypothesis", None)
    result.update(
        {
            "status": "unavailable",
            "reason": reason,
            "entailed_claim_count": None,
            "contradicted_claim_count": None,
            "neutral_claim_count": None,
            "no_valid_evidence_claim_count": sum(
                item.get("classification") == "unsupported" for item in result["per_claim"]
            ),
            "unsupported_claim_count": None,
            "grounded_claim_rate": None,
            "unsupported_claim_rate": None,
            "hallucination_score": None,
            "supported_claims": None,
            "unsupported_claims": None,
            "unsupported_claim_details": [],
        }
    )
    return result


def _evaluate_claims_with_nli(
    result: Dict[str, Any],
    *,
    premise_by_claim: Sequence[Optional[str]],
    threshold: float,
    nli_runner: Optional[Callable[..., Any]],
    model_name: str,
    model_revision: Optional[str],
    entailed_reason: str = "Valid cited evidence meets the entailment threshold.",
    neutral_reason: str = "The cited evidence does not meet the entailment threshold.",
) -> Dict[str, Any]:
    if not result["per_claim"]:
        return _finalize_available(result)
    runner: Any = nli_runner
    for claim_detail, premise in zip(result["per_claim"], premise_by_claim):
        claim_detail["_requires_nli"] = bool(premise)
    try:
        for claim_detail, premise in zip(result["per_claim"], premise_by_claim):
            if not premise:
                claim_detail.update(
                    {
                        "classification": "unsupported",
                        "entailment_score": None,
                        "contradiction_score": None,
                        "neutral_score": None,
                        "reason": "No valid canonical evidence is available for this claim.",
                    }
                )
                continue
            if runner is None:
                runner = _get_nli_pipeline(model_name, model_revision)
                result["nli_model_revision"] = _observed_model_revision(runner, model_revision)
            scores = _run_nli(
                runner,
                premise,
                claim_detail["hypothesis"],
                model_name=model_name,
            )
            classification = _classify_nli(scores, threshold)
            reason_by_class = {
                "entailed": entailed_reason,
                "contradicted": "The NLI model classifies the evidence as contradictory.",
                "neutral": neutral_reason,
            }
            claim_detail.update(
                {
                    "classification": classification,
                    "entailment_score": round(scores["entailment"], 4),
                    "contradiction_score": round(scores["contradiction"], 4),
                    "neutral_score": round(scores["neutral"], 4),
                    "reason": reason_by_class[classification],
                }
            )
    except Exception as error:
        return _finalize_unavailable(result, f"NLI evaluation failed ({type(error).__name__}).")
    for item in result["per_claim"]:
        item.pop("_requires_nli", None)
        item.pop("hypothesis", None)
    return _finalize_available(result)


def _scope_failure_result(
    *,
    total_claims: int,
    per_claim: List[Dict[str, Any]],
    model_name: str,
    model_revision: Optional[str],
    threshold: Optional[float],
    reason: str,
    citation_metrics: Dict[str, Any],
) -> Dict[str, Any]:
    result = _base_result(
        model_name=model_name,
        model_revision=model_revision,
        threshold=threshold,
        total_claims=total_claims,
        citation_metrics=citation_metrics,
        per_claim=per_claim,
    )
    return _finalize_unavailable(result, reason)


def evaluate_plain_summary_groundedness(
    summary_text: str,
    source_entries: Sequence[DiaryEntryResponse],
    *,
    user_id: Optional[str] = None,
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
    nli_model_name: Optional[str] = None,
    nli_model_revision: Optional[str] = None,
    entailment_threshold: Optional[float] = None,
    nli_runner: Optional[Callable[..., Any]] = None,
) -> Dict[str, Any]:
    """Evaluate each plain-summary claim against selected canonical evidence.

    Result keys include status/reason/model/threshold, claim category counts,
    grounded and unsupported rates, per-claim evidence-selection metadata,
    evidence IDs, classification and NLI scores. Citation fields are explicitly
    ``not_applicable``/``None``. The selector covers compound claim clauses and
    bounds every NLI premise so later weekly records are not silently truncated.
    ``unsupported_claim_count`` means every non-entailed claim.
    ``hallucination_score`` is a deprecated exact alias for
    ``unsupported_claim_rate`` and is null whenever that rate is unavailable.
    """

    model_name = _resolve_model_name(nli_model_name)
    model_revision = _resolve_model_revision(nli_model_revision)
    claims = split_into_claims(summary_text)
    canonical_entries, _ = _coerce_entries(source_entries)
    resolved_user, resolved_start, resolved_end, scope_error = _resolve_scope(
        canonical_entries, user_id, week_start, week_end
    )
    citation_metrics = _citation_metrics_not_applicable()
    per_claim = [
        {
            "claim": claim,
            "hypothesis": _strip_citation_markers(claim),
            "cited_evidence_ids": None,
            "valid_evidence_ids": [],
            "invalid_evidence_ids": [],
            "evidence_ids": [],
            "classification": None,
            "entailment_score": None,
            "contradiction_score": None,
            "neutral_score": None,
            "reason": None,
            "evidence_selection": {
                "status": "not_run",
                "reason": "Canonical user/week scope has not been resolved.",
            },
        }
        for claim in claims
    ]
    try:
        threshold = _resolve_threshold(entailment_threshold)
    except ValueError as error:
        return _scope_failure_result(
            total_claims=len(claims), per_claim=per_claim, model_name=model_name,
            model_revision=model_revision, threshold=None, reason=str(error),
            citation_metrics=citation_metrics,
        )
    if scope_error:
        return _scope_failure_result(
            total_claims=len(claims), per_claim=per_claim, model_name=model_name,
            model_revision=model_revision, threshold=threshold, reason=scope_error,
            citation_metrics=citation_metrics,
        )
    scoped_entries = [
        entry for entry in canonical_entries
        if entry.user_id == resolved_user and _entry_matches_week(entry, resolved_start, resolved_end)
    ]
    premise_by_claim: List[Optional[str]] = []
    for detail in per_claim:
        selected_entries, selection = _select_plain_claim_evidence(
            detail["hypothesis"],
            scoped_entries,
        )
        premise = (
            _join_bounded_claim_evidence(selected_entries, detail["hypothesis"])
            if selected_entries
            else None
        )
        selected_ids = [entry.evidence_id for entry in selected_entries]
        selection.update(
            {
                "premise_character_count": len(premise or ""),
                "premise_character_limit": _PLAIN_PREMISE_MAX_CHARS,
            }
        )
        detail["valid_evidence_ids"] = selected_ids
        detail["evidence_ids"] = selected_ids
        detail["evidence_selection"] = selection
        premise_by_claim.append(premise)
    result = _base_result(
        model_name=model_name, model_revision=model_revision, threshold=threshold,
        total_claims=len(claims), citation_metrics=citation_metrics, per_claim=per_claim,
    )
    result["evidence_selection"] = {
        "status": "available",
        "method": _PLAIN_EVIDENCE_SELECTION_METHOD,
        "scope_candidate_count": len(scoped_entries),
        "scope_candidate_evidence_ids": [
            entry.evidence_id
            for entry in sorted(
                scoped_entries,
                key=lambda item: (
                    item.entry_date,
                    item.start_time,
                    item.evidence_id,
                ),
            )
        ],
        "max_entries_per_claim": _PLAIN_MAX_EVIDENCE_ENTRIES,
        "premise_character_limit": _PLAIN_PREMISE_MAX_CHARS,
        "claim_scoped": True,
        "uses_full_week_premise": False,
        "selection_score_purpose": "evidence_routing_only",
    }
    return _evaluate_claims_with_nli(
        result, premise_by_claim=premise_by_claim, threshold=threshold,
        nli_runner=nli_runner, model_name=model_name, model_revision=model_revision,
        entailed_reason=(
            "Selected canonical evidence meets the entailment threshold."
        ),
        neutral_reason=(
            "The selected canonical evidence does not meet the entailment threshold."
        ),
    )


def _build_evidence_catalog(
    entries: Sequence[DiaryEntryResponse],
    rejected_entries: Sequence[Any],
    *,
    user_id: str,
    week_start: str,
    week_end: str,
) -> Tuple[Dict[str, DiaryEntryResponse], Dict[str, str]]:
    valid_candidates: Dict[str, List[DiaryEntryResponse]] = {}
    invalid_reasons: Dict[str, str] = {}
    for entry in entries:
        evidence_id = entry.evidence_id
        if entry.user_id != user_id:
            invalid_reasons.setdefault(evidence_id, "wrong_user")
            continue
        if not _entry_matches_week(entry, week_start, week_end):
            invalid_reasons.setdefault(evidence_id, "wrong_week")
            continue
        valid_candidates.setdefault(evidence_id, []).append(entry)
    valid: Dict[str, DiaryEntryResponse] = {}
    for evidence_id, candidates in valid_candidates.items():
        if len(candidates) == 1:
            valid[evidence_id] = candidates[0]
        else:
            invalid_reasons[evidence_id] = "ambiguous_duplicate_evidence_id"
    for raw_entry in rejected_entries:
        if isinstance(raw_entry, Mapping):
            evidence_id = _clean_reference_value(raw_entry.get("evidence_id"))
            if evidence_id:
                invalid_reasons.setdefault(evidence_id, "noncanonical_source_record")
    return valid, invalid_reasons


def evaluate_rag_summary_groundedness(
    summary_points: Sequence[Any],
    source_entries: Optional[Sequence[DiaryEntryResponse]] = None,
    *,
    user_id: Optional[str] = None,
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
    nli_model_name: Optional[str] = None,
    nli_model_revision: Optional[str] = None,
    entailment_threshold: Optional[float] = None,
    nli_runner: Optional[Callable[..., Any]] = None,
    valid_evidence_ids: Optional[Sequence[str]] = None,
    allowed_evidence_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    """Validate citations and evaluate each RAG claim against only its evidence.

    The result includes flat and nested citation counts/precision/completeness,
    NLI claim counts/rates, ``citation_details`` and ``per_claim`` details.
    Citations resolve only from canonical ``DiaryEntryResponse`` records for the
    requested user/week. When ``allowed_evidence_ids`` is supplied, citations
    must also have appeared in the model prompt. ``valid_evidence_ids`` is a
    deprecated keyword: an ID list alone cannot establish ownership/week or
    provide an NLI premise, so ID-only calls return unavailable.
    ``hallucination_score`` is an exact deprecated alias for
    ``unsupported_claim_rate`` when available.
    """

    model_name = _resolve_model_name(nli_model_name)
    model_revision = _resolve_model_revision(nli_model_revision)
    raw_claims: List[Dict[str, Any]] = []
    for point in summary_points or []:
        raw_claims.extend(_point_claim_records(point))
    try:
        threshold = _resolve_threshold(entailment_threshold)
    except ValueError as error:
        per_claim = [
            {
                **record, "cited_evidence_ids": [], "valid_evidence_ids": [],
                "invalid_evidence_ids": [], "evidence_ids": [], "classification": None,
                "entailment_score": None, "contradiction_score": None,
                "neutral_score": None, "reason": None,
            }
            for record in raw_claims
        ]
        citation_metrics = {
            "status": "unavailable", "reason": str(error),
            "total_citations": sum(len(item["citations"]) for item in raw_claims),
            "valid_citations": None, "invalid_citations": None,
            "citation_precision": None, "claims_with_valid_citation": None,
            "citation_completeness": None,
        }
        return _scope_failure_result(
            total_claims=len(raw_claims), per_claim=per_claim, model_name=model_name,
            model_revision=model_revision, threshold=None, reason=str(error),
            citation_metrics=citation_metrics,
        )

    canonical_entries, rejected_entries = _coerce_entries(source_entries)
    if source_entries is None and valid_evidence_ids is not None:
        resolved_user = resolved_start = resolved_end = None
        scope_error = (
            "Canonical DiaryEntryResponse records are required; valid_evidence_ids "
            "alone cannot verify user/week ownership or run NLI."
        )
    else:
        resolved_user, resolved_start, resolved_end, scope_error = _resolve_scope(
            canonical_entries, user_id, week_start, week_end
        )
    if scope_error:
        per_claim = [
            {
                **record,
                "cited_evidence_ids": [c.get("evidence_id") for c in record["citations"] if c.get("evidence_id")],
                "valid_evidence_ids": [],
                "invalid_evidence_ids": [c.get("evidence_id") for c in record["citations"] if c.get("evidence_id")],
                "evidence_ids": [], "classification": None, "entailment_score": None,
                "contradiction_score": None, "neutral_score": None, "reason": None,
            }
            for record in raw_claims
        ]
        total_citations = sum(len(item["citations"]) for item in raw_claims)
        citation_metrics = {
            "status": "unavailable", "reason": scope_error,
            "total_citations": total_citations, "valid_citations": None,
            "invalid_citations": None, "citation_precision": None,
            "claims_with_valid_citation": None, "citation_completeness": None,
        }
        return _scope_failure_result(
            total_claims=len(raw_claims), per_claim=per_claim, model_name=model_name,
            model_revision=model_revision, threshold=threshold, reason=scope_error,
            citation_metrics=citation_metrics,
        )

    valid_entries, invalid_catalog = _build_evidence_catalog(
        canonical_entries, rejected_entries, user_id=resolved_user,
        week_start=resolved_start, week_end=resolved_end,
    )
    prompt_evidence_ids = (
        {str(evidence_id).strip() for evidence_id in allowed_evidence_ids}
        if allowed_evidence_ids is not None
        else None
    )
    citation_details: List[Dict[str, Any]] = []
    per_claim: List[Dict[str, Any]] = []
    premise_by_claim: List[Optional[str]] = []
    for claim_index, record in enumerate(raw_claims, start=1):
        cited_ids: List[str] = []
        valid_ids: List[str] = []
        invalid_ids: List[str] = []
        valid_for_claim: List[DiaryEntryResponse] = []
        for citation in record["citations"]:
            evidence_id = citation.get("evidence_id")
            label = citation.get("label")
            parse_error = citation.get("parse_error")
            if evidence_id:
                cited_ids.append(evidence_id)
            if parse_error:
                is_valid, invalid_reason = False, parse_error
            elif citation.get("parser_is_valid") is False:
                is_valid, invalid_reason = False, (
                    citation.get("parser_validation_error")
                    or "citation_rejected_during_output_parsing"
                )
            elif not evidence_id:
                is_valid, invalid_reason = False, "missing_evidence_id"
            elif prompt_evidence_ids is not None and evidence_id not in prompt_evidence_ids:
                is_valid, invalid_reason = False, "evidence_id_not_supplied_to_model"
            elif evidence_id in valid_entries:
                is_valid, invalid_reason = True, None
                valid_ids.append(evidence_id)
                valid_for_claim.append(valid_entries[evidence_id])
            else:
                is_valid, invalid_reason = False, invalid_catalog.get(evidence_id, "unknown_evidence_id")
            if not is_valid and evidence_id:
                invalid_ids.append(evidence_id)
            citation_details.append(
                {"claim_index": claim_index, "label": label, "evidence_id": evidence_id,
                 "valid": is_valid, "reason": invalid_reason}
            )
        unique_entries: List[DiaryEntryResponse] = []
        seen_ids = set()
        for entry in valid_for_claim:
            if entry.evidence_id not in seen_ids:
                seen_ids.add(entry.evidence_id)
                unique_entries.append(entry)
        valid_ids = list(dict.fromkeys(valid_ids))
        invalid_ids = list(dict.fromkeys(invalid_ids))
        per_claim.append(
            {
                "claim": record["claim"], "hypothesis": record["hypothesis"],
                "cited_evidence_ids": cited_ids, "valid_evidence_ids": valid_ids,
                "invalid_evidence_ids": invalid_ids, "evidence_ids": valid_ids,
                "classification": None, "entailment_score": None,
                "contradiction_score": None, "neutral_score": None, "reason": None,
            }
        )
        premise_by_claim.append(
            _join_bounded_claim_evidence(unique_entries, record["hypothesis"])
            if unique_entries
            else None
        )

    total_citations = len(citation_details)
    valid_citations = sum(item["valid"] for item in citation_details)
    total_claims = len(per_claim)
    claims_with_valid = sum(bool(item["valid_evidence_ids"]) for item in per_claim)
    citation_metrics = {
        "status": "available" if total_claims or total_citations else "not_applicable",
        "reason": None if total_claims or total_citations else "The summary contains no claims or citations.",
        "total_citations": total_citations,
        "valid_citations": valid_citations,
        "invalid_citations": total_citations - valid_citations,
        "citation_precision": round(valid_citations / total_citations, 4) if total_citations else None,
        "claims_with_valid_citation": claims_with_valid,
        "citation_completeness": round(claims_with_valid / total_claims, 4) if total_claims else None,
    }
    result = _base_result(
        model_name=model_name, model_revision=model_revision, threshold=threshold,
        total_claims=total_claims, citation_metrics=citation_metrics, per_claim=per_claim,
    )
    result["citation_details"] = citation_details
    return _evaluate_claims_with_nli(
        result, premise_by_claim=premise_by_claim, threshold=threshold,
        nli_runner=nli_runner, model_name=model_name, model_revision=model_revision,
    )


def evaluate_plain_summary_hallucination(
    summary_text: str,
    source_entries: Sequence[DiaryEntryResponse],
    threshold: Optional[float] = None,
    **kwargs: Any,
) -> Dict[str, Any]:
    """Deprecated name for :func:`evaluate_plain_summary_groundedness`."""

    if threshold is not None and "entailment_threshold" not in kwargs:
        kwargs["entailment_threshold"] = threshold
    return evaluate_plain_summary_groundedness(summary_text, source_entries, **kwargs)


def evaluate_rag_summary_hallucination(
    summary_points: Sequence[Any],
    source_entries: Optional[Sequence[DiaryEntryResponse]] = None,
    **kwargs: Any,
) -> Dict[str, Any]:
    """Deprecated name for :func:`evaluate_rag_summary_groundedness`."""

    return evaluate_rag_summary_groundedness(summary_points, source_entries, **kwargs)
