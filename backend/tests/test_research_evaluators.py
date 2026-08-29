import os
import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from app.components.rag_summary.hallucination_evaluator import (
    DEFAULT_ENTAILMENT_THRESHOLD,
    DEFAULT_NLI_MODEL,
    evaluate_plain_summary_groundedness,
    evaluate_rag_summary_groundedness,
    evaluate_rag_summary_hallucination,
)
from app.components.rag_summary.schemas import DiaryEntryResponse
from app.components.rag_summary.similarity_evaluator import (
    calculate_bertscore_similarity,
    calculate_evidence_accuracy,
    calculate_rouge_l_similarity,
    evaluate_bertscore,
    evaluate_reference_similarity,
)


WEEK_START = "2026-05-04"
WEEK_END = "2026-05-10"
USER_ID = "research-user-001"


def _entry(
    evidence_id: str,
    activity: str,
    *,
    user_id: str = USER_ID,
    week_start: str = WEEK_START,
    week_end: str = WEEK_END,
    entry_date: str = "2026-05-04",
    numeric_id: int = 1,
) -> DiaryEntryResponse:
    return DiaryEntryResponse(
        id=numeric_id,
        user_id=user_id,
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
        notes=f"Notes about {activity}",
        entry_date=entry_date,
        week_start=week_start,
        week_end=week_end,
        created_at=datetime(2026, 5, 4, 10, 0, tzinfo=timezone.utc),
        updated_at=datetime(2026, 5, 4, 10, 0, tzinfo=timezone.utc),
    )


def _scores(entailment: float, contradiction: float, neutral: float):
    return [
        {"label": "contradiction", "score": contradiction},
        {"label": "entailment", "score": entailment},
        {"label": "neutral", "score": neutral},
    ]


class FakeNliRunner:
    def __init__(self, *responses):
        self.responses = list(responses)
        self.calls = []

    def __call__(self, inputs, **kwargs):
        self.calls.append((inputs, kwargs))
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


class HallucinationEvaluatorTests(unittest.TestCase):
    def test_defaults_are_documented_research_configuration(self):
        self.assertEqual(DEFAULT_NLI_MODEL, "cross-encoder/nli-deberta-v3-base")
        self.assertEqual(DEFAULT_ENTAILMENT_THRESHOLD, 0.70)

    def test_rag_validity_rejects_wrong_user_wrong_week_and_unknown_ids(self):
        correct = _entry("EV-001", "Database assignment")
        wrong_user = _entry("EV-002", "Private activity", user_id="other-user", numeric_id=2)
        wrong_week = _entry(
            "EV-003",
            "Older activity",
            week_start="2026-04-27",
            week_end="2026-05-03",
            entry_date="2026-05-03",
            numeric_id=3,
        )
        points = [
            {
                "text": (
                    "The assignment was completed [1]. "
                    "A private activity occurred [2]. "
                    "An older activity occurred [3]. "
                    "An invented event occurred [4]."
                ),
                "citations": [
                    {"label": "[1]", "evidence_id": "EV-001"},
                    {"label": "[2]", "evidence_id": "EV-002"},
                    {"label": "[3]", "evidence_id": "EV-003"},
                    {"label": "[4]", "evidence_id": "EV-999"},
                ],
            }
        ]
        runner = FakeNliRunner(_scores(0.91, 0.04, 0.05))

        result = evaluate_rag_summary_groundedness(
            points,
            [correct, wrong_user, wrong_week],
            user_id=USER_ID,
            week_start=WEEK_START,
            week_end=WEEK_END,
            nli_runner=runner,
        )

        self.assertEqual(result["total_citations"], 4)
        self.assertEqual(result["valid_citations"], 1)
        self.assertEqual(result["invalid_citations"], 3)
        self.assertEqual(result["citation_precision"], 0.25)
        self.assertEqual(result["claims_with_valid_citation"], 1)
        self.assertEqual(result["citation_completeness"], 0.25)
        self.assertEqual(result["entailed_claim_count"], 1)
        self.assertEqual(result["unsupported_claim_count"], 3)
        self.assertEqual(result["unsupported_claim_rate"], 0.75)
        self.assertEqual(result["hallucination_score"], 0.75)
        self.assertEqual(
            [detail["reason"] for detail in result["citation_details"]],
            [None, "wrong_user", "wrong_week", "unknown_evidence_id"],
        )
        self.assertEqual(len(runner.calls), 1)

    def test_only_claim_local_valid_citations_are_used_as_nli_premise(self):
        cited = _entry("EV-001", "Database assignment")
        uncited = _entry("EV-002", "Running at the park", numeric_id=2)
        runner = FakeNliRunner(_scores(0.25, 0.10, 0.65))

        result = evaluate_rag_summary_groundedness(
            [
                {
                    "text": "The user enjoyed a long holiday [1].",
                    "citations": [{"label": "[1]", "evidence_id": "EV-001"}],
                }
            ],
            [cited, uncited],
            user_id=USER_ID,
            week_start=WEEK_START,
            week_end=WEEK_END,
            nli_runner=runner,
        )

        premise = runner.calls[0][0]["text"]
        self.assertIn("EV-001", premise)
        self.assertNotIn("EV-002", premise)
        self.assertEqual(result["per_claim"][0]["classification"], "neutral")
        self.assertEqual(result["neutral_claim_count"], 1)
        self.assertEqual(result["grounded_claim_rate"], 0.0)
        self.assertEqual(result["unsupported_claim_rate"], 1.0)
        self.assertEqual(result["no_valid_evidence_claim_count"], 0)

    def test_canonical_but_unretrieved_id_is_not_valid_for_rag(self):
        retrieved = _entry("EV-001", "Database assignment")
        not_retrieved = _entry("EV-002", "Running at the park", numeric_id=2)
        runner = FakeNliRunner(RuntimeError("must not be called"))

        result = evaluate_rag_summary_groundedness(
            [
                {
                    "text": "The user ran at the park.",
                    "citations": [{"label": "[EV-002]", "evidence_id": "EV-002"}],
                }
            ],
            [retrieved, not_retrieved],
            user_id=USER_ID,
            week_start=WEEK_START,
            week_end=WEEK_END,
            nli_runner=runner,
            allowed_evidence_ids=["EV-001"],
        )

        self.assertEqual(runner.calls, [])
        self.assertEqual(result["valid_citations"], 0)
        self.assertEqual(result["invalid_citations"], 1)
        self.assertEqual(result["per_claim"][0]["classification"], "unsupported")
        self.assertEqual(
            result["citation_details"][0]["reason"],
            "evidence_id_not_supplied_to_model",
        )

    def test_contradiction_is_detected_and_counted_as_unsupported(self):
        runner = FakeNliRunner(_scores(0.02, 0.95, 0.03))
        result = evaluate_rag_summary_groundedness(
            [
                {
                    "text": "The assignment was not completed [EV-001].",
                    "citations": [],
                }
            ],
            [_entry("EV-001", "Database assignment")],
            user_id=USER_ID,
            week_start=WEEK_START,
            week_end=WEEK_END,
            nli_runner=runner,
        )

        self.assertEqual(result["per_claim"][0]["classification"], "contradicted")
        self.assertEqual(result["contradicted_claim_count"], 1)
        self.assertEqual(result["unsupported_claim_count"], 1)

    def test_uncited_claim_is_unsupported_without_loading_nli(self):
        runner = FakeNliRunner(RuntimeError("must not be called"))
        result = evaluate_rag_summary_groundedness(
            [{"text": "The user travelled abroad.", "citations": []}],
            [_entry("EV-001", "Database assignment")],
            user_id=USER_ID,
            week_start=WEEK_START,
            week_end=WEEK_END,
            nli_runner=runner,
        )

        self.assertEqual(runner.calls, [])
        self.assertEqual(result["status"], "available")
        self.assertEqual(result["per_claim"][0]["classification"], "unsupported")
        self.assertEqual(result["citation_completeness"], 0.0)
        self.assertIsNone(result["citation_precision"])
        self.assertEqual(result["unsupported_claim_rate"], 1.0)

    def test_any_nli_runtime_failure_nulls_all_nli_aggregate_metrics(self):
        runner = FakeNliRunner(
            _scores(0.90, 0.05, 0.05),
            RuntimeError("model unavailable"),
        )
        result = evaluate_rag_summary_groundedness(
            [
                {
                    "text": "First claim [1]. Second claim [2].",
                    "citations": [
                        {"label": "[1]", "evidence_id": "EV-001"},
                        {"label": "[2]", "evidence_id": "EV-002"},
                    ],
                }
            ],
            [
                _entry("EV-001", "Database assignment"),
                _entry("EV-002", "Research reading", numeric_id=2),
            ],
            user_id=USER_ID,
            week_start=WEEK_START,
            week_end=WEEK_END,
            nli_runner=runner,
        )

        self.assertEqual(result["status"], "unavailable")
        self.assertIsNone(result["entailed_claim_count"])
        self.assertIsNone(result["grounded_claim_rate"])
        self.assertIsNone(result["unsupported_claim_rate"])
        self.assertIsNone(result["hallucination_score"])
        self.assertTrue(all(item["classification"] is None for item in result["per_claim"]))
        self.assertEqual(result["citation_precision"], 1.0)

    def test_plain_nli_receives_full_canonical_week_and_citations_are_na(self):
        first = _entry("EV-001", "Database assignment")
        second = _entry("EV-002", "Research reading", numeric_id=2)
        other_user = _entry("EV-003", "Private event", user_id="other-user", numeric_id=3)
        runner = FakeNliRunner(_scores(0.88, 0.05, 0.07))

        result = evaluate_plain_summary_groundedness(
            "The week included study activities.",
            [first, second, other_user],
            user_id=USER_ID,
            week_start=WEEK_START,
            week_end=WEEK_END,
            nli_runner=runner,
        )

        premise = runner.calls[0][0]["text"]
        self.assertIn("EV-001", premise)
        self.assertIn("EV-002", premise)
        self.assertNotIn("EV-003", premise)
        self.assertEqual(result["citation_metrics"]["status"], "not_applicable")
        self.assertIsNone(result["total_citations"])
        self.assertEqual(result["grounded_claim_rate"], 1.0)

    def test_nli_model_and_threshold_are_environment_configurable(self):
        runner = FakeNliRunner(_scores(0.75, 0.05, 0.20))
        with patch.dict(
            os.environ,
            {"NLI_MODEL_NAME": "example/custom-nli", "NLI_ENTAILMENT_THRESHOLD": "0.80"},
        ):
            result = evaluate_plain_summary_groundedness(
                "A study activity occurred.",
                [_entry("EV-001", "Database assignment")],
                user_id=USER_ID,
                week_start=WEEK_START,
                week_end=WEEK_END,
                nli_runner=runner,
            )

        self.assertEqual(result["nli_model"], "example/custom-nli")
        self.assertEqual(result["entailment_threshold"], 0.8)
        self.assertEqual(result["per_claim"][0]["classification"], "neutral")

    def test_legacy_id_only_rag_call_is_explicitly_unavailable(self):
        result = evaluate_rag_summary_hallucination(
            [{"text": "Claim [1].", "citations": [{"label": "[1]", "evidence_id": "EV-001"}]}],
            valid_evidence_ids=["EV-001"],
        )

        self.assertEqual(result["status"], "unavailable")
        self.assertIsNone(result["citation_precision"])
        self.assertIsNone(result["hallucination_score"])
        self.assertIn("Canonical DiaryEntryResponse", result["reason"])


class _FakeScalar:
    def __init__(self, value):
        self.value = value

    def item(self):
        return self.value


class _FakeScores:
    def __init__(self, value):
        self.value = value

    def mean(self):
        return _FakeScalar(self.value)


class SimilarityEvaluatorTests(unittest.TestCase):
    def test_bertscore_uses_only_supplied_human_reference_and_returns_status(self):
        calls = []

        def scorer(**kwargs):
            calls.append(kwargs)
            return None, None, _FakeScores(0.81234)

        result = evaluate_bertscore(
            "Generated summary",
            "Human reference summary",
            scorer=scorer,
        )

        self.assertEqual(result["status"], "available")
        self.assertEqual(result["value"], 0.8123)
        self.assertIsNone(result["reason"])
        self.assertEqual(calls[0]["refs"], ["Human reference summary"])

    def test_bertscore_blank_or_runtime_failure_is_unavailable_not_zero(self):
        blank = calculate_bertscore_similarity("summary", "   ")
        failed = calculate_bertscore_similarity(
            "summary",
            "human reference",
            scorer=lambda **kwargs: (_ for _ in ()).throw(RuntimeError("offline")),
        )

        self.assertEqual(blank["status"], "unavailable")
        self.assertIsNone(blank["value"])
        self.assertEqual(failed["status"], "unavailable")
        self.assertIsNone(failed["value"])

    def test_rouge_l_is_human_reference_lcs_f1_with_explicit_failure_state(self):
        available = calculate_rouge_l_similarity("alpha beta gamma", "alpha gamma")
        no_overlap = calculate_rouge_l_similarity("alpha", "omega")
        blank = calculate_rouge_l_similarity("alpha", " ")

        self.assertEqual(available["status"], "available")
        self.assertEqual(available["value"], 0.8)
        self.assertEqual(no_overlap["status"], "available")
        self.assertEqual(no_overlap["value"], 0.0)
        self.assertEqual(blank["status"], "unavailable")
        self.assertIsNone(blank["value"])

    def test_combined_similarity_keeps_metrics_separate(self):
        result = evaluate_reference_similarity(
            "alpha beta",
            "alpha beta",
            bertscore_scorer=lambda **kwargs: (None, None, _FakeScores(0.9)),
        )
        self.assertEqual(result["bertscore"]["value"], 0.9)
        self.assertEqual(result["rouge_l"]["value"], 1.0)
        self.assertNotIn("evidence_accuracy", result)

    def test_invented_evidence_accuracy_formula_is_retired(self):
        with self.assertRaisesRegex(NotImplementedError, "retired"):
            calculate_evidence_accuracy(0.2, 0.8)


if __name__ == "__main__":
    unittest.main()
