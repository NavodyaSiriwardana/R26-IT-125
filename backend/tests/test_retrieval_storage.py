import unittest
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

from app.components.rag_summary import chroma_store, date_utils, diary_entry_service
from app.components.rag_summary import firestore_store
from app.components.rag_summary.schemas import DiaryEntryResponse


WEEK_START = "2026-08-24"
WEEK_END = "2026-08-30"


def _entry_dict(
    evidence_id: str,
    *,
    user_id: str = "user-001",
    entry_date: str = WEEK_START,
    week_start: str = WEEK_START,
    week_end: str = WEEK_END,
) -> dict:
    numeric_id = int(evidence_id.rsplit("-", maxsplit=1)[-1])
    timestamp = datetime(2026, 8, 24, 10, numeric_id % 60, tzinfo=timezone.utc)
    return {
        "id": numeric_id,
        "user_id": user_id,
        "evidence_id": evidence_id,
        "activity_name": f"Activity {numeric_id}",
        "activity_category": "Study",
        "start_time": "09:00",
        "end_time": "10:00",
        "duration_minutes": 60,
        "productivity_level": "High",
        "mood_before": "Focused",
        "mood_after": "Happy",
        "task_outcome": "Completed",
        "person_names": None,
        "health_status": "Normal",
        "location": "Home",
        "with_whom": "Alone",
        "notes": "Finished the planned task.",
        "entry_date": entry_date,
        "week_start": week_start,
        "week_end": week_end,
        "created_at": timestamp,
        "updated_at": timestamp,
    }


def _entry(evidence_id: str, **overrides) -> DiaryEntryResponse:
    return DiaryEntryResponse(**_entry_dict(evidence_id, **overrides))


class _Vector:
    def __init__(self, values):
        self.values = values

    def tolist(self):
        return self.values


class _Snapshot:
    def __init__(self, document_id: str, data: dict | None, *, exists: bool = True):
        self.id = document_id
        self.exists = exists
        self._data = data

    def to_dict(self):
        return self._data


class DateUtilsTests(unittest.TestCase):
    def test_validate_week_range_accepts_complete_monday_to_sunday_week(self):
        self.assertEqual(
            date_utils.validate_week_range(WEEK_START, WEEK_END),
            (WEEK_START, WEEK_END),
        )

    def test_validate_week_range_requires_both_or_neither_boundary(self):
        with self.assertRaisesRegex(ValueError, "provided together"):
            date_utils.validate_week_range(WEEK_START, None)

    def test_validate_week_range_rejects_non_week_and_cross_week_ranges(self):
        with self.assertRaisesRegex(ValueError, "start on Monday"):
            date_utils.validate_week_range("2026-08-25", "2026-08-31")

        with self.assertRaisesRegex(ValueError, "same seven-day week"):
            date_utils.validate_week_range("2026-08-24", "2026-09-06")

    def test_validate_week_range_resolves_current_week_only_when_both_are_omitted(self):
        with patch.object(
            date_utils,
            "get_current_week_bounds",
            return_value=(WEEK_START, WEEK_END),
        ):
            self.assertEqual(
                date_utils.validate_week_range(),
                (WEEK_START, WEEK_END),
            )


class ChromaStoreTests(unittest.TestCase):
    def tearDown(self):
        chroma_store._embedding_model = None

    def test_embedding_model_is_lazy_loaded_and_reused(self):
        fake_model = object()

        with patch.object(
            chroma_store,
            "_create_embedding_model",
            return_value=fake_model,
        ) as model_factory:
            first = chroma_store._get_embedding_model()
            second = chroma_store._get_embedding_model()

        self.assertIs(first, fake_model)
        self.assertIs(second, fake_model)
        model_factory.assert_called_once_with()

    def test_weekly_search_filters_user_and_both_week_bounds_before_ranking(self):
        collection = MagicMock()
        collection.query.return_value = {
            "documents": [["canonical document"]],
            "metadatas": [[{"evidence_id": "EV-001"}]],
            "distances": [[0.25]],
        }
        embedding_model = MagicMock()
        embedding_model.encode.return_value = _Vector([0.1, 0.2])

        with (
            patch.object(chroma_store, "_get_collection", return_value=collection),
            patch.object(
                chroma_store,
                "_get_embedding_model",
                return_value=embedding_model,
            ),
        ):
            results = chroma_store.search_diary_entries_for_week(
                user_id="user-001",
                query="project work",
                week_start=WEEK_START,
                week_end=WEEK_END,
                top_k=4,
            )

        query_kwargs = collection.query.call_args.kwargs
        self.assertEqual(query_kwargs["n_results"], 4)
        self.assertEqual(
            query_kwargs["where"],
            {
                "$and": [
                    {"user_id": {"$eq": "user-001"}},
                    {"week_start": {"$eq": WEEK_START}},
                    {"week_end": {"$eq": WEEK_END}},
                ]
            },
        )
        self.assertEqual([item["evidence_id"] for item in results], ["EV-001"])

    def test_general_week_path_uses_every_canonical_entry_without_search(self):
        entries = [
            _entry("EV-002", entry_date="2026-08-25"),
            _entry("EV-001", entry_date="2026-08-24"),
        ]

        with patch.object(chroma_store, "search_diary_entries_for_week") as search:
            evidence = chroma_store.retrieve_weekly_evidence(
                entries,
                user_id="user-001",
                query="Summarize this week",
                week_start=WEEK_START,
                week_end=WEEK_END,
                topic_specific=False,
                top_k=1,
            )

        search.assert_not_called()
        self.assertEqual(
            [item["evidence_id"] for item in evidence],
            ["EV-001", "EV-002"],
        )
        self.assertTrue(all(item["retrieval_method"] == "all_week" for item in evidence))
        self.assertTrue(all("similarity_score" not in item for item in evidence))

    def test_general_week_path_rejects_inconsistent_entry_date(self):
        entry = _entry("EV-001", entry_date="2026-08-31")

        with self.assertRaisesRegex(ValueError, "outside the requested week"):
            chroma_store.build_general_week_evidence(
                [entry],
                user_id="user-001",
                week_start=WEEK_START,
                week_end=WEEK_END,
            )

    def test_topic_path_uses_ranking_but_rebuilds_hits_from_canonical_entries(self):
        entries = [_entry("EV-001"), _entry("EV-002", entry_date="2026-08-25")]
        ranked_results = [
            {
                "evidence_id": "EV-002",
                "content": "stale vector content",
                "metadata": {"user_id": "another-user"},
                "similarity_score": 0.9,
            },
            {
                "evidence_id": "EV-999",
                "content": "unknown vector content",
                "metadata": {},
                "similarity_score": 0.8,
            },
        ]

        with (
            patch.object(
                chroma_store,
                "search_diary_entries_for_week",
                return_value=ranked_results,
            ),
            patch.object(chroma_store, "index_diary_entry") as index_entry,
        ):
            evidence = chroma_store.retrieve_weekly_evidence(
                entries,
                user_id="user-001",
                query="study activities",
                week_start=WEEK_START,
                week_end=WEEK_END,
                topic_specific=True,
                top_k=2,
            )

        self.assertEqual(index_entry.call_count, 2)
        self.assertEqual([item["evidence_id"] for item in evidence], ["EV-002"])
        self.assertIn("Activity 2", evidence[0]["content"])
        self.assertNotIn("stale vector content", evidence[0]["content"])
        self.assertEqual(evidence[0]["metadata"]["user_id"], "user-001")

    def test_retrieval_coverage_counts_unique_in_scope_ids(self):
        self.assertEqual(
            chroma_store.calculate_retrieval_coverage(
                ["EV-001", "EV-001", "EV-999"],
                ["EV-001", "EV-002"],
            ),
            0.5,
        )
        self.assertIsNone(chroma_store.calculate_retrieval_coverage([], []))


class FirestoreStoreTests(unittest.TestCase):
    def _weekly_db(self, snapshots):
        db = MagicMock()
        entries_collection = MagicMock()
        query = MagicMock()
        db.collection.return_value.document.return_value.collection.return_value = (
            entries_collection
        )
        entries_collection.where.return_value = query
        query.stream.return_value = snapshots
        return db

    def test_weekly_list_has_no_implicit_entry_cap(self):
        snapshots = [
            _Snapshot(f"EV-{index:03d}", _entry_dict(f"EV-{index:03d}"))
            for index in range(1, 106)
        ]
        db = self._weekly_db(snapshots)

        with patch.object(firestore_store, "get_firestore_client", return_value=db):
            entries = firestore_store.list_diary_entries_for_week(
                user_id="user-001",
                week_start=WEEK_START,
                week_end=WEEK_END,
            )

        self.assertEqual(len(entries), 105)

    def test_weekly_list_applies_only_an_explicit_limit(self):
        snapshots = [
            _Snapshot("EV-003", _entry_dict("EV-003")),
            _Snapshot("EV-001", _entry_dict("EV-001")),
            _Snapshot("EV-002", _entry_dict("EV-002")),
        ]
        db = self._weekly_db(snapshots)

        with patch.object(firestore_store, "get_firestore_client", return_value=db):
            entries = firestore_store.list_diary_entries_for_week(
                user_id="user-001",
                week_start=WEEK_START,
                week_end=WEEK_END,
                limit=2,
            )

        self.assertEqual([entry["evidence_id"] for entry in entries], ["EV-001", "EV-002"])

    def test_bulk_resolution_enforces_document_user_and_week_and_preserves_order(self):
        db = MagicMock()
        entries_collection = MagicMock()
        db.collection.return_value.document.return_value.collection.return_value = (
            entries_collection
        )
        entries_collection.document.side_effect = lambda evidence_id: f"ref:{evidence_id}"
        db.get_all.return_value = [
            _Snapshot("EV-002", _entry_dict("EV-002")),
            _Snapshot("EV-003", _entry_dict("EV-003", user_id="other-user")),
            _Snapshot(
                "EV-004",
                _entry_dict(
                    "EV-004",
                    week_start="2026-08-17",
                    week_end="2026-08-23",
                ),
            ),
            _Snapshot("EV-001", _entry_dict("EV-001")),
            _Snapshot("EV-999", None, exists=False),
        ]

        with patch.object(firestore_store, "get_firestore_client", return_value=db):
            entries = firestore_store.get_diary_entries_by_evidence_ids(
                user_id="user-001",
                evidence_ids=["EV-001", "EV-002", "EV-003", "EV-004", "EV-999", "EV-001"],
                week_start=WEEK_START,
                week_end=WEEK_END,
            )

        self.assertEqual([entry["evidence_id"] for entry in entries], ["EV-001", "EV-002"])
        db.get_all.assert_called_once_with(
            ["ref:EV-001", "ref:EV-002", "ref:EV-003", "ref:EV-004", "ref:EV-999"]
        )


class DiaryEntryServiceTests(unittest.TestCase):
    def test_week_resolution_returns_typed_authoritative_map(self):
        canonical_entry = _entry_dict("EV-002")

        with patch.object(
            diary_entry_service,
            "get_diary_entries_by_evidence_ids",
            return_value=[canonical_entry],
        ) as bulk_get:
            entries_by_id = diary_entry_service.resolve_user_week_evidence_entries(
                user_id="user-001",
                evidence_ids=["EV-002", "EV-999"],
                week_start=WEEK_START,
                week_end=WEEK_END,
            )

        self.assertEqual(list(entries_by_id), ["EV-002"])
        self.assertIsInstance(entries_by_id["EV-002"], DiaryEntryResponse)
        bulk_get.assert_called_once_with(
            user_id="user-001",
            evidence_ids=["EV-002", "EV-999"],
            week_start=WEEK_START,
            week_end=WEEK_END,
        )


if __name__ == "__main__":
    unittest.main()
