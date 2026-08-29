import io
import sys
import types
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from unittest.mock import patch

from fastapi import HTTPException

from app.components.rag_summary import (
    feedback_generator,
    routes,
    summarizers,
    weekly_summary_service,
)
from app.components.rag_summary.schemas import (
    DiaryEntryCreate,
    DiaryEntryResponse,
    PlainSummaryRequest,
    RagSummaryRequest,
    WeeklySummaryRequest,
)


def _entry(
    evidence_id="EV-001",
    activity="Study",
    *,
    entry_date="2026-05-04",
    week_start="2026-05-04",
    week_end="2026-05-10",
):
    return DiaryEntryResponse(
        id=int(evidence_id.split("-")[-1]),
        user_id="research-user-001",
        evidence_id=evidence_id,
        activity_name=activity,
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
        notes="Reviewed notes.",
        entry_date=entry_date,
        week_start=week_start,
        week_end=week_end,
        created_at=datetime(2026, 5, 4, tzinfo=timezone.utc),
        updated_at=datetime(2026, 5, 4, tzinfo=timezone.utc),
    )


def _evidence(entry):
    data = entry.model_dump(mode="json")
    return {"evidence_id": entry.evidence_id, "metadata": data}


class _FakeTokenizer:
    def __call__(self, text, **kwargs):
        return {"input_ids": list(range(max(1, len(text) // 20)))}


class _FakeGenerator:
    def __init__(self, outputs):
        self.outputs = iter(outputs)
        self.calls = []
        self.tokenizer = _FakeTokenizer()
        self.model = types.SimpleNamespace(
            config=types.SimpleNamespace(_commit_hash="test-revision")
        )

    def __call__(self, prompt, **kwargs):
        self.calls.append((prompt, kwargs))
        return [{"generated_text": next(self.outputs)}]


def _available_evaluation(classifications):
    per_claim = [
        {
            "claim": f"Claim {index}",
            "classification": classification,
            "valid_evidence_ids": ["EV-001"],
        }
        for index, classification in enumerate(classifications, 1)
    ]
    entailed = classifications.count("entailed")
    total = len(classifications)
    unsupported = total - entailed
    return {
        "status": "available",
        "per_claim": per_claim,
        "citation_metrics": {
            "citation_precision": 1.0,
            "citation_completeness": 1.0,
        },
        "grounded_claim_rate": entailed / total if total else None,
        "unsupported_claim_rate": unsupported / total if total else None,
        "hallucination_score": unsupported / total if total else None,
    }


class SharedGenerationTests(unittest.TestCase):
    def tearDown(self):
        summarizers._summarizer_pipeline = None

    def test_plain_and_rag_share_generator_decoding_seed_and_include_query(self):
        entry = _entry()
        fake = _FakeGenerator(
            [
                "The model generated this plain summary.",
                "The model generated this RAG claim [EVIDENCE_ID: EV-001].",
            ]
        )
        fake_transformers = types.ModuleType("transformers")
        seeds = []
        fake_transformers.set_seed = seeds.append
        summarizers._summarizer_pipeline = fake

        query = "Explain the study session"
        with patch.dict(sys.modules, {"transformers": fake_transformers}):
            plain = summarizers.generate_plain_slm_summary_result([entry], query)
            rag = summarizers.generate_rag_slm_summary([_evidence(entry)], query)

        self.assertEqual(len(fake.calls), 2)
        self.assertIn(query, fake.calls[0][0])
        self.assertIn(query, fake.calls[1][0])
        self.assertNotIn("EVIDENCE_ID", fake.calls[0][0])
        self.assertIn("[EVIDENCE_ID: EV-001]", fake.calls[1][0])
        self.assertIn("Weekly activities as plain text", fake.calls[0][0])
        self.assertNotIn("Every factual statement must be grounded", fake.calls[0][0])
        self.assertIn("Every factual statement must be grounded", fake.calls[1][0])
        self.assertIn("Chroma-retrieved weekly evidence", fake.calls[1][0])
        self.assertEqual(fake.calls[0][1], fake.calls[1][1])
        self.assertFalse(fake.calls[0][1]["do_sample"])
        self.assertEqual(plain.metadata["random_seed"], rag.metadata["random_seed"])
        self.assertEqual(seeds, [plain.metadata["random_seed"]] * 2)
        self.assertEqual(
            rag.summary_points[0]["text"],
            "The model generated this RAG claim.",
        )
        self.assertNotIn("On 2026", rag.summary_points[0]["text"])

    def test_unknown_ids_are_invalid_and_uncited_claims_remain_visible(self):
        points, parsing = summarizers.parse_rag_output(
            "Supported wording [EVIDENCE_ID: EV-001].\n"
            "Invented source [EVIDENCE_ID: EV-999].\n"
            "An uncited factual claim.",
            [_evidence(_entry())],
        )

        self.assertTrue(points[0]["citations"][0]["is_valid"])
        self.assertFalse(points[1]["citations"][0]["is_valid"])
        self.assertEqual(points[1]["citations"][0]["evidence_id"], "EV-999")
        self.assertEqual(points[2]["citations"], [])
        self.assertEqual(parsing["unknown_evidence_ids"], ["EV-999"])
        self.assertEqual(parsing["uncited_claim_count"], 1)

    def test_evidence_id_matching_is_exact(self):
        points, parsing = summarizers.parse_rag_output(
            "Altered identifier [EVIDENCE_ID: ev-001].",
            [_evidence(_entry())],
        )

        self.assertFalse(points[0]["citations"][0]["is_valid"])
        self.assertEqual(parsing["unknown_evidence_ids"], ["ev-001"])

    def test_completely_unparseable_output_raises_instead_of_using_template(self):
        with self.assertRaises(summarizers.RagParsingFailure):
            summarizers.parse_rag_output("[EVIDENCE_ID: EV-001]", [_evidence(_entry())])

    def test_model_formatting_is_normalized_to_one_unlabelled_paragraph(self):
        paragraph = summarizers._normalize_generated_paragraph(
            "- This week: A productive day.\n"
            "2. This week: My mood became calmer."
        )

        self.assertEqual(
            paragraph,
            "A productive day. My mood became calmer.",
        )

    def test_no_raw_diary_text_is_printed(self):
        fake = _FakeGenerator(["A model summary long enough to remain unchanged."])
        fake_transformers = types.ModuleType("transformers")
        fake_transformers.set_seed = lambda _: None
        summarizers._summarizer_pipeline = fake
        captured = io.StringIO()
        with patch.dict(sys.modules, {"transformers": fake_transformers}), redirect_stdout(captured):
            summarizers.generate_plain_slm_summary_result([_entry()], "Summarize")
        self.assertEqual(captured.getvalue(), "")


class RetrievalFailureTests(unittest.TestCase):
    def test_embedding_failure_is_explicit_and_not_a_fake_zero(self):
        def unavailable_retriever(*args, **kwargs):
            raise RuntimeError("embedding unavailable")

        retrieved, result = weekly_summary_service.select_research_evidence(
            [_entry()],
            user_id="research-user-001",
            query="Only discuss exercise",
            week_start="2026-05-04",
            week_end="2026-05-10",
            top_k=5,
            retrieval_mode="semantic",
            semantic_retriever=unavailable_retriever,
        )

        self.assertEqual(retrieved, [])
        self.assertEqual(result["status"], "unavailable")
        self.assertIsNone(result["retrieved_evidence_count"])
        self.assertIsNone(result["retrieval_coverage"])
        self.assertEqual(result["failure_reason"], "retrieval_failed:RuntimeError")


class SameWeekRagPipelineTests(unittest.TestCase):
    def test_rag_retrieval_is_scoped_to_the_same_week(self):
        entries = [_entry(), _entry("EV-002", "Badminton")]

        def fake_retriever(received_entries, **kwargs):
            self.assertEqual(received_entries, entries)
            self.assertEqual(kwargs["week_start"], "2026-05-04")
            self.assertEqual(kwargs["week_end"], "2026-05-10")
            return [{**_evidence(entries[1]), "similarity_score": 0.9}]

        retrieved, diagnostics = weekly_summary_service.select_research_evidence(
            entries,
            user_id="research-user-001",
            query="Summarize my week",
            week_start="2026-05-04",
            week_end="2026-05-10",
            top_k=3,
            retrieval_mode="semantic",
            semantic_retriever=fake_retriever,
        )

        self.assertEqual([item["evidence_id"] for item in retrieved], ["EV-002"])
        self.assertTrue(diagnostics["comparison_eligible"])
        self.assertEqual(diagnostics["retrieval_mode"], "chroma_semantic_week")

    def test_four_entries_and_uncited_rag_output_are_not_rejected(self):
        entries = [_entry(f"EV-{index:03d}", f"Activity {index}") for index in range(1, 5)]
        plain_output = summarizers.GenerationOutput(
            text="A plain weekly summary.",
            metadata={"status": "success", "latency_ms": 1.0},
        )
        rag_output = summarizers.RagGenerationOutput(
            raw_text="A personalized summary generated without citations.",
            summary_points=[
                {
                    "claim_id": "CLM-001",
                    "text": "A personalized summary generated without citations.",
                    "citations": [],
                }
            ],
            metadata={"status": "success", "latency_ms": 1.0},
            parsing={"status": "success", "uncited_claim_count": 1},
        )

        with (
            patch.object(
                weekly_summary_service,
                "load_user_week_entries",
                return_value=("2026-05-04", "2026-05-10", entries),
            ),
            patch.object(
                weekly_summary_service,
                "generate_plain_slm_summary_result",
                return_value=plain_output,
            ),
            patch.object(
                weekly_summary_service,
                "generate_rag_slm_summary",
                return_value=rag_output,
            ),
            patch.object(
                weekly_summary_service,
                "select_research_evidence",
                return_value=(
                    [_evidence(entry) for entry in entries],
                    {
                        "status": "available",
                        "retrieval_mode": "chroma_semantic_week",
                        "weekly_entry_count": 4,
                        "retrieved_evidence_count": 4,
                        "retrieved_evidence_ids": [entry.evidence_id for entry in entries],
                        "retrieval_coverage": 1.0,
                        "comparison_eligible": True,
                        "comparison_reason": None,
                    },
                ),
            ),
            patch.object(
                weekly_summary_service,
                "evaluate_plain_summary_groundedness",
                return_value=_available_evaluation(["entailed"]),
            ),
            patch.object(weekly_summary_service, "save_summary"),
        ):
            result = weekly_summary_service.generate_weekly_summary(
                WeeklySummaryRequest(
                    user_id="research-user-001",
                    query="Summarize my week",
                    week_start="2026-05-04",
                    week_end="2026-05-10",
                    retrieval_mode="semantic",
                )
            )

        self.assertEqual(len(result.summary_points), 1)
        self.assertEqual(result.summary_points[0].citations, [])
        self.assertFalse(result.feedback.abstained)
        self.assertEqual(result.feedback.based_on_evidence_ids, [
            "EV-001",
            "EV-002",
            "EV-003",
            "EV-004",
        ])
        self.assertNotIn("verified_rag", result.additional_data)
        self.assertIsNone(result.unsupported_claim_rate)


class RouteRegressionTests(unittest.TestCase):
    def test_plain_and_rag_legacy_paths_are_user_aware_and_do_not_name_error(self):
        entry = _entry()
        with (
            patch.object(routes, "load_user_week_entries", return_value=("2026-05-04", "2026-05-10", [entry])),
            patch.object(
                routes,
                "run_plain_condition",
                return_value={
                    "status": "success",
                    "summary_text": "Plain output.",
                    "generation": {},
                    "evaluation": {},
                    "metrics": {},
                },
            ),
        ):
            plain = routes.generate_plain_summary(
                PlainSummaryRequest(user_id="research-user-001", query="Summarize")
            )
        self.assertEqual(plain.summary_text, "Plain output.")

        experiment = {
            "rag": {
                "status": "success",
                "summary_points": [],
                "generation": {},
                "evaluation": {},
                "metrics": {},
            },
            "retrieval": {
                "retrieved_evidence_count": 1,
                "weekly_entry_count": 1,
                "retrieval_coverage": 1.0,
                "retrieved_evidence_ids": ["EV-002"],
            },
        }
        with patch.object(
            routes,
            "run_user_week_experiment",
            return_value=("2026-05-04", "2026-05-10", [entry], experiment),
        ):
            rag = routes.generate_rag_summary(
                RagSummaryRequest(user_id="research-user-001", query="Summarize")
            )
        self.assertEqual(rag.retrieved_evidence_ids, ["EV-002"])
        self.assertEqual(rag.represented_entry_count, 1)

    def test_public_500_response_does_not_expose_internal_exception(self):
        payload = DiaryEntryCreate(
            user_id="research-user-001",
            activity_name="private diary text",
            activity_category="Study",
            start_time="09:00",
            end_time="10:00",
            productivity_level="High",
            mood_before="Stressed",
            mood_after="Calm",
            task_outcome="Completed",
            location="Home",
            with_whom="Alone",
        )
        with patch.object(
            routes,
            "create_user_diary_entry",
            side_effect=RuntimeError("SECRET internal failure"),
        ):
            with self.assertLogs(routes.logger, level="ERROR") as captured:
                with self.assertRaises(HTTPException) as raised:
                    routes.add_diary_entry(payload)
        self.assertEqual(raised.exception.status_code, 500)
        self.assertNotIn("SECRET", raised.exception.detail)
        self.assertNotIn("private diary text", raised.exception.detail)
        self.assertNotIn("SECRET", " ".join(captured.output))
        self.assertNotIn("private diary text", " ".join(captured.output))


class FeedbackSafetyTests(unittest.TestCase):
    def test_invalid_slm_feedback_uses_explicit_rule_based_fallback(self):
        generated = summarizers.GenerationOutput(
            text=(
                '{"message":"Productivity improved by 80 percent.",'
                '"action":"Continue.","evidence_ids":["EV-999"],'
                '"abstained":false}'
            ),
            metadata={"status": "success"},
        )
        with patch.object(feedback_generator, "_feedback_prompt", wraps=feedback_generator._feedback_prompt), patch.object(
            summarizers,
            "generate_text",
            return_value=generated,
        ):
            result = feedback_generator.generate_feedback_from_rag_evidence(
                [_entry()],
                [_evidence(_entry())],
                use_slm=True,
            )

        self.assertEqual(result["generation_method"], "rule_based_fallback")
        self.assertIsNotNone(result["fallback_reason"])
        self.assertEqual(result["evidence_ids"], ["EV-001"])

    def test_rule_based_feedback_keeps_structured_signals_and_provenance(self):
        result = feedback_generator.generate_feedback_from_rag_evidence(
            [_entry()],
            [_evidence(_entry())],
        )
        self.assertEqual(result["mood_signal"], "negative_to_positive")
        self.assertEqual(result["productivity_signal"], "high")
        self.assertEqual(result["generation_method"], "rule_based")
        self.assertEqual(result["evidence_ids"], ["EV-001"])
        self.assertTrue(result["action"])


if __name__ == "__main__":
    unittest.main()
