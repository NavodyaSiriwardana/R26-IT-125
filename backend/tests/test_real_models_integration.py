"""Opt-in smoke tests for real downloaded research models.

Run only after installing requirements and setting RUN_REAL_MODEL_INTEGRATION=1:
`python -m pytest -m integration -s`.
"""

import os
import unittest
from datetime import datetime, timezone

try:
    import pytest

    pytestmark = pytest.mark.integration
except ImportError:  # unittest discovery still sees and skips this module.
    pytestmark = None

from app.components.rag_summary import chroma_store, weekly_summary_service
from app.components.rag_summary.schemas import DiaryEntryResponse


ENABLED = os.getenv("RUN_REAL_MODEL_INTEGRATION") == "1"


def _entry():
    return DiaryEntryResponse(
        id=1,
        user_id="integration-user",
        evidence_id="EV-001",
        activity_name="Study session",
        activity_category="Study",
        start_time="09:00",
        end_time="10:00",
        duration_minutes=60,
        productivity_level="High",
        mood_before="Stressed",
        mood_after="Calm",
        task_outcome="Completed",
        person_names=None,
        health_status="Normal",
        location="Home",
        with_whom="Alone",
        notes="Reviewed lecture notes.",
        entry_date="2026-05-04",
        week_start="2026-05-04",
        week_end="2026-05-10",
        created_at=datetime(2026, 5, 4, tzinfo=timezone.utc),
        updated_at=datetime(2026, 5, 4, tzinfo=timezone.utc),
    )


@unittest.skipUnless(ENABLED, "set RUN_REAL_MODEL_INTEGRATION=1")
class RealModelIntegrationTests(unittest.TestCase):
    def test_real_plain_and_personal_memory_rag_models_execute(self):
        entry = _entry()
        history_data = entry.model_dump()
        history_data.update(
            id=2,
            evidence_id="EV-002",
            activity_name="Earlier study session",
            entry_date="2026-04-27",
            week_start="2026-04-27",
            week_end="2026-05-03",
            created_at=datetime(2026, 4, 27, tzinfo=timezone.utc),
            updated_at=datetime(2026, 4, 27, tzinfo=timezone.utc),
        )
        history = DiaryEntryResponse(**history_data)
        experiment = weekly_summary_service.run_summarization_experiment(
            [entry],
            entry.user_id,
            "Summarize this week",
            entry.week_start,
            entry.week_end,
            retrieval_mode="semantic",
            reference_summary="The user completed a study session.",
            history_entries=[history],
        )

        self.assertEqual(experiment["plain_slm"]["status"], "success")
        self.assertTrue(experiment["plain_slm"]["summary_text"])
        self.assertEqual(
            experiment["rag"]["status"],
            "success",
            experiment["rag"].get("raw_output"),
        )
        self.assertTrue(experiment["rag"]["summary_points"])
        self.assertEqual(experiment["rag"]["evaluation"]["status"], "not_applicable")
        self.assertNotIn("verified_rag", experiment)
        self.assertTrue(experiment["retrieval"]["comparison_eligible"])
        for condition_name in ("plain_slm", "rag"):
            metrics = experiment[condition_name]["metrics"]
            self.assertEqual(metrics["rouge_l"]["status"], "available")
            self.assertEqual(metrics["bertscore"]["status"], "available")

        embedding = chroma_store._get_embedding_model().encode("integration smoke")
        self.assertGreater(len(embedding), 0)


if __name__ == "__main__":
    unittest.main()
