from typing import Any

from fastapi import APIRouter, Body
from pydantic import BaseModel, Field

from app.components.task_prioritization.ranker import rank_tasks
from app.components.task_prioritization.score_predictor import predict_scores
from app.components.task_prioritization.scheduler import generate_schedule
from app.components.task_prioritization.reflection_generator import (
    generate_daily_reflection,
)

router = APIRouter()


# ── Request model for /predict-scores ───────────────────────────────────────

class PredictScoresRequest(BaseModel):
    title: str
    description: str = ""
    category: str
    start_time: str
    end_time: str
    task_duration: int
    estimated_duration_minutes: int


# ── Request model for /generate-schedule ────────────────────────────────────

class ScheduleRequest(BaseModel):
    schedule_date: str
    available_start: str
    available_end: str
    break_strategy: str = "adaptive"
    planning_mode: str = "include_upcoming"
    tasks: list[dict[str, Any]]


# ── Request model for /generate-reflection ──────────────────────────────────

class ReflectionRequest(BaseModel):
    # Core deterministic analytics
    completion_rate: float = Field(ge=0.0, le=1.0)

    # Weighted adherence across Critical, High, Medium and Low tasks
    priority_adherence: float = Field(ge=0.0, le=1.0)

    # Absence of snooze/postpone disruptions
    schedule_stability: float = Field(ge=0.0, le=1.0)

    # Today's task states
    completed: int = Field(ge=0)
    pending: int = Field(ge=0)

    actionable_pending: int = Field(default=0, ge=0)
    upcoming: int = Field(default=0, ge=0)
    scored_task_count: int = Field(default=0, ge=0)

    # True while today's score can still change
    is_provisional: bool = True

    # Recorded behaviour events
    snoozes: int = Field(ge=0)
    postpones: int = Field(ge=0)

    high_cognitive_postponed: int = Field(default=0, ge=0)

    # Category analytics
    completed_by_category: dict[str, int] = Field(
        default_factory=dict
    )

    pending_by_category: dict[str, int] = Field(
        default_factory=dict
    )

    # Tomorrow's workload
    tomorrow_high_priority_count: int = Field(default=0, ge=0)

    # High-priority supporting statistics
    high_priority_total: int = Field(default=0, ge=0)
    high_priority_completed: int = Field(default=0, ge=0)
    pending_high_priority_count: int = Field(default=0, ge=0)

    pending_high_priority_tasks: list[dict[str, Any]] = Field(
        default_factory=list
    )

    # Overdue-task statistics
    overdue_task_count: int = Field(default=0, ge=0)
    overdue_high_priority_count: int = Field(default=0, ge=0)

    overdue_tasks: list[dict[str, Any]] = Field(
        default_factory=list
    )

    overdue_high_priority_tasks: list[dict[str, Any]] = Field(
        default_factory=list
    )

    # Completion timing
    completed_on_time: int = Field(default=0, ge=0)
    completed_late: int = Field(default=0, ge=0)
    overdue_pending: int = Field(default=0, ge=0)


# ── POST /predict-scores ────────────────────────────────────────────────────

@router.post("/predict-scores")
def predict_scores_endpoint(req: PredictScoresRequest):
    return predict_scores(
        title=req.title,
        description=req.description,
        category=req.category,
        start_time=req.start_time,
        end_time=req.end_time,
        task_duration=req.task_duration,
        estimated_duration_minutes=req.estimated_duration_minutes,
    )


# ── POST /rank-tasks ────────────────────────────────────────────────────────

@router.post("/rank-tasks")
def rank_tasks_endpoint(tasks: list = Body(...)):
    """
    Stage 2:
    Predicted scores → XGBRanker → ranked list + SHAP explanations.
    """
    return rank_tasks(tasks)


# ── POST /generate-schedule ─────────────────────────────────────────────────

@router.post("/generate-schedule")
def generate_schedule_endpoint(req: ScheduleRequest):
    """
    Stage 3:
    Ranked pending tasks → constraint-based daily schedule.
    """
    return generate_schedule(
        tasks=req.tasks,
        schedule_date=req.schedule_date,
        available_start=req.available_start,
        available_end=req.available_end,
        break_strategy=req.break_strategy,
        planning_mode=req.planning_mode,
    )


# ── POST /generate-reflection ────────────────────────────────────────────────

@router.post("/generate-reflection")
def generate_reflection_endpoint(req: ReflectionRequest):
    """
    Stage 4:
    Verified deterministic analytics → grounded LLM reflection.
    """
    data = req.model_dump()

    return generate_daily_reflection(data)