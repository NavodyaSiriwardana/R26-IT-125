"""User-scoped HTTP routes for diary evidence and summarization."""

from __future__ import annotations

import logging
from typing import List, Optional

from fastapi import APIRouter, HTTPException

from .chroma_store import search_diary_entries
from .dashboard_service import build_weekly_dashboard, get_latest_weekly_summary
from .diary_entry_service import (
    create_user_diary_entry,
    get_user_evidence_entry,
    list_user_diary_entries,
)
from .schemas import (
    ApiMessage,
    CompareSummaryRequest,
    CompareSummaryResponse,
    DashboardResponse,
    DiaryEntryCreate,
    DiaryEntryResponse,
    PlainSummaryRequest,
    PlainSummaryResponse,
    RagSummaryRequest,
    RagSummaryResponse,
    SearchRequest,
    SearchResult,
    WeeklySummaryRequest,
    WeeklySummaryResponse,
)
from .weekly_summary_service import (
    generate_weekly_summary,
    load_user_week_entries,
    run_plain_condition,
    run_user_week_experiment,
)


logger = logging.getLogger(__name__)

router = APIRouter(tags=["RAG Summary"])


def _server_error(operation: str, public_detail: str) -> HTTPException:
    # Do not emit exception strings: third-party errors can echo model prompts
    # or diary content. Structured operation IDs are safe for monitoring.
    logger.error("RAG summary operation failed: %s", operation)
    return HTTPException(status_code=500, detail=public_detail)


@router.post("/entries", response_model=DiaryEntryResponse)
def add_diary_entry(entry_data: DiaryEntryCreate):
    try:
        return create_user_diary_entry(entry_data)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error("add_diary_entry", "Failed to save the diary entry.") from error


@router.post("/search", response_model=List[SearchResult])
def search_entries(search_request: SearchRequest):
    try:
        return search_diary_entries(
            user_id=search_request.user_id,
            query=search_request.query,
            top_k=search_request.top_k,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error("search_entries", "Failed to search diary entries.") from error


@router.get("/entries", response_model=List[DiaryEntryResponse])
def get_diary_entries(user_id: str, limit: int = 50):
    try:
        return list_user_diary_entries(user_id=user_id, limit=limit)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error("get_diary_entries", "Failed to load diary entries.") from error


@router.get("/evidence/{evidence_id}", response_model=DiaryEntryResponse)
def get_evidence_entry(evidence_id: str, user_id: str):
    try:
        entry = get_user_evidence_entry(user_id=user_id, evidence_id=evidence_id)
    except Exception as error:
        raise _server_error("get_evidence_entry", "Failed to load the evidence entry.") from error
    if entry is None:
        raise HTTPException(status_code=404, detail="Evidence entry not found.")
    return entry


@router.post("/plain-summary", response_model=PlainSummaryResponse)
def generate_plain_summary(summary_request: PlainSummaryRequest):
    try:
        week_start, week_end, entries = load_user_week_entries(
            summary_request.user_id,
            summary_request.week_start,
            summary_request.week_end,
        )
        condition = run_plain_condition(
            entries,
            user_id=summary_request.user_id,
            query=summary_request.query,
            week_start=week_start,
            week_end=week_end,
            reference_summary=summary_request.reference_summary,
        )
        return PlainSummaryResponse(
            query=summary_request.query,
            summary_type="plain_slm",
            summary_text=condition.get("summary_text", ""),
            source_entry_count=len(entries),
            status=condition["status"],
            failure_reason=condition.get("failure_reason"),
            generation=condition.get("generation"),
            evaluation=condition.get("evaluation"),
            metrics=condition.get("metrics"),
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error("generate_plain_summary", "Failed to generate the plain summary.") from error


@router.post("/rag-summary", response_model=RagSummaryResponse)
def generate_rag_summary(summary_request: RagSummaryRequest):
    try:
        week_start, week_end, entries, experiment = run_user_week_experiment(
            user_id=summary_request.user_id,
            query=summary_request.query,
            week_start=summary_request.week_start,
            week_end=summary_request.week_end,
            top_k=summary_request.top_k,
            retrieval_mode=summary_request.retrieval_mode,
            reference_summary=summary_request.reference_summary,
        )
        condition = experiment["rag"]
        retrieval = experiment["retrieval"]
        return RagSummaryResponse(
            query=summary_request.query,
            summary_type="rag_slm",
            summary_points=condition.get("summary_points", []),
            retrieved_evidence_count=retrieval["retrieved_evidence_count"],
            weekly_entry_count=retrieval["weekly_entry_count"],
            represented_entry_count=retrieval.get("represented_entry_count"),
            retrieval_coverage=retrieval["retrieval_coverage"],
            answer_coverage=retrieval.get("answer_coverage"),
            retrieved_evidence_ids=retrieval["retrieved_evidence_ids"],
            represented_evidence_ids=retrieval.get(
                "represented_evidence_ids",
                [],
            ),
            status=condition["status"],
            failure_reason=condition.get("failure_reason"),
            generation=condition.get("generation"),
            evaluation=condition.get("evaluation"),
            metrics=condition.get("metrics"),
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error("generate_rag_summary", "Failed to generate the RAG summary.") from error


@router.post("/compare-summary", response_model=CompareSummaryResponse)
def compare_plain_and_rag_summary(summary_request: CompareSummaryRequest):
    """Compatibility route returning the two-condition weekly result."""

    try:
        weekly_request = WeeklySummaryRequest(
            user_id=summary_request.user_id,
            query=summary_request.query,
            week_start=summary_request.week_start,
            week_end=summary_request.week_end,
            top_k=summary_request.top_k,
            retrieval_mode=summary_request.retrieval_mode,
            reference_summary=summary_request.reference_summary,
        )
        return generate_weekly_summary(weekly_request)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error("compare_summaries", "Failed to compare summaries.") from error


@router.post("/weekly-summary", response_model=WeeklySummaryResponse)
def create_weekly_summary(summary_request: WeeklySummaryRequest):
    try:
        return generate_weekly_summary(summary_request)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error("create_weekly_summary", "Failed to generate the weekly summary.") from error


@router.get("/dashboard", response_model=DashboardResponse)
def get_dashboard(
    user_id: str,
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
):
    try:
        print(f"Fetching dashboard for user_id: {user_id}, week_start: {week_start}, week_end: {week_end}")
        return build_weekly_dashboard(
            user_id=user_id,
            week_start=week_start,
            week_end=week_end,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error("get_dashboard", "Failed to load the dashboard.") from error


@router.get("/weekly-summary/latest", response_model=WeeklySummaryResponse)
def get_latest_saved_weekly_summary(
    user_id: str,
    week_start: Optional[str] = None,
    week_end: Optional[str] = None,
):
    try:
        summary = get_latest_weekly_summary(
            user_id=user_id,
            week_start=week_start,
            week_end=week_end,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise _server_error(
            "get_latest_weekly_summary",
            "Failed to load the latest weekly summary.",
        ) from error
    if summary is None:
        raise HTTPException(
            status_code=404,
            detail="No saved summary was found for the requested week.",
        )
    return summary


@router.get("/health", response_model=ApiMessage)
def rag_summary_health_check():
    return ApiMessage(message="RAG Summary API is running.")
