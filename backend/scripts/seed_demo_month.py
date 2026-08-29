"""Idempotently add four weeks of realistic entries for the demo user."""

from __future__ import annotations

import argparse
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Dict, List


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.components.rag_summary.diary_entry_service import (  # noqa: E402
    create_user_diary_entry,
    list_user_diary_entries,
)
from app.components.rag_summary.schemas import DiaryEntryCreate  # noqa: E402


def _record(
    *,
    week_offset: int,
    day_offset: int,
    activity_name: str,
    activity_category: str,
    start_time: str,
    end_time: str,
    productivity_level: str,
    mood_before: str,
    mood_after: str,
    task_outcome: str,
    health_status: str,
    location: str,
    with_whom: str,
    notes: str,
) -> Dict[str, Any]:
    return locals()


DEMO_RECORDS: List[Dict[str, Any]] = [
    _record(
        week_offset=-3,
        day_offset=0,
        activity_name="Plan web project milestones",
        activity_category="Work",
        start_time="09:00",
        end_time="10:30",
        productivity_level="High",
        mood_before="Motivated",
        mood_after="Focused",
        task_outcome="Completed",
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Mapped the main features and set achievable milestones for the project.",
    ),
    _record(
        week_offset=-3,
        day_offset=2,
        activity_name="Database assignment research",
        activity_category="Study",
        start_time="14:00",
        end_time="16:15",
        productivity_level="Medium",
        mood_before="Unsure",
        mood_after="Tired",
        task_outcome="Partially completed",
        health_status="Tired",
        location="Library",
        with_whom="Alone",
        notes="Made progress, but complex query design caused stress near the end.",
    ),
    _record(
        week_offset=-3,
        day_offset=4,
        activity_name="Evening walk",
        activity_category="Health",
        start_time="18:00",
        end_time="18:45",
        productivity_level="Medium",
        mood_before="Stressed",
        mood_after="Calm",
        task_outcome="Completed",
        health_status="Good",
        location="Neighborhood",
        with_whom="Alone",
        notes="The walk helped me unwind after a demanding study session.",
    ),
    _record(
        week_offset=-3,
        day_offset=5,
        activity_name="Badminton practice",
        activity_category="Exercise",
        start_time="16:00",
        end_time="17:30",
        productivity_level="High",
        mood_before="Neutral",
        mood_after="Happy",
        task_outcome="Completed",
        health_status="Energetic",
        location="Sports center",
        with_whom="Friends",
        notes="A good session improved my energy and mood.",
    ),
    _record(
        week_offset=-2,
        day_offset=0,
        activity_name="Build diary API endpoints",
        activity_category="Work",
        start_time="09:30",
        end_time="12:00",
        productivity_level="High",
        mood_before="Focused",
        mood_after="Satisfied",
        task_outcome="Completed",
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Finished the create and list endpoints and verified their responses.",
    ),
    _record(
        week_offset=-2,
        day_offset=2,
        activity_name="Client presentation rehearsal",
        activity_category="Work",
        start_time="19:00",
        end_time="20:00",
        productivity_level="Medium",
        mood_before="Anxious",
        mood_after="Confident",
        task_outcome="Completed",
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Practicing the difficult sections reduced my anxiety about presenting.",
    ),
    _record(
        week_offset=-2,
        day_offset=4,
        activity_name="Fix authentication bug",
        activity_category="Work",
        start_time="13:00",
        end_time="16:30",
        productivity_level="Low",
        mood_before="Optimistic",
        mood_after="Frustrated",
        task_outcome="Incomplete",
        health_status="Tired",
        location="Home",
        with_whom="Alone",
        notes="Repeated token errors blocked progress and made the afternoon stressful.",
    ),
    _record(
        week_offset=-2,
        day_offset=6,
        activity_name="Read software design chapter",
        activity_category="Study",
        start_time="10:00",
        end_time="11:15",
        productivity_level="Medium",
        mood_before="Calm",
        mood_after="Interested",
        task_outcome="Completed",
        health_status="Good",
        location="Home",
        with_whom="Alone",
        notes="The chapter clarified how to split the backend into smaller services.",
    ),
    _record(
        week_offset=-1,
        day_offset=0,
        activity_name="Integrate Flutter summary screen",
        activity_category="Work",
        start_time="09:00",
        end_time="12:30",
        productivity_level="High",
        mood_before="Motivated",
        mood_after="Proud",
        task_outcome="Completed",
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Connected the weekly summary API and displayed the returned feedback.",
    ),
    _record(
        week_offset=-1,
        day_offset=2,
        activity_name="Debug vector retrieval",
        activity_category="Work",
        start_time="14:00",
        end_time="17:00",
        productivity_level="Low",
        mood_before="Focused",
        mood_after="Stressed",
        task_outcome="Partially completed",
        health_status="Tired",
        location="Home",
        with_whom="Alone",
        notes="Filtering problems took longer than expected, though the cause was identified.",
    ),
    _record(
        week_offset=-1,
        day_offset=4,
        activity_name="Badminton match",
        activity_category="Exercise",
        start_time="17:00",
        end_time="18:30",
        productivity_level="High",
        mood_before="Stressed",
        mood_after="Relaxed",
        task_outcome="Completed",
        health_status="Energetic",
        location="Sports center",
        with_whom="Friends",
        notes="Playing with friends helped me recover from the stressful debugging session.",
    ),
    _record(
        week_offset=-1,
        day_offset=6,
        activity_name="Weekly planning session",
        activity_category="Personal",
        start_time="18:30",
        end_time="19:15",
        productivity_level="High",
        mood_before="Scattered",
        mood_after="Organized",
        task_outcome="Completed",
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Prioritized the remaining project work and scheduled focused blocks.",
    ),
    _record(
        week_offset=0,
        day_offset=0,
        activity_name="Implement grounded RAG summary",
        activity_category="Work",
        start_time="09:00",
        end_time="12:00",
        productivity_level="High",
        mood_before="Focused",
        mood_after="Satisfied",
        task_outcome="Completed",
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Added same-week retrieval and a prompt that stays grounded in retrieved activities.",
    ),
    _record(
        week_offset=0,
        day_offset=1,
        activity_name="Resolve summary formatting issue",
        activity_category="Work",
        start_time="13:30",
        end_time="15:00",
        productivity_level="High",
        mood_before="Frustrated",
        mood_after="Relieved",
        task_outcome="Completed",
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Changed the weekly result from separate cards into one coherent paragraph.",
    ),
    _record(
        week_offset=0,
        day_offset=3,
        activity_name="Prepare project demonstration",
        activity_category="Study",
        start_time="18:00",
        end_time="19:30",
        productivity_level="Medium",
        mood_before="Anxious",
        mood_after="Confident",
        task_outcome="Completed",
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Rehearsing the comparison explanation made the demo feel manageable.",
    ),
    _record(
        week_offset=0,
        day_offset=4,
        activity_name="Short recovery walk",
        activity_category="Health",
        start_time="17:30",
        end_time="18:10",
        productivity_level="Medium",
        mood_before="Stressed",
        mood_after="Calm",
        task_outcome="Completed",
        health_status="Good",
        location="Neighborhood",
        with_whom="Alone",
        notes="The walk reduced stress after a long project work session.",
    ),
]


def seed_demo_month(user_id: str, anchor_date: date) -> tuple[int, int]:
    current_week_start = anchor_date - timedelta(days=anchor_date.weekday())
    existing = list_user_diary_entries(user_id=user_id, limit=500)
    existing_keys = {
        (entry.entry_date, entry.activity_name, entry.start_time) for entry in existing
    }
    created = 0
    skipped = 0

    for template in DEMO_RECORDS:
        data = dict(template)
        entry_day = (
            current_week_start
            + timedelta(weeks=int(data.pop("week_offset")))
            + timedelta(days=int(data.pop("day_offset")))
        )
        key = (entry_day.isoformat(), data["activity_name"], data["start_time"])
        if key in existing_keys:
            skipped += 1
            continue
        create_user_diary_entry(
            DiaryEntryCreate(
                user_id=user_id,
                entry_date=entry_day.isoformat(),
                person_names=None,
                **data,
            )
        )
        existing_keys.add(key)
        created += 1

    return created, skipped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-id", default="demo-user-001")
    parser.add_argument(
        "--anchor-date",
        type=date.fromisoformat,
        default=date.today(),
        help="Date whose Monday anchors the newest demo week (YYYY-MM-DD).",
    )
    args = parser.parse_args()
    created, skipped = seed_demo_month(args.user_id, args.anchor_date)
    print(
        f"Demo month ready for {args.user_id}: "
        f"created {created}, already present {skipped}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
