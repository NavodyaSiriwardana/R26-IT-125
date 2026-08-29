import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from app.components.rag_summary import dashboard_service
from app.components.rag_summary import firestore_store


def _entry(
    *,
    numeric_id: int,
    evidence_id: str,
    entry_date: str,
    category: str,
    duration: int,
    productivity: str,
    mood_before: str,
    mood_after: str,
    outcome: str,
    start_time: str,
) -> dict:
    return {
        "id": numeric_id,
        "user_id": "demo-user-001",
        "evidence_id": evidence_id,
        "activity_name": f"Activity {numeric_id}",
        "activity_category": category,
        "start_time": start_time,
        "end_time": "16:00",
        "duration_minutes": duration,
        "productivity_level": productivity,
        "mood_before": mood_before,
        "mood_after": mood_after,
        "task_outcome": outcome,
        "person_names": None,
        "health_status": "Normal",
        "location": "Home",
        "with_whom": "Alone",
        "notes": None,
        "entry_date": entry_date,
        "week_start": "2026-08-24",
        "week_end": "2026-08-30",
        "created_at": f"2026-08-{23 + numeric_id:02d}T10:00:00",
        "updated_at": f"2026-08-{23 + numeric_id:02d}T10:00:00",
    }


class DashboardServiceTests(unittest.TestCase):
    def test_build_weekly_dashboard_aggregates_all_sections(self):
        entries = [
            _entry(
                numeric_id=1,
                evidence_id="EV-001",
                entry_date="2026-08-24",
                category="Study",
                duration=60,
                productivity="High",
                mood_before="Stressed",
                mood_after="Happy",
                outcome="Completed",
                start_time="14:00",
            ),
            _entry(
                numeric_id=2,
                evidence_id="EV-002",
                entry_date="2026-08-25",
                category="Study",
                duration=120,
                productivity="Medium",
                mood_before="Neutral",
                mood_after="Neutral",
                outcome="Incomplete",
                start_time="09:00",
            ),
            _entry(
                numeric_id=3,
                evidence_id="EV-003",
                entry_date="2026-08-25",
                category="Sports",
                duration=30,
                productivity="Low",
                mood_before="Tired",
                mood_after="Relaxed",
                outcome="Partially Completed",
                start_time="18:00",
            ),
        ]
        latest_summary = {
            "summary_id": "summary-001",
            "saved_summary_id": "summary-001",
            "user_id": "demo-user-001",
            "week_start": "2026-08-24",
            "week_end": "2026-08-30",
            "generated_at": "2026-08-30T12:00:00",
            "query": "Summarize my week",
            "summary_type": "weekly_rag_comparison",
            "summary_points": [
                {
                    "text": "A grounded weekly summary.",
                    "citations": [],
                }
            ],
            "hallucination_score": 0.0,
            "feedback": {
                "feedback_type": "wellbeing_productivity",
                "mood_signal": "mostly_positive",
                "productivity_signal": "medium",
                "message": "Keep the routine that worked well.",
                "based_on_evidence_ids": ["EV-001"],
            },
            "additional_data": {
                "rag": {"evidence_accuracy_normalized": 0.88},
                "verified_rag": {
                    "status": "success",
                    "summary_points": [
                        {"text": "A grounded weekly summary.", "citations": []}
                    ],
                    "evaluation": {
                        "status": "available",
                        "grounded_claim_rate": 1.0,
                        "unsupported_claim_rate": 0.0,
                        "citation_metrics": {
                            "citation_precision": 1.0,
                            "citation_completeness": 1.0,
                        },
                    },
                    "retrieval": {"retrieval_coverage": 0.67},
                    "metrics": {
                        "bertscore": {"status": "available", "value": 0.82},
                        "rouge_l": {"status": "available", "value": 0.71},
                    },
                    "generation": {"latency_ms": 125.5},
                },
            },
        }

        with (
            patch.object(
                dashboard_service,
                "list_diary_entries_for_week",
                return_value=entries,
            ),
            patch.object(
                dashboard_service,
                "list_recent_diary_entries",
                return_value=list(reversed(entries)),
            ),
            patch.object(
                dashboard_service,
                "get_latest_summary_for_week",
                return_value=latest_summary,
            ),
        ):
            dashboard = dashboard_service.build_weekly_dashboard(
                user_id="demo-user-001",
                week_start="2026-08-24",
                week_end="2026-08-30",
            )

        self.assertEqual(dashboard.overview.activity_count, 3)
        self.assertEqual(dashboard.overview.logged_minutes, 210)
        self.assertEqual(dashboard.overview.completion_rate, 33.3)
        self.assertEqual(dashboard.overview.mood_improved_rate, 66.7)
        self.assertEqual(len(dashboard.daily_activity), 7)
        self.assertEqual(dashboard.daily_activity[1].total_minutes, 150)
        self.assertEqual(dashboard.category_breakdown[0].category, "Study")
        self.assertEqual(dashboard.category_breakdown[0].total_minutes, 180)
        self.assertEqual(dashboard.mood_breakdown.improved_count, 2)
        self.assertEqual(len(dashboard.insights), 2)
        self.assertEqual(dashboard.recent_entries[0].evidence_id, "EV-003")
        self.assertIsNotNone(dashboard.latest_summary)
        self.assertEqual(dashboard.latest_summary.summary_id, "summary-001")
        self.assertEqual(dashboard.latest_summary.evidence_accuracy, 0.88)
        self.assertEqual(dashboard.latest_summary.grounded_claim_rate, 1.0)
        self.assertEqual(dashboard.latest_summary.unsupported_claim_rate, 0.0)
        self.assertEqual(dashboard.latest_summary.citation_precision, 1.0)
        self.assertEqual(dashboard.latest_summary.retrieval_coverage, 0.67)
        self.assertEqual(dashboard.latest_summary.bertscore, 0.82)
        self.assertEqual(dashboard.latest_summary.rouge_l, 0.71)
        self.assertEqual(dashboard.latest_summary.generation_latency_ms, 125.5)

    def test_empty_week_returns_zero_filled_dashboard(self):
        with (
            patch.object(
                dashboard_service,
                "list_diary_entries_for_week",
                return_value=[],
            ),
            patch.object(
                dashboard_service,
                "list_recent_diary_entries",
                return_value=[],
            ),
            patch.object(
                dashboard_service,
                "get_latest_summary_for_week",
                return_value=None,
            ),
        ):
            dashboard = dashboard_service.build_weekly_dashboard(
                user_id="demo-user-001",
                week_start="2026-08-24",
                week_end="2026-08-30",
            )

        self.assertEqual(dashboard.evidence_entry_count, 0)
        self.assertEqual(dashboard.overview.logged_minutes, 0)
        self.assertEqual(len(dashboard.daily_activity), 7)
        self.assertTrue(all(day.total_minutes == 0 for day in dashboard.daily_activity))
        self.assertEqual(dashboard.insights, [])
        self.assertIsNone(dashboard.latest_summary)

    def test_week_must_be_a_complete_monday_to_sunday_pair(self):
        with self.assertRaisesRegex(ValueError, "provided together"):
            dashboard_service.resolve_dashboard_week("2026-08-24", None)

        with self.assertRaisesRegex(ValueError, "start on Monday"):
            dashboard_service.resolve_dashboard_week(
                "2026-08-25",
                "2026-08-31",
            )

    def test_legacy_naive_timestamps_are_interpreted_as_utc(self):
        naive_key = firestore_store._datetime_sort_key("2026-08-30T12:00:00")
        aware_key = firestore_store._datetime_sort_key(
            datetime(2026, 8, 30, 12, 0, tzinfo=timezone.utc)
        )

        self.assertEqual(naive_key, aware_key)
        self.assertEqual(
            dashboard_service._as_iso_string("2026-08-30T12:00:00"),
            "2026-08-30T12:00:00+00:00",
        )

    def test_malformed_latest_summary_is_a_server_data_error(self):
        with patch.object(
            dashboard_service,
            "get_latest_summary_for_week",
            return_value={
                "summary_id": "broken-summary",
                "week_start": "2026-08-24",
                "week_end": "2026-08-30",
            },
        ):
            with self.assertRaisesRegex(RuntimeError, "invalid data"):
                dashboard_service.get_latest_weekly_summary(
                    user_id="demo-user-001",
                    week_start="2026-08-24",
                    week_end="2026-08-30",
                )


if __name__ == "__main__":
    unittest.main()
