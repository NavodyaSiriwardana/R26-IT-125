from datetime import datetime
from typing import Optional, List, Dict, Any, Literal
from pydantic import AliasChoices, BaseModel, ConfigDict, Field



class DiaryEntryCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    user_id: str = Field(
        ...,
        validation_alias=AliasChoices("user_id", "userId"),
        examples=["demo-user-001"],
    )

    activity_name: str = Field(
        ...,
        validation_alias=AliasChoices("activity_name", "activityName"),
        examples=["Database Assignment Work"],
    )
    activity_category: str = Field(
        ...,
        validation_alias=AliasChoices("activity_category", "activityCategory"),
        examples=["Study"],
    )

    start_time: str = Field(
        ...,
        validation_alias=AliasChoices("start_time", "startTime"),
        examples=["14:00"],
    )
    end_time: str = Field(
        ...,
        validation_alias=AliasChoices("end_time", "endTime"),
        examples=["16:00"],
    )
    duration: Optional[str] = Field(None, examples=["2h"])
    time_period: Optional[str] = Field(
        None,
        validation_alias=AliasChoices("time_period", "timePeriod"),
        examples=["Afternoon"],
    )

    productivity_level: str = Field(
        ...,
        validation_alias=AliasChoices("productivity_level", "productivityLevel"),
        examples=["Low"],
    )

    mood_before: str = Field(
        ...,
        validation_alias=AliasChoices("mood_before", "moodBefore"),
        examples=["Stressed"],
    )
    mood_after: str = Field(
        ...,
        validation_alias=AliasChoices("mood_after", "moodAfter"),
        examples=["Tired"],
    )

    task_outcome: str = Field(
        ...,
        validation_alias=AliasChoices("task_outcome", "taskOutcome"),
        examples=["Incomplete"],
    )

    specific_person: Optional[str] = Field(
        "",
        validation_alias=AliasChoices(
            "specific_person",
            "specificPerson",
            "person_names",
        ),
        examples=["Kasun"],
    )
    health_status: str = Field(
        default="Normal",
        validation_alias=AliasChoices("health_status", "healthStatus"),
        examples=["Tired"],
    )

    location_type: str = Field(
        ...,
        validation_alias=AliasChoices("location_type", "locationType", "location"),
        examples=["Home"],
    )
    custom_location: Optional[str] = Field(
        "",
        validation_alias=AliasChoices("custom_location", "customLocation"),
    )
    with_whom: str = Field(
        ...,
        validation_alias=AliasChoices("with_whom", "withWhom"),
        examples=["Alone"],
    )

    notes: Optional[str] = Field(
        None,
        examples=["I struggled to finish the database assignment and felt mentally drained."],
    )

    # Optional. If frontend does not send it, backend uses today's date.
    entry_date: Optional[str] = Field(
        None,
        validation_alias=AliasChoices("entry_date", "entryDate"),
        examples=["2026-05-06"],
    )


class DiaryEntryResponse(BaseModel):
    # The identifier is supplied from the Firestore document snapshot. Integer
    # values remain accepted for older in-memory/research callers.
    id: str | int
    user_id: str
    evidence_id: str

    activity_name: str
    activity_category: str

    start_time: str
    end_time: str
    duration: str = ""
    duration_minutes: int
    time_period: str = ""

    productivity_level: str

    mood_before: str
    mood_after: str

    task_outcome: str

    specific_person: str = ""
    # Compatibility projection for existing API consumers. It is populated
    # from specificPerson, never read from a Firestore person_names field.
    person_names: Optional[str] = None
    health_status: str

    location_type: str = ""
    custom_location: str = ""
    # Resolved display value derived from locationType/customLocation.
    location: str
    with_whom: str

    notes: Optional[str]

    entry_date: str
    week_start: str
    week_end: str

    created_at: Optional[datetime] = None
    # The final diary schema has no updatedAt field; retained only as an
    # optional API compatibility value.
    updated_at: Optional[datetime] = None


class ApiMessage(BaseModel):
    message: str


class SearchRequest(BaseModel):
    user_id: str = Field(..., examples=["demo-user-001"])
    query: str = Field(..., examples=["productive lecture with motivated mood"])
    top_k: int = Field(default=3, examples=[3])


class SearchResult(BaseModel):
    evidence_id: str
    content: str
    metadata: Dict[str, Any]
    similarity_score: float

class PlainSummaryRequest(BaseModel):
    user_id: str = Field(..., examples=["demo-user-001"])
    query: str = Field(
        default="Summarize my diary entries.",
        examples=["Summarize my productivity and mood today"],
    )
    week_start: Optional[str] = Field(None, examples=["2026-05-04"])
    week_end: Optional[str] = Field(None, examples=["2026-05-10"])
    reference_summary: Optional[str] = None
    # Retained for request compatibility. Research weekly runs do not truncate.
    max_entries: Optional[int] = Field(default=None, ge=1)


class PlainSummaryResponse(BaseModel):
    query: str
    summary_type: str
    summary_text: str
    source_entry_count: int
    status: str = "success"
    failure_reason: Optional[str] = None
    generation: Optional[Dict[str, Any]] = None
    evaluation: Optional[Dict[str, Any]] = None
    metrics: Optional[Dict[str, Any]] = None

class RagSummaryRequest(BaseModel):
    user_id: str = Field(..., examples=["demo-user-001"])
    query: str = Field(
        default="Summarize my diary entries.",
        examples=["Summarize my productivity and mood today"],
    )
    week_start: Optional[str] = Field(None, examples=["2026-05-04"])
    week_end: Optional[str] = Field(None, examples=["2026-05-10"])
    top_k: int = Field(default=8, ge=1, examples=[8])
    retrieval_mode: Literal["auto", "all", "semantic"] = "auto"
    reference_summary: Optional[str] = None


class Citation(BaseModel):
    citation_id: str
    evidence_id: str
    label: str
    source_preview: str
    source_type: str = "diary_entry"
    is_valid: bool = True
    validation_error: Optional[str] = None


class RagSummaryPoint(BaseModel):
    text: str
    citations: List[Citation]
    claim_id: Optional[str] = None


class RagSummaryResponse(BaseModel):
    query: str
    summary_type: str
    summary_points: List[RagSummaryPoint]
    retrieved_evidence_count: Optional[int]
    status: str = "success"
    failure_reason: Optional[str] = None
    weekly_entry_count: Optional[int] = None
    represented_entry_count: Optional[int] = None
    retrieval_coverage: Optional[float] = None
    answer_coverage: Optional[float] = None
    retrieved_evidence_ids: List[str] = Field(default_factory=list)
    represented_evidence_ids: List[str] = Field(default_factory=list)
    generation: Optional[Dict[str, Any]] = None
    evaluation: Optional[Dict[str, Any]] = None
    metrics: Optional[Dict[str, Any]] = None


# Stage 5 
class UnsupportedClaim(BaseModel):
    claim: str
    reason: str


class HallucinationEvaluation(BaseModel):
    """Compatibility schema; hallucination_score aliases unsupported rate."""

    hallucination_score: Optional[float] = None
    total_claims: int
    supported_claims: Optional[int] = None
    unsupported_claims: Optional[int] = None
    unsupported_claim_details: List[UnsupportedClaim]
    status: str = "available"
    grounded_claim_rate: Optional[float] = None
    unsupported_claim_rate: Optional[float] = None


class CompareSummaryRequest(BaseModel):
    user_id: str = Field(..., examples=["demo-user-001"])
    query: str = Field(
        default="Summarize my week and include relevant personal patterns.",
        examples=["Summarize my productivity and mood today"],
    )
    week_start: Optional[str] = Field(None, examples=["2026-05-04"])
    week_end: Optional[str] = Field(None, examples=["2026-05-10"])
    max_entries: Optional[int] = Field(default=None, ge=1)
    top_k: int = Field(default=8, ge=1, examples=[8])
    retrieval_mode: Literal["auto", "all", "semantic"] = "auto"
    reference_summary: Optional[str] = None

# Stage 6
class FeedbackResponse(BaseModel):
    feedback_type: str
    mood_signal: str
    productivity_signal: str
    message: str
    action: str = ""
    evidence_ids: List[str] = Field(default_factory=list)
    based_on_evidence_ids: List[str] = Field(default_factory=list)
    abstained: bool = False
    generation_method: str = "rule_based"
    fallback_reason: Optional[str] = None

class CompareSummaryResponse(BaseModel):
    query: str
    summary_type: str
    summary_points: List[RagSummaryPoint]
    # Legacy diagnostic fields retained so old saved summaries still decode.
    # New summaries leave them null; none of them gates or alters model output.
    hallucination_score: Optional[float] = None
    unsupported_claim_rate: Optional[float] = None
    grounded_claim_rate: Optional[float] = None
    citation_precision: Optional[float] = None
    citation_completeness: Optional[float] = None
    feedback: FeedbackResponse
    additional_data: Dict[str, Any]

class WeeklySummaryRequest(BaseModel):
    user_id: str = Field(..., examples=["demo-user-001"])
    query: str = Field(
        default="Summarize my productivity and mood for this week and give feedback.",
        examples=["Summarize my productivity and mood for this week and give feedback"],
    )

    # Optional. Backend calculates current week if not provided.
    week_start: Optional[str] = Field(None, examples=["2026-05-04"])
    week_end: Optional[str] = Field(None, examples=["2026-05-10"])

    # max_entries is deprecated and ignored by controlled weekly research runs.
    max_entries: Optional[int] = Field(default=None, ge=1)
    top_k: int = Field(default=8, ge=1, examples=[8])
    retrieval_mode: Literal["auto", "all", "semantic"] = "auto"
    reference_summary: Optional[str] = Field(
        None,
        description="Human-written reference used only for ROUGE-L/BERTScore.",
    )
    enable_slm_feedback: bool = False

class WeeklySummaryResponse(CompareSummaryResponse):
    user_id: str
    week_start: str
    week_end: str
    saved_summary_id: str


class DashboardOverview(BaseModel):
    """Transparent headline metrics for one Monday-to-Sunday week."""

    activity_count: int
    logged_minutes: int
    completion_rate: float
    mood_improved_rate: float


class DashboardDailyActivity(BaseModel):
    date: str
    day_label: str
    total_minutes: int
    entry_count: int


class DashboardCategoryBreakdown(BaseModel):
    category: str
    total_minutes: int
    entry_count: int
    percentage: float


class DashboardBreakdownItem(BaseModel):
    label: str
    count: int
    percentage: float


class DashboardOutcomeBreakdown(BaseModel):
    outcome: str
    count: int
    percentage: float


class DashboardMoodBreakdown(BaseModel):
    improved_count: int
    stable_count: int
    declined_count: int
    improved_percentage: float


class DashboardInsight(BaseModel):
    title: str
    message: str
    evidence_ids: List[str]
    sample_size: int


class DashboardLatestSummaryPreview(BaseModel):
    summary_id: str
    generated_at: str
    summary_text: str
    feedback_message: str
    grounded_claim_rate: Optional[float] = None
    unsupported_claim_rate: Optional[float] = None
    citation_precision: Optional[float] = None
    citation_completeness: Optional[float] = None
    retrieval_coverage: Optional[float] = None
    bertscore: Optional[float] = None
    rouge_l: Optional[float] = None
    generation_latency_ms: Optional[float] = None
    evaluation_status: str = "unavailable"
    # Deprecated legacy field. Never derive or use this for research claims.
    evidence_accuracy: Optional[float] = None


class DashboardResponse(BaseModel):
    user_id: str
    week_start: str
    week_end: str
    evidence_entry_count: int
    overview: DashboardOverview
    daily_activity: List[DashboardDailyActivity]
    category_breakdown: List[DashboardCategoryBreakdown]
    productivity_breakdown: List[DashboardBreakdownItem]
    mood_breakdown: DashboardMoodBreakdown
    outcome_breakdown: List[DashboardOutcomeBreakdown]
    insights: List[DashboardInsight]
    recent_entries: List[DiaryEntryResponse]
    latest_summary: Optional[DashboardLatestSummaryPreview]
