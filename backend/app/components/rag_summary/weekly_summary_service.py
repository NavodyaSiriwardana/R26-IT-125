"""Plain-text versus query-aware same-week RAG summarization orchestration."""

from __future__ import annotations

import re
import time
from typing import Any, Callable, Dict, List, Optional, Sequence
from uuid import uuid4

from app.config import GENERATION_SETTINGS, SUMMARY_SCHEMA_VERSION

from .chroma_store import (
    build_general_week_evidence,
    calculate_retrieval_coverage,
    retrieve_weekly_evidence,
)
from .date_utils import utc_now_iso, validate_week_range
from .feedback_generator import generate_feedback_from_rag_evidence
from .firestore_store import (
    list_diary_entries_for_week,
    save_summary,
)
from .hallucination_evaluator import (
    evaluate_plain_summary_groundedness,
    evaluate_rag_summary_groundedness,
)
from .schemas import DiaryEntryResponse, WeeklySummaryRequest, WeeklySummaryResponse
from .similarity_evaluator import evaluate_reference_similarity
from .summarizers import (
    GenerationFailure,
    RagParsingFailure,
    generate_plain_slm_summary_result,
    generate_rag_slm_summary,
    regenerate_unsupported_rag_claims,
)


SemanticRetriever = Callable[..., List[dict]]

_GENERAL_QUERY_WORDS = {
    "a",
    "about",
    "an",
    "activity",
    "activities",
    "and",
    "at",
    "can",
    "could",
    "diary",
    "did",
    "do",
    "doing",
    "done",
    "during",
    "entries",
    "feedback",
    "for",
    "from",
    "give",
    "had",
    "happen",
    "happened",
    "happening",
    "has",
    "have",
    "highlights",
    "how",
    "i",
    "include",
    "in",
    "key",
    "main",
    "me",
    "mood",
    "my",
    "of",
    "on",
    "overview",
    "patterns",
    "personal",
    "please",
    "productivity",
    "provide",
    "recap",
    "relevant",
    "review",
    "s",
    "selected",
    "show",
    "summarise",
    "summarize",
    "summary",
    "tell",
    "the",
    "this",
    "to",
    "week",
    "weekly",
    "went",
    "what",
    "was",
    "were",
}

_HOLISTIC_WEEK_PHRASES = (
    "all activities",
    "all diary entries",
    "complete week",
    "entire week",
    "everything i did",
    "full week",
    "overview of my week",
    "recap my week",
    "review my week",
    "summarise my week",
    "summarize my week",
    "summary of my week",
    "this week s summary",
    "what did i do this week",
    "week overview",
    "weekly overview",
    "weekly summary",
    "whole week",
)

_FOCUSED_QUERY_PHRASES = (
    "focus on",
    "focused on",
    "focusing on",
    "only discuss",
    "only include",
    "related to",
    "specifically",
)

_HOLISTIC_SCOPE_WORDS = {
    "average",
    "all",
    "best",
    "compare",
    "comparison",
    "complete",
    "entire",
    "everything",
    "full",
    "least",
    "most",
    "overall",
    "pattern",
    "patterns",
    "total",
    "trend",
    "trends",
    "worst",
    "whole",
}


def _model_to_dict(model: Any) -> Dict[str, Any]:
    if hasattr(model, "model_dump"):
        return model.model_dump()
    return model.dict()


def _summary_points_to_text(points: Sequence[Dict[str, Any]]) -> str:
    return " ".join(
        str(point.get("text") or "").strip()
        for point in points
        if point.get("text")
    ).strip()


def _renumber_summary_points(points: Sequence[Dict[str, Any]]) -> None:
    for claim_index, point in enumerate(points, 1):
        point["claim_id"] = f"CLM-{claim_index:03d}"
        for citation_index, citation in enumerate(point.get("citations") or [], 1):
            citation["citation_id"] = f"CIT-{claim_index:03d}-{citation_index:02d}"


def _evidence_ids(evidence: Sequence[Dict[str, Any]]) -> List[str]:
    return list(
        dict.fromkeys(
            str(item.get("evidence_id") or "").strip()
            for item in evidence
            if str(item.get("evidence_id") or "").strip()
        )
    )


def _entailed_evidence_ids(evaluation: Dict[str, Any]) -> Optional[List[str]]:
    """Return sources represented by supported claims."""

    if evaluation.get("status") != "available":
        return None
    return list(
        dict.fromkeys(
            str(evidence_id).strip()
            for claim in evaluation.get("per_claim", [])
            if claim.get("classification") == "entailed"
            for evidence_id in claim.get("valid_evidence_ids", [])
            if str(evidence_id).strip()
        )
    )


def _unavailable_evaluation(reason: str) -> Dict[str, Any]:
    return {
        "status": "unavailable",
        "reason": reason,
        "evaluation_method": "paired_human_review",
        "grounded_claim_rate": None,
        "unsupported_claim_rate": None,
        "hallucination_score": None,
        "citation_metrics": {
            "status": "not_applicable",
            "citation_precision": None,
            "citation_completeness": None,
        },
    }


def _not_applicable_reference_metrics(reason: str) -> Dict[str, Any]:
    return {
        metric: {
            "status": "unavailable",
            "value": None,
            "reason": reason,
            "model": None,
            "metric": metric,
        }
        for metric in ("bertscore", "rouge_l")
    }


def _reference_metrics(candidate: str, reference_summary: Optional[str]) -> Dict[str, Any]:
    if not reference_summary or not reference_summary.strip():
        return _not_applicable_reference_metrics(
            "A human-written reference summary was not supplied."
        )
    return evaluate_reference_similarity(candidate, reference_summary)


def is_topic_specific_query(query: str) -> bool:
    """Return whether an automatic request should use semantic top-k retrieval.

    Comprehensive week requests must not lose records merely because their
    wording contains harmless modifiers such as ``personal patterns``. Explicit
    focus language still wins when a query asks for one narrow slice of a week.
    """

    normalized = " ".join(re.findall(r"[a-z0-9]+", query.lower()))
    tokens = set(normalized.split())
    if any(phrase in normalized for phrase in _FOCUSED_QUERY_PHRASES):
        return True
    if tokens & _HOLISTIC_SCOPE_WORDS:
        return False
    if any(phrase in normalized for phrase in _HOLISTIC_WEEK_PHRASES):
        return False
    return bool(tokens - _GENERAL_QUERY_WORDS)


def _resolve_retrieval_policy(retrieval_mode: str, query: str) -> tuple[bool, str]:
    if retrieval_mode == "all":
        return False, "explicit_all_mode"
    if retrieval_mode == "semantic":
        return True, "explicit_semantic_mode"
    if retrieval_mode != "auto":
        raise ValueError("retrieval_mode must be auto, all, or semantic.")
    topic_specific = is_topic_specific_query(query)
    return (
        topic_specific,
        "auto_focused_query" if topic_specific else "auto_holistic_week_query",
    )


def _resolve_topic_specific(retrieval_mode: str, query: str) -> bool:
    """Compatibility wrapper retained for callers of the previous helper."""

    topic_specific, _ = _resolve_retrieval_policy(retrieval_mode, query)
    return topic_specific


def select_research_evidence(
    entries: Sequence[DiaryEntryResponse],
    *,
    user_id: str,
    query: str,
    week_start: str,
    week_end: str,
    top_k: int,
    retrieval_mode: str,
    semantic_retriever: Optional[SemanticRetriever] = None,
) -> tuple[List[dict], Dict[str, Any]]:
    """Retrieve a complete week or focused same-week semantic evidence."""

    topic_specific, resolution_reason = _resolve_retrieval_policy(
        retrieval_mode,
        query,
    )
    retrieval_strategy = "semantic_top_k" if topic_specific else "complete_week"
    coverage_target = None if topic_specific else 1.0
    coverage_target_description = (
        "query-relevant evidence, limited by top_k"
        if topic_specific
        else "100% of the canonical entries in the requested week"
    )
    if topic_specific:
        retriever = semantic_retriever or retrieve_weekly_evidence
        arguments = dict(
            user_id=user_id,
            query=query,
            week_start=week_start,
            week_end=week_end,
            top_k=top_k,
        )
        if retriever is retrieve_weekly_evidence:
            arguments["topic_specific"] = True
        try:
            retrieved = retriever(entries, **arguments)
        except Exception as error:
            return [], {
                "status": "unavailable",
                "failure_reason": f"retrieval_failed:{type(error).__name__}",
                "retrieval_mode": "semantic_week",
                "requested_retrieval_mode": retrieval_mode,
                "retrieval_strategy": retrieval_strategy,
                "strategy_resolution_reason": resolution_reason,
                "coverage_target": coverage_target,
                "coverage_target_description": coverage_target_description,
                "coverage_target_met": None,
                "full_week_coverage_required": False,
                "weekly_entry_count": len(entries),
                "retrieved_evidence_count": None,
                "retrieved_evidence_ids": [],
                "retrieval_coverage": None,
                "top_k": top_k,
                "comparison_eligible": False,
                "comparison_reason": "Same-week Chroma retrieval was unavailable.",
            }
    else:
        retrieved = build_general_week_evidence(
            entries,
            user_id=user_id,
            week_start=week_start,
            week_end=week_end,
        )

    ids = _evidence_ids(retrieved)
    retrieval_coverage = calculate_retrieval_coverage(
        ids,
        [entry.evidence_id for entry in entries],
    )
    coverage_target_met = (
        retrieval_coverage == coverage_target
        if coverage_target is not None
        else None
    )
    comparison_eligible = bool(ids) and coverage_target_met is not False
    if not ids:
        comparison_reason = "Retrieval did not return any canonical weekly activity."
    elif coverage_target_met is False:
        comparison_reason = "Complete-week retrieval did not meet its coverage target."
    else:
        comparison_reason = None
    return retrieved, {
        "status": "available",
        "retrieval_mode": "chroma_semantic_week" if topic_specific else "all_week",
        "requested_retrieval_mode": retrieval_mode,
        "retrieval_strategy": retrieval_strategy,
        "strategy_resolution_reason": resolution_reason,
        "coverage_target": coverage_target,
        "coverage_target_description": coverage_target_description,
        "coverage_target_met": coverage_target_met,
        "full_week_coverage_required": not topic_specific,
        "weekly_entry_count": len(entries),
        "retrieved_evidence_count": len(ids),
        "retrieved_evidence_ids": ids,
        "retrieval_coverage": retrieval_coverage,
        "top_k": top_k if topic_specific else None,
        "comparison_eligible": comparison_eligible,
        "comparison_reason": comparison_reason,
    }


def run_plain_condition(
    entries: List[DiaryEntryResponse],
    *,
    user_id: str,
    query: str,
    week_start: str,
    week_end: str,
    reference_summary: Optional[str] = None,
    nli_runner: Optional[Callable[..., Any]] = None,
) -> Dict[str, Any]:
    """Generate the baseline from unranked current-week entries."""

    started = time.perf_counter()
    try:
        generated = generate_plain_slm_summary_result(entries, query)
    except GenerationFailure as error:
        return {
            "condition": "plain_slm",
            "status": error.metadata.get("status", "generation_failed"),
            "failure_reason": error.reason,
            "summary_text": "",
            "generation": error.metadata,
            "generation_latency_ms": error.metadata.get("latency_ms"),
            "evaluation": _unavailable_evaluation("Plain generation failed."),
            "metrics": _not_applicable_reference_metrics("Plain generation failed."),
            "source_entry_count": len(entries),
            "latency_ms": round((time.perf_counter() - started) * 1000, 3),
        }

    evaluation = evaluate_plain_summary_groundedness(
        generated.text,
        entries,
        user_id=user_id,
        week_start=week_start,
        week_end=week_end,
        nli_runner=nli_runner,
    )
    grounded_rate = evaluation.get("grounded_claim_rate")
    if evaluation.get("status") != "available":
        condition_status = "evaluation_unavailable"
        failure_reason = "nli_evaluation_unavailable"
    elif grounded_rate == 0:
        condition_status = "unsupported_output"
        failure_reason = "no_generated_claim_was_supported"
    else:
        condition_status = "success"
        failure_reason = None
    return {
        "condition": "plain_slm",
        "status": condition_status,
        "failure_reason": failure_reason,
        "summary_text": generated.text,
        "generation": generated.metadata,
        "generation_latency_ms": generated.metadata.get("latency_ms"),
        "evaluation": evaluation,
        "metrics": _reference_metrics(generated.text, reference_summary),
        "source_entry_count": len(entries),
        "latency_ms": round((time.perf_counter() - started) * 1000, 3),
    }


def run_rag_condition(
    entries: List[DiaryEntryResponse],
    retrieved_evidence: List[Dict[str, Any]],
    retrieval: Dict[str, Any],
    *,
    user_id: str,
    query: str,
    week_start: str,
    week_end: str,
    reference_summary: Optional[str] = None,
    nli_runner: Optional[Callable[..., Any]] = None,
) -> Dict[str, Any]:
    """Generate cited RAG output and report faithfulness plus evidence coverage."""

    started = time.perf_counter()
    if retrieval.get("status") != "available":
        return {
            "condition": "rag_slm",
            "status": "retrieval_failed",
            "failure_reason": retrieval.get("failure_reason") or "retrieval_unavailable",
            "raw_output": "",
            "summary_points": [],
            "generation": {
                "status": "not_run",
                "failure_reason": "retrieval_unavailable",
                "model_name": GENERATION_SETTINGS.model_name,
                "model_revision": GENERATION_SETTINGS.model_revision,
                "latency_ms": None,
            },
            "generation_latency_ms": None,
            "parsing": {"status": "not_run", "failure_reason": "retrieval_unavailable"},
            "evaluation": _unavailable_evaluation("Same-week Chroma retrieval failed."),
            "metrics": _not_applicable_reference_metrics("Same-week Chroma retrieval failed."),
            "retrieval": dict(retrieval),
            "latency_ms": round((time.perf_counter() - started) * 1000, 3),
        }

    try:
        full_week_coverage_required = bool(
            retrieval.get("full_week_coverage_required")
        )
        generated = generate_rag_slm_summary(
            retrieved_evidence,
            query,
            require_full_coverage=full_week_coverage_required,
            repair_missing_coverage=full_week_coverage_required,
        )
    except GenerationFailure as error:
        return {
            "condition": "rag_slm",
            "status": error.metadata.get("status", "generation_failed"),
            "failure_reason": error.reason,
            "raw_output": "",
            "summary_points": [],
            "generation": error.metadata,
            "generation_latency_ms": error.metadata.get("latency_ms"),
            "parsing": {"status": "not_run", "failure_reason": "generation_failed"},
            "evaluation": _unavailable_evaluation("RAG generation failed."),
            "metrics": _not_applicable_reference_metrics("RAG generation failed."),
            "retrieval": dict(retrieval),
            "latency_ms": round((time.perf_counter() - started) * 1000, 3),
        }
    except RagParsingFailure as error:
        return {
            "condition": "rag_slm",
            "status": "parsing_failed",
            "failure_reason": error.reason,
            "raw_output": error.raw_text,
            "summary_points": [],
            "generation": error.metadata or {},
            "generation_latency_ms": (
                error.metadata.get("latency_ms") if error.metadata else None
            ),
            "parsing": {"status": "parsing_failed", "failure_reason": error.reason},
            "evaluation": _unavailable_evaluation("RAG output parsing failed."),
            "metrics": _not_applicable_reference_metrics("RAG output parsing failed."),
            "retrieval": dict(retrieval),
            "latency_ms": round((time.perf_counter() - started) * 1000, 3),
        }

    retrieved_id_list = _evidence_ids(retrieved_evidence)
    retrieved_ids = set(retrieved_id_list)
    weekly_ids = list(dict.fromkeys(entry.evidence_id for entry in entries))
    weekly_id_set = set(weekly_ids)
    summary_points = list(generated.summary_points)
    raw_outputs = [generated.raw_text]
    generation = dict(generated.metadata)
    parsing = dict(generated.parsing)

    evaluation = evaluate_rag_summary_groundedness(
        summary_points,
        entries,
        user_id=user_id,
        week_start=week_start,
        week_end=week_end,
        nli_runner=nli_runner,
        allowed_evidence_ids=retrieved_id_list,
    )

    # Repair only contradicted/unsupported points against their own cited
    # evidence. This avoids cross-entry fact mixing while keeping the output
    # model-generated.
    repair_calls: List[Dict[str, Any]] = []
    if evaluation.get("status") == "available":
        claims_by_id: Dict[str, List[Dict[str, Any]]] = {}
        for claim in evaluation.get("per_claim", []):
            claim_id = str(claim.get("claim_id") or "").strip()
            if claim_id and claim.get("classification") != "entailed":
                claims_by_id.setdefault(claim_id, []).append(claim)

        evidence_by_id = {
            str(item.get("evidence_id") or "").strip(): item
            for item in retrieved_evidence
        }
        repaired_by_claim_id: Dict[str, List[Dict[str, Any]]] = {}
        for claim_id, claims in claims_by_id.items():
            evidence_ids = list(
                dict.fromkeys(
                    str(evidence_id).strip()
                    for claim in claims
                    for evidence_id in claim.get("valid_evidence_ids", [])
                    if str(evidence_id).strip() in evidence_by_id
                )
            )
            repair_evidence = [evidence_by_id[evidence_id] for evidence_id in evidence_ids]
            if not repair_evidence:
                continue
            try:
                repaired = regenerate_unsupported_rag_claims(
                    repair_evidence,
                    query,
                    [str(claim.get("claim") or "") for claim in claims],
                )
            except (GenerationFailure, RagParsingFailure):
                continue
            repaired_by_claim_id[claim_id] = repaired.summary_points
            raw_outputs.append(repaired.raw_text)
            repair_calls.append(repaired.metadata)

        if repaired_by_claim_id:
            repaired_points: List[Dict[str, Any]] = []
            for point in summary_points:
                claim_id = str(point.get("claim_id") or "").strip()
                repaired_points.extend(repaired_by_claim_id.get(claim_id, [point]))
            summary_points = repaired_points
            _renumber_summary_points(summary_points)
            evaluation = evaluate_rag_summary_groundedness(
                summary_points,
                entries,
                user_id=user_id,
                week_start=week_start,
                week_end=week_end,
                nli_runner=nli_runner,
                allowed_evidence_ids=retrieved_id_list,
            )

    repair_latency_ms = sum(
        float(call.get("latency_ms") or 0) for call in repair_calls
    )
    generation["latency_ms"] = round(
        float(generation.get("latency_ms") or 0) + repair_latency_ms,
        3,
    )
    generation["unsupported_repair_count"] = len(repair_calls)
    generation["unsupported_repair_calls"] = repair_calls
    summary_text = _summary_points_to_text(summary_points)
    cited_ids = list(
        dict.fromkeys(
            str(citation.get("evidence_id") or "").strip()
            for point in summary_points
            for citation in point.get("citations") or []
            if citation.get("is_valid") is not False
            and str(citation.get("evidence_id") or "").strip() in retrieved_ids
            and str(citation.get("evidence_id") or "").strip() in weekly_id_set
        )
    )
    evaluated_represented_ids = _entailed_evidence_ids(evaluation)
    represented_ids = (
        [
            evidence_id
            for evidence_id in evaluated_represented_ids
            if evidence_id in retrieved_ids and evidence_id in weekly_id_set
        ]
        if evaluated_represented_ids is not None
        else None
    )
    if represented_ids is not None:
        represented_ids = list(dict.fromkeys(represented_ids))
    representation_coverage = (
        round(len(represented_ids) / len(retrieved_ids), 4)
        if retrieved_ids and represented_ids is not None
        else None
    )
    answer_coverage = (
        round(len(represented_ids) / len(weekly_ids), 4)
        if weekly_ids and represented_ids is not None
        else None
    )
    citation_coverage = (
        round(len(cited_ids) / len(weekly_ids), 4)
        if weekly_ids
        else None
    )
    retrieval.update(
        cited_entry_count=len(cited_ids),
        cited_evidence_ids=cited_ids,
        citation_coverage=citation_coverage,
        represented_entry_count=(
            len(represented_ids) if represented_ids is not None else None
        ),
        represented_evidence_ids=represented_ids or [],
        representation_coverage=representation_coverage,
        answer_coverage=answer_coverage,
        generation_coverage_target_met=(
            answer_coverage == 1.0
            if retrieval.get("full_week_coverage_required")
            and answer_coverage is not None
            else None
        ),
    )
    parsing.update(
        claim_count=len(summary_points),
        display_point_count=len(summary_points),
        represented_evidence_ids=cited_ids,
        missing_evidence_ids=[
            evidence_id for evidence_id in retrieved_id_list if evidence_id not in cited_ids
        ],
        unsupported_repair_count=len(repair_calls),
    )
    grounded_rate = evaluation.get("grounded_claim_rate")
    if evaluation.get("status") != "available":
        condition_status = "evaluation_unavailable"
        failure_reason = "nli_evaluation_unavailable"
    elif grounded_rate != 1.0:
        condition_status = "unsupported_output"
        failure_reason = "one_or_more_generated_claims_were_unsupported"
    elif full_week_coverage_required and answer_coverage != 1.0:
        condition_status = "incomplete_coverage"
        failure_reason = "not_all_weekly_entries_were_supported"
    else:
        condition_status = "success"
        failure_reason = None
    return {
        "condition": "rag_slm",
        "status": condition_status,
        "failure_reason": failure_reason,
        "raw_output": "\n".join(raw_outputs),
        "summary_text": summary_text,
        "summary_points": summary_points,
        "generation": generation,
        "generation_latency_ms": generation.get("latency_ms"),
        "parsing": parsing,
        "evaluation": evaluation,
        "metrics": _reference_metrics(summary_text, reference_summary),
        "retrieval": dict(retrieval),
        "latency_ms": round((time.perf_counter() - started) * 1000, 3),
    }


def _current_week_context(
    entries: Sequence[DiaryEntryResponse],
    *,
    user_id: str,
    week_start: str,
    week_end: str,
) -> List[dict]:
    output = []
    for item in build_general_week_evidence(
        entries,
        user_id=user_id,
        week_start=week_start,
        week_end=week_end,
    ):
        current = dict(item)
        current["context_role"] = "current_week"
        current["retrieval_method"] = "current_week_all"
        output.append(current)
    return output


def _comparison_result(
    plain: Dict[str, Any],
    rag: Dict[str, Any],
    retrieval: Dict[str, Any],
    reference_summary: Optional[str],
) -> Dict[str, Any]:
    ready = (
        plain.get("status") == "success"
        and rag.get("status") == "success"
        and retrieval.get("comparison_eligible") is True
    )
    if retrieval.get("retrieval_strategy") == "complete_week":
        rag_input = "complete canonical week selected by query-aware retrieval"
    else:
        rag_input = "same-week activities selected by Chroma semantic top-k retrieval"

    return {
        "status": "ready_for_evaluation" if ready else "not_comparable",
        "hypothesis": (
            "A query-aware same-week retrieval and cited grounding pipeline reduces "
            "unsupported claims without sacrificing answer coverage."
        ),
        "comparison_type": "plain_generation_system_vs_grounded_rag_system",
        "plain_input": "all weekly activities serialized as plain text",
        "rag_input": rag_input,
        "reference_available": bool(reference_summary and reference_summary.strip()),
        "primary_evaluation": [
            "NLI grounded-statement rate",
            "NLI estimated unsupported-statement rate",
            "retrieval coverage",
            "answer evidence coverage",
        ],
        "secondary_evaluation": [
            "blinded human factual-accuracy rating",
            "BERTScore and ROUGE-L when a human reference is supplied",
        ],
        "reason": None if ready else retrieval.get("comparison_reason"),
    }


def run_summarization_experiment(
    entries: List[DiaryEntryResponse],
    user_id: str,
    query: str,
    week_start: str,
    week_end: str,
    top_k: int = 8,
    retrieval_mode: str = "auto",
    reference_summary: Optional[str] = None,
    *,
    semantic_retriever: Optional[SemanticRetriever] = None,
    nli_runner: Optional[Callable[..., Any]] = None,
) -> Dict[str, Any]:
    """Run the two-condition paired experiment over one user/week/query case."""

    experiment_started = time.perf_counter()
    resolved_start, resolved_end = validate_week_range(week_start, week_end)
    if not user_id or not user_id.strip():
        raise ValueError("user_id cannot be empty.")
    if not query or not query.strip():
        raise ValueError("query cannot be empty.")

    plain = run_plain_condition(
        entries,
        user_id=user_id,
        query=query,
        week_start=resolved_start,
        week_end=resolved_end,
        reference_summary=reference_summary,
        nli_runner=nli_runner,
    )
    retrieved_evidence, retrieval = select_research_evidence(
        entries,
        user_id=user_id,
        query=query,
        week_start=resolved_start,
        week_end=resolved_end,
        top_k=top_k,
        retrieval_mode=retrieval_mode,
        semantic_retriever=semantic_retriever,
    )
    rag = run_rag_condition(
        entries,
        retrieved_evidence,
        retrieval,
        user_id=user_id,
        query=query,
        week_start=resolved_start,
        week_end=resolved_end,
        reference_summary=reference_summary,
        nli_runner=nli_runner,
    )
    comparison = _comparison_result(plain, rag, retrieval, reference_summary)

    return {
        "schema_version": SUMMARY_SCHEMA_VERSION,
        "user_id": user_id,
        "query": query,
        "week_start": resolved_start,
        "week_end": resolved_end,
        "retrieval": retrieval,
        "plain_slm": plain,
        "rag": rag,
        "comparison": comparison,
        "controlled_variables": {
            "generator_model": GENERATION_SETTINGS.model_name,
            "generator_revision": GENERATION_SETTINGS.model_revision,
            "decoding_parameters": {
                "max_new_tokens": GENERATION_SETTINGS.max_new_tokens,
                "do_sample": GENERATION_SETTINGS.do_sample,
                "num_beams": GENERATION_SETTINGS.num_beams,
            },
            "max_input_tokens": GENERATION_SETTINGS.max_input_tokens,
            "random_seed": GENERATION_SETTINGS.random_seed,
            "same_model_instance": True,
            "same_query": True,
            "same_current_week_source_pool": True,
            "differences": {
                "plain": "complete week serialized as ordinary text without citations",
                "rag": (
                    "query-aware same-week evidence with source attribution; "
                    f"resolved strategy: {retrieval.get('retrieval_strategy')}"
                ),
            },
        },
        "execution_time_ms": round((time.perf_counter() - experiment_started) * 1000, 3),
    }


def load_user_week_entries(
    user_id: str,
    week_start: Optional[str],
    week_end: Optional[str],
) -> tuple[str, str, List[DiaryEntryResponse]]:
    resolved_start, resolved_end = validate_week_range(week_start, week_end)
    raw_entries = list_diary_entries_for_week(
        user_id=user_id,
        week_start=resolved_start,
        week_end=resolved_end,
        limit=None,
    )
    entries = [DiaryEntryResponse(**entry) for entry in raw_entries]
    return resolved_start, resolved_end, entries


def run_user_week_experiment(
    *,
    user_id: str,
    query: str,
    week_start: Optional[str],
    week_end: Optional[str],
    top_k: int,
    retrieval_mode: str,
    reference_summary: Optional[str] = None,
) -> tuple[str, str, List[DiaryEntryResponse], Dict[str, Any]]:
    resolved_start, resolved_end, entries = load_user_week_entries(
        user_id,
        week_start,
        week_end,
    )
    experiment = run_summarization_experiment(
        entries,
        user_id,
        query,
        resolved_start,
        resolved_end,
        top_k=top_k,
        retrieval_mode=retrieval_mode,
        reference_summary=reference_summary,
    )
    return resolved_start, resolved_end, entries, experiment


def _empty_feedback() -> Dict[str, Any]:
    message = (
        "No diary entries were found for this week. Add a diary entry before "
        "requesting a weekly reflection."
    )
    return {
        "feedback_type": "wellbeing_productivity",
        "mood_signal": "unknown",
        "productivity_signal": "unknown",
        "message": message,
        "action": "Record an activity before generating another weekly summary.",
        "evidence_ids": [],
        "based_on_evidence_ids": [],
        "abstained": True,
        "generation_method": "rule_based",
        "fallback_reason": "no_weekly_entries",
    }


def _empty_experiment(
    *,
    user_id: str,
    query: str,
    week_start: str,
    week_end: str,
    retrieval_mode: str,
) -> Dict[str, Any]:
    generation = {
        "status": "not_applicable",
        "failure_reason": "no_weekly_entries",
        "model_name": GENERATION_SETTINGS.model_name,
        "model_revision": GENERATION_SETTINGS.model_revision,
        "decoding_parameters": {
            "max_new_tokens": GENERATION_SETTINGS.max_new_tokens,
            "do_sample": GENERATION_SETTINGS.do_sample,
            "num_beams": GENERATION_SETTINGS.num_beams,
        },
        "max_input_tokens": GENERATION_SETTINGS.max_input_tokens,
        "random_seed": GENERATION_SETTINGS.random_seed,
        "latency_ms": None,
        "batch_count": 0,
    }
    unavailable = _unavailable_evaluation("No diary entries were available.")
    metrics = _not_applicable_reference_metrics("No diary entries were available.")
    topic_specific, resolution_reason = _resolve_retrieval_policy(
        retrieval_mode,
        query,
    )
    retrieval_strategy = "semantic_top_k" if topic_specific else "complete_week"
    retrieval = {
        "status": "not_applicable",
        "retrieval_mode": (
            "chroma_semantic_week" if topic_specific else "all_week"
        ),
        "requested_retrieval_mode": retrieval_mode,
        "retrieval_strategy": retrieval_strategy,
        "strategy_resolution_reason": resolution_reason,
        "coverage_target": None if topic_specific else 1.0,
        "coverage_target_description": (
            "query-relevant evidence, limited by top_k"
            if topic_specific
            else "100% of the canonical entries in the requested week"
        ),
        "coverage_target_met": None,
        "full_week_coverage_required": not topic_specific,
        "weekly_entry_count": 0,
        "retrieved_evidence_count": 0,
        "retrieved_evidence_ids": [],
        "retrieval_coverage": None,
        "comparison_eligible": False,
        "comparison_reason": "The requested week contains no diary entries.",
    }
    return {
        "schema_version": SUMMARY_SCHEMA_VERSION,
        "user_id": user_id,
        "query": query,
        "week_start": week_start,
        "week_end": week_end,
        "retrieval": retrieval,
        "plain_slm": {
            "condition": "plain_slm",
            "status": "not_applicable",
            "failure_reason": "no_weekly_entries",
            "summary_text": "",
            "generation": generation,
            "evaluation": unavailable,
            "metrics": metrics,
        },
        "rag": {
            "condition": "rag_slm",
            "status": "not_applicable",
            "failure_reason": "no_weekly_entries",
            "summary_text": "",
            "raw_output": "",
            "summary_points": [],
            "generation": generation,
            "evaluation": unavailable,
            "metrics": metrics,
            "retrieval": retrieval,
        },
        "comparison": {
            "status": "not_comparable",
            "reason": retrieval["comparison_reason"],
        },
        "controlled_variables": {
            "generator_model": GENERATION_SETTINGS.model_name,
            "generator_revision": GENERATION_SETTINGS.model_revision,
            "decoding_parameters": generation["decoding_parameters"],
            "max_input_tokens": GENERATION_SETTINGS.max_input_tokens,
            "random_seed": GENERATION_SETTINGS.random_seed,
            "same_model_instance": True,
            "same_query": True,
            "same_current_week_source_pool": True,
            "differences": {
                "plain": "complete week serialized as ordinary text without citations",
                "rag": (
                    "query-aware same-week evidence with source attribution; "
                    f"resolved strategy: {retrieval_strategy}"
                ),
            },
        },
        "execution_time_ms": None,
    }


def _supported_rag_display_points(rag: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Return only RAG points whose generated claims are supported."""

    points = list(rag.get("summary_points") or [])
    claims = rag.get("evaluation", {}).get("per_claim")
    if not isinstance(claims, list):
        return []

    claims_by_id: Dict[str, List[Dict[str, Any]]] = {}
    for claim in claims:
        if not isinstance(claim, dict):
            continue
        claim_id = str(claim.get("claim_id") or "").strip()
        if claim_id:
            claims_by_id.setdefault(claim_id, []).append(claim)

    supported: List[Dict[str, Any]] = []
    for index, point in enumerate(points):
        claim_id = str(point.get("claim_id") or "").strip()
        matching = claims_by_id.get(claim_id)
        if matching is not None:
            is_entailed = bool(matching) and all(
                claim.get("classification") == "entailed"
                for claim in matching
            )
        else:
            is_entailed = (
                len(claims) == len(points)
                and isinstance(claims[index], dict)
                and claims[index].get("classification") == "entailed"
            )
        if is_entailed:
            supported.append(point)
    return supported


def generate_weekly_summary(request: WeeklySummaryRequest) -> WeeklySummaryResponse:
    request_data = _model_to_dict(request)
    user_id = str(request_data["user_id"]).strip()
    if not user_id:
        raise ValueError("user_id cannot be empty.")

    resolved_start, resolved_end, entries = load_user_week_entries(
        user_id,
        request_data.get("week_start"),
        request_data.get("week_end"),
    )

    if entries:
        experiment = run_summarization_experiment(
            entries,
            user_id,
            request_data["query"],
            resolved_start,
            resolved_end,
            top_k=request_data["top_k"],
            retrieval_mode=request_data.get("retrieval_mode", "auto"),
            reference_summary=request_data.get("reference_summary"),
        )
        rag = experiment["rag"]
        summary_points = _supported_rag_display_points(rag)
        rag["display_summary_points"] = summary_points
        displayed_condition = "rag"

        displayed_evaluation = rag.get("evaluation", {})

        current_evidence = _current_week_context(
            entries,
            user_id=user_id,
            week_start=resolved_start,
            week_end=resolved_end,
        )
        feedback = generate_feedback_from_rag_evidence(
            retrieved_entries=entries,
            retrieved_evidence=current_evidence,
            use_slm=bool(request_data.get("enable_slm_feedback", False)),
        )
    else:
        experiment = _empty_experiment(
            user_id=user_id,
            query=request_data["query"],
            week_start=resolved_start,
            week_end=resolved_end,
            retrieval_mode=request_data.get("retrieval_mode", "auto"),
        )
        summary_points = []
        displayed_condition = "none"
        displayed_evaluation = {}
        feedback = _empty_feedback()

    summary_id = str(uuid4())
    additional_data = {
        **experiment,
        "displayed_condition": displayed_condition,
        "feedback": feedback,
    }
    response = WeeklySummaryResponse(
        user_id=user_id,
        week_start=resolved_start,
        week_end=resolved_end,
        saved_summary_id=summary_id,
        query=request_data["query"],
        summary_type="weekly_plain_vs_traceable_rag",
        summary_points=summary_points,
        hallucination_score=displayed_evaluation.get("hallucination_score"),
        unsupported_claim_rate=displayed_evaluation.get("unsupported_claim_rate"),
        grounded_claim_rate=displayed_evaluation.get("grounded_claim_rate"),
        citation_precision=displayed_evaluation.get("citation_precision"),
        citation_completeness=displayed_evaluation.get("citation_completeness"),
        feedback=feedback,
        additional_data=additional_data,
    )
    response_data = response.model_dump() if hasattr(response, "model_dump") else response.dict()
    save_summary(
        user_id=user_id,
        summary_id=summary_id,
        summary_data={
            **response_data,
            "schema_version": SUMMARY_SCHEMA_VERSION,
            "generated_at": utc_now_iso(),
        },
    )
    return response
