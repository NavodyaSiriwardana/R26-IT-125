import csv
import json
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from research import evaluate_summarization as cli


def _entry_dict(
    evidence_id="EV-001",
    *,
    entry_date="2026-05-04",
    week_start="2026-05-04",
    week_end="2026-05-10",
):
    timestamp = datetime(2026, 5, 4, tzinfo=timezone.utc).isoformat()
    return {
        "id": int(evidence_id.split("-")[-1]),
        "user_id": "research-user-001",
        "evidence_id": evidence_id,
        "activity_name": "Study",
        "activity_category": "Study",
        "start_time": "09:00",
        "end_time": "10:00",
        "duration_minutes": 60,
        "productivity_level": "High",
        "mood_before": "Stressed",
        "mood_after": "Calm",
        "task_outcome": "Completed",
        "person_names": None,
        "health_status": "Normal",
        "location": "Home",
        "with_whom": "Alone",
        "notes": "Reviewed notes.",
        "entry_date": entry_date,
        "week_start": week_start,
        "week_end": week_end,
        "created_at": timestamp,
        "updated_at": timestamp,
    }


def _case(example_only=False):
    return {
        "case_id": "CASE-001",
        "user_id": "research-user-001",
        "query": "Summarize this week",
        "week_start": "2026-05-04",
        "week_end": "2026-05-10",
        "entries": [_entry_dict()],
        "reference_summary": "The user completed another productive study session.",
        "example_only": example_only,
    }


def _condition(
    *,
    text,
    bertscore_available=True,
    grounded_claim_rate=0.5,
    unsupported_claim_rate=0.5,
):
    return {
        "status": "success",
        "summary_text": text,
        "summary_points": [{"text": text, "citations": []}],
        "latency_ms": 25.0,
        "generation_latency_ms": 15.0,
        "generation": {"status": "success"},
        "evaluation": {
            "status": "available",
            "grounded_claim_rate": grounded_claim_rate,
            "unsupported_claim_rate": unsupported_claim_rate,
        },
        "metrics": {
            "bertscore": {
                "status": "available" if bertscore_available else "unavailable",
                "value": 0.8 if bertscore_available else None,
            },
            "rouge_l": {"status": "available", "value": 0.7},
        },
    }


class ResearchCliTests(unittest.TestCase):
    def test_example_only_dataset_is_never_evaluated(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "example.jsonl"
            path.write_text(json.dumps(_case(example_only=True)) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(cli.DatasetValidationError, "no evaluable cases"):
                cli.load_dataset(path)

    def test_cli_runs_paired_experiment_and_exports_review_files(self):
        experiment = {
            "retrieval": {
                "weekly_entry_count": 1,
                "retrieved_evidence_count": 1,
                "retrieved_evidence_ids": ["EV-001"],
                "retrieval_coverage": 1.0,
            },
            "plain_slm": _condition(
                text="Plain output.",
                bertscore_available=False,
                grounded_claim_rate=0.4,
                unsupported_claim_rate=0.6,
            ),
            "rag": _condition(
                text="Grounded RAG output.",
                grounded_claim_rate=0.8,
                unsupported_claim_rate=0.2,
            ),
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            dataset = root / "cases.jsonl"
            output = root / "results"
            dataset.write_text(json.dumps(_case()) + "\n", encoding="utf-8")
            with patch.object(
                cli,
                "run_summarization_experiment",
                return_value=experiment,
            ) as runner:
                exit_code = cli.run_cli(
                    [
                        str(dataset),
                        "--output-dir",
                        str(output),
                        "--retrieval-mode",
                        "semantic",
                    ]
                )

            self.assertEqual(exit_code, 0)
            runner.assert_called_once()
            self.assertNotIn("history_entries", runner.call_args.kwargs)
            for filename in (
                "case_results.json",
                "case_results.csv",
                "aggregate_results.json",
                "aggregate_results.csv",
                "paired_comparison.json",
                "blind_review.csv",
                "blind_key.json",
            ):
                self.assertTrue((output / filename).is_file())

            case_rows = json.loads(
                (output / "case_results.json").read_text(encoding="utf-8")
            )[0]["condition_metrics"]
            self.assertEqual(set(case_rows), set(cli.CONDITIONS))
            self.assertIsNone(case_rows["plain_slm"]["bertscore"])
            self.assertEqual(case_rows["rag"]["retrieval_coverage"], 1.0)
            self.assertEqual(case_rows["plain_slm"]["grounded_claim_rate"], 0.4)
            self.assertEqual(case_rows["rag"]["grounded_claim_rate"], 0.8)
            self.assertEqual(case_rows["rag"]["unsupported_claim_rate"], 0.2)
            self.assertEqual(case_rows["rag"]["generation_latency_ms"], 15.0)
            self.assertNotIn("citation_precision", case_rows["rag"])

            paired = json.loads(
                (output / "paired_comparison.json").read_text(encoding="utf-8")
            )
            self.assertEqual(
                paired["grounded_claim_rate"]["mean_rag_minus_plain"],
                0.4,
            )
            self.assertEqual(
                paired["unsupported_claim_rate_reduction"]["mean_rag_minus_plain"],
                0.4,
            )

    def test_completed_blind_sheet_maps_scores_back_to_conditions(self):
        case_results = [
            {
                "case_id": "CASE-001",
                "summaries": {"plain_slm": "Plain", "rag": "RAG"},
            }
        ]
        blank_rows, key = cli.build_blind_review(case_results, seed=42)
        row = blank_rows[0]
        row.update(
            factual_accuracy_a="4",
            factual_accuracy_b="5",
            personalization_a="3",
            personalization_b="5",
            query_relevance_a="4",
            query_relevance_b="5",
            preferred_output=(
                "A" if key["CASE-001"]["A"] == "rag" else "B"
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            ratings = Path(directory) / "ratings.csv"
            with ratings.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=cli.BLIND_REVIEW_FIELDS)
                writer.writeheader()
                writer.writerow(row)
            condition_rows, comparison = cli.load_human_ratings(ratings, key)

        self.assertEqual(len(condition_rows), 2)
        self.assertEqual(comparison["preference_counts"]["rag"], 1)
        self.assertEqual(
            comparison["dimensions"]["personalization"]["paired_case_count"],
            1,
        )

    def test_duplicate_weekly_evidence_ids_are_rejected(self):
        invalid = _case()
        invalid["entries"].append(dict(invalid["entries"][0]))
        with self.assertRaisesRegex(cli.DatasetValidationError, "duplicate Evidence IDs"):
            cli.validate_case(invalid, line_number=1)


if __name__ == "__main__":
    unittest.main()
