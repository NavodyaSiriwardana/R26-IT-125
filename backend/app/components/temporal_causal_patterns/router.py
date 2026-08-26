from fastapi import APIRouter, HTTPException
from app.components.temporal_causal_patterns.models import (
    DiaryEntryRequest,
    DiaryEntryResponse,
    AnalyseResponse,
    GetPatternsResponse,
    PatternResult,
)
from app.components.temporal_causal_patterns.graph_builder import graph_builder
from app.components.temporal_causal_patterns.pattern_engine import pattern_engine

router = APIRouter(
    prefix="/temporal-patterns",
    tags=["Temporal Causal Patterns"],
)


# ─────────────────────────────────────────────
# ENDPOINT 1 — INSERT DIARY ENTRY
# ─────────────────────────────────────────────

@router.post(
    "/diary/entry",
    response_model=DiaryEntryResponse,
    summary="Insert diary template entry into user graph",
)
def insert_diary_entry(request: DiaryEntryRequest):
    """
    Receives diary template data from frontend.
    userId is automatically attached from localStorage.
    Creates user-specific graph in Neo4j AuraDB.
    All nodes and relationships carry full metadata.
    """
    try:
        result = graph_builder.insert_diary_entry(request.dict())
        return DiaryEntryResponse(
            entryId = result["entryId"],
            userId  = result["userId"],
            status  = "success",
            message = f"Diary entry inserted successfully into user graph for {result['userId']}",
        )
    except Exception as e:
        print(f"[Router] ERROR inserting diary entry: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to insert diary entry: {str(e)}"
        )
#bulck insert endpoint can be added later for testing with large datasets, but for now we focus on single entry insertion and pattern analysis.
@router.post(
    "/diary/bulk-entry",
    summary="Insert multiple diary entries at once",
)
def insert_bulk_diary_entries(request: list[DiaryEntryRequest]):
    """
    Accepts a JSON array of diary entries.
    Inserts all entries one by one into AuraDB.
    """
    results = []
    failed  = []

    for entry in request:
        try:
            result = graph_builder.insert_diary_entry(entry.dict())
            results.append(result)
        except Exception as e:
            failed.append({
                "entry" : entry.dict(),
                "error" : str(e)
            })

    return {
        "totalReceived" : len(request),
        "totalInserted" : len(results),
        "totalFailed"   : len(failed),
        "inserted"      : results,
        "failed"        : failed,
    }



# ─────────────────────────────────────────────
# ENDPOINT 2 — ANALYSE PATTERNS
# ─────────────────────────────────────────────

@router.post(
    "/analyse/{userId}",
    response_model=AnalyseResponse,
    summary="Automatically detect behavioral patterns for a user",
)
def analyse_patterns(userId: str):
    """
    userId is automatically filled from localStorage
    when user clicks Analyse My Patterns button.
    Fetches user graph from AuraDB.
    Runs trigger-outcome frequency counting in Python.
    Returns explainable pattern insights.
    """
    try:
        if not userId:
            raise HTTPException(
                status_code=400,
                detail="userId is required"
            )

        # Run pattern detection
        patterns = pattern_engine.analyse(userId)

        if not patterns:
            return AnalyseResponse(
                userId             = userId,
                totalPatternsFound = 0,
                patterns           = [],
                message            = "No patterns found. Add more diary entries to discover patterns.",
            )

        # Convert to PatternResult models
        pattern_results = [
            PatternResult(
                insightText          = p["insightText"],
                trigger              = p["trigger"],
                outcome              = p["outcome"],
                matchedCount         = p["matchedCount"],
                totalTriggerCount    = p["totalTriggerCount"],
                confidencePercentage = p["confidencePercentage"],
                patternLevel         = p["patternLevel"],
                evidenceDates        = p["evidenceDates"],
            )
            for p in patterns
        ]

        # Save detected patterns to AuraDB as PatternInsight nodes
        graph_builder.save_pattern_insights(userId, patterns)

        return AnalyseResponse(
            userId             = userId,
            totalPatternsFound = len(pattern_results),
            patterns           = pattern_results,
            message            = f"Successfully detected {len(pattern_results)} pattern(s) for user {userId}",
        )

    except HTTPException:
        raise
    except Exception as e:
        print(f"[Router] ERROR analysing patterns: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to analyse patterns: {str(e)}"
        )


# ─────────────────────────────────────────────
# ENDPOINT 3 — GET USER DIARY INFO
# ─────────────────────────────────────────────

@router.get(
    "/entries/{userId}",
    response_model=GetPatternsResponse,
    summary="Get diary entry count for a user",
)
def get_user_entries(userId: str):
    """
    Returns total diary entries stored in
    AuraDB graph for the given user.
    """
    try:
        entries = graph_builder.fetch_user_diary_data(userId)
        return GetPatternsResponse(
            userId       = userId,
            totalEntries = len(entries),
            message      = f"User {userId} has {len(entries)} diary entries in the graph",
        )
    except Exception as e:
        print(f"[Router] ERROR fetching entries: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to fetch entries: {str(e)}"
        )

# ─────────────────────────────────────────────
# ENDPOINT — GET SAVED PATTERNS FROM GRAPH
# ─────────────────────────────────────────────

@router.get(
    "/patterns/{userId}",
    summary="Get saved PatternInsight nodes from AuraDB for a user",
)
def get_saved_patterns(userId: str):
    """
    Returns all PatternInsight nodes saved
    in AuraDB for the given user.
    Each pattern is linked to evidence
    diary entries via SUPPORTED_BY edges.
    """
    try:
        patterns = graph_builder.fetch_user_patterns(userId)

        if not patterns:
            return {
                "userId"        : userId,
                "totalPatterns" : 0,
                "patterns"      : [],
                "message"       : f"No saved patterns found for user {userId}. Run analyse first.",
            }

        return {
            "userId"        : userId,
            "totalPatterns" : len(patterns),
            "patterns"      : patterns,
            "message"       : f"Found {len(patterns)} saved pattern(s) for user {userId}",
        }

    except Exception as e:
        print(f"[Router] ERROR fetching saved patterns: {e}")
        raise HTTPException(
            status_code = 500,
            detail      = f"Failed to fetch saved patterns: {str(e)}"
        )