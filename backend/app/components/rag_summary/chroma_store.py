from pathlib import Path
from typing import Iterable, List, Optional, Sequence

import chromadb

from .date_utils import get_week_bounds, validate_week_range
from .schemas import DiaryEntryResponse


CHROMA_DIR = Path("app/data/chroma_db")
COLLECTION_NAME = "rag_diary_entries"
EMBEDDING_MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"

_embedding_model = None


def _create_embedding_model():
    # Keep the heavyweight transformers import out of application startup.
    from sentence_transformers import SentenceTransformer

    return SentenceTransformer(EMBEDDING_MODEL_NAME)


def _get_embedding_model():
    """Lazy-load the embedding model when indexing or retrieval is requested."""

    global _embedding_model

    if _embedding_model is None:
        _embedding_model = _create_embedding_model()

    return _embedding_model


def _get_chroma_client():
    CHROMA_DIR.mkdir(parents=True, exist_ok=True)

    return chromadb.PersistentClient(
        path=str(CHROMA_DIR)
    )


def _get_collection():
    client = _get_chroma_client()

    return client.get_or_create_collection(
        name=COLLECTION_NAME
    )


def build_entry_document(entry: DiaryEntryResponse) -> str:
    notes_text = entry.notes if entry.notes else "No additional notes"
    person_text = (
        entry.specific_person.strip()
        if entry.specific_person and entry.specific_person.strip()
        else "No specific person recorded"
    )
    duration_text = entry.duration.strip() if entry.duration else "Not recorded"

    return (
        f"Evidence ID (Firestore document ID): {entry.evidence_id}. "
        f"User ID: {entry.user_id}. "
        f"Entry date: {entry.entry_date}. "
        f"Week: {entry.week_start} to {entry.week_end}. "
        f"Activity: {entry.activity_name}. "
        f"Category: {entry.activity_category}. "
        f"Start time: {entry.start_time}. "
        f"End time: {entry.end_time}. "
        f"Duration: {duration_text} ({entry.duration_minutes} minutes). "
        f"Time period: {entry.time_period or 'Not recorded'}. "
        f"Productivity level: {entry.productivity_level}. "
        f"Mood before: {entry.mood_before}. "
        f"Mood after: {entry.mood_after}. "
        f"Task outcome: {entry.task_outcome}. "
        f"Health status: {entry.health_status}. "
        f"Location: {entry.location}. "
        f"With whom: {entry.with_whom}. "
        f"Specific person: {person_text}. "
        f"Notes: {notes_text}."
    )


def _build_entry_metadata(entry: DiaryEntryResponse) -> dict:
    metadata = {
        "userId": entry.user_id,
        "evidenceId": entry.evidence_id,
        "entryDate": entry.entry_date,
        "weekStart": entry.week_start,
        "weekEnd": entry.week_end,
        "activityName": entry.activity_name,
        "activityCategory": entry.activity_category,
        "startTime": entry.start_time,
        "endTime": entry.end_time,
        "duration": entry.duration or "",
        "durationMinutes": entry.duration_minutes,
        "timePeriod": entry.time_period or "",
        "productivityLevel": entry.productivity_level,
        "moodBefore": entry.mood_before,
        "moodAfter": entry.mood_after,
        "taskOutcome": entry.task_outcome,
        "specificPerson": entry.specific_person or "",
        "healthStatus": entry.health_status,
        "locationType": entry.location_type or "",
        "customLocation": entry.custom_location or "",
        "resolvedLocation": entry.location,
        "withWhom": entry.with_whom,
        "notes": entry.notes or "",
    }
    if entry.created_at is not None:
        metadata["createdAt"] = entry.created_at.isoformat()
    return metadata


def _canonical_entry_sort_key(entry: DiaryEntryResponse) -> tuple[str, str, str]:
    return entry.entry_date, entry.start_time, entry.evidence_id


def build_general_week_evidence(
    entries: Sequence[DiaryEntryResponse],
    *,
    user_id: str,
    week_start: str,
    week_end: str,
) -> List[dict]:
    """Build evidence from every canonical entry in a requested week.

    This path intentionally performs no semantic ranking and applies no entry cap.
    Scope mismatches are errors rather than silently discarded records.
    """

    resolved_start, resolved_end = validate_week_range(week_start, week_end)
    ordered_entries = sorted(entries, key=_canonical_entry_sort_key)
    output = []
    seen_evidence_ids = set()

    for rank, entry in enumerate(ordered_entries, start=1):
        if entry.user_id != user_id:
            raise ValueError("Canonical weekly evidence contains an entry for another user.")

        if entry.week_start != resolved_start or entry.week_end != resolved_end:
            raise ValueError("Canonical weekly evidence contains an entry from another week.")

        try:
            entry_week_start, entry_week_end = get_week_bounds(entry.entry_date)
        except ValueError as error:
            raise ValueError("Canonical weekly evidence contains an invalid entry date.") from error
        if (entry_week_start, entry_week_end) != (resolved_start, resolved_end):
            raise ValueError(
                "Canonical weekly evidence contains an entry date outside the requested week."
            )

        if entry.evidence_id in seen_evidence_ids:
            raise ValueError(f"Duplicate canonical Evidence ID: {entry.evidence_id}")

        seen_evidence_ids.add(entry.evidence_id)
        output.append(
            {
                "evidence_id": entry.evidence_id,
                "content": build_entry_document(entry),
                "metadata": _build_entry_metadata(entry),
                "retrieval_rank": rank,
                "retrieval_method": "all_week",
            }
        )

    return output


def calculate_retrieval_coverage(
    retrieved_evidence_ids: Iterable[str],
    eligible_evidence_ids: Iterable[str],
) -> Optional[float]:
    """Return unique in-scope retrieved IDs divided by unique eligible IDs.

    An empty eligible set has no defined coverage and therefore returns ``None``.
    Unknown or out-of-scope retrieved IDs never increase the numerator.
    """

    eligible_ids = {evidence_id for evidence_id in eligible_evidence_ids if evidence_id}
    if not eligible_ids:
        return None

    retrieved_ids = {evidence_id for evidence_id in retrieved_evidence_ids if evidence_id}
    represented_ids = retrieved_ids.intersection(eligible_ids)
    return round(len(represented_ids) / len(eligible_ids), 4)


def _get_chroma_document_id(entry: DiaryEntryResponse) -> str:
    """
    Chroma document IDs must be globally unique. The evidence identifier is the
    Firestore document ID, and the user prefix keeps collection scopes isolated.
    """

    return f"{entry.user_id}__{entry.evidence_id}"


def index_diary_entry(entry: DiaryEntryResponse) -> None:
    collection = _get_collection()

    document = build_entry_document(entry)
    embedding = _get_embedding_model().encode(document).tolist()

    collection.upsert(
        ids=[_get_chroma_document_id(entry)],
        documents=[document],
        embeddings=[embedding],
        metadatas=[_build_entry_metadata(entry)],
    )


def search_diary_entries(
    user_id: str,
    query: str,
    top_k: int = 3,
) -> List[dict]:
    """
    Searches only the current user's indexed diary entries.
    """

    collection = _get_collection()

    if top_k <= 0:
        raise ValueError("top_k must be greater than zero.")

    query_embedding = _get_embedding_model().encode(query).tolist()

    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=top_k,
        where={"userId": user_id},
        include=["documents", "metadatas", "distances"],
    )

    documents = results.get("documents", [[]])[0]
    metadatas = results.get("metadatas", [[]])[0]
    distances = results.get("distances", [[]])[0]

    output = []

    for rank, (document, metadata, distance) in enumerate(
        zip(documents, metadatas, distances),
        start=1,
    ):
        similarity_score = 1 / (1 + distance)

        output.append(
            {
                "evidence_id": metadata.get("evidenceId"),
                "content": document,
                "metadata": metadata,
                "similarity_score": round(similarity_score, 4),
                "retrieval_rank": rank,
                "retrieval_method": "semantic",
            }
        )

    return output

def search_diary_entries_for_week(
    user_id: str,
    query: str,
    week_start: str,
    week_end: str,
    top_k: int = 8,
) -> List[dict]:
    """
    Rank entries only after Chroma has constrained the user and complete week.
    """

    resolved_start, resolved_end = validate_week_range(week_start, week_end)

    if top_k <= 0:
        raise ValueError("top_k must be greater than zero.")

    collection = _get_collection()

    query_embedding = _get_embedding_model().encode(query).tolist()

    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=top_k,
        where={
            "$and": [
                {"userId": {"$eq": user_id}},
                {"weekStart": {"$eq": resolved_start}},
                {"weekEnd": {"$eq": resolved_end}},
            ]
        },
        include=["documents", "metadatas", "distances"],
    )

    documents = results.get("documents", [[]])[0]
    metadatas = results.get("metadatas", [[]])[0]
    distances = results.get("distances", [[]])[0]

    output = []

    for rank, (document, metadata, distance) in enumerate(
        zip(documents, metadatas, distances),
        start=1,
    ):
        similarity_score = 1 / (1 + distance)

        output.append(
            {
                "evidence_id": metadata.get("evidenceId"),
                "content": document,
                "metadata": metadata,
                "similarity_score": round(similarity_score, 4),
                "retrieval_rank": rank,
                "retrieval_method": "semantic_week",
            }
        )

    return output


def retrieve_weekly_evidence(
    entries: Sequence[DiaryEntryResponse],
    *,
    user_id: str,
    query: str,
    week_start: str,
    week_end: str,
    topic_specific: bool,
    top_k: int = 8,
) -> List[dict]:
    """Select the explicit all-week or topic-specific retrieval path.

    ``entries`` must be the canonical Firestore records for the requested week.
    Topic retrieval uses Chroma only for ranking, then rebuilds every result from
    the canonical records so stale or invented vector-store IDs are not trusted.
    """

    canonical_evidence = build_general_week_evidence(
        entries,
        user_id=user_id,
        week_start=week_start,
        week_end=week_end,
    )

    if not topic_specific:
        return canonical_evidence

    # Firestore remains canonical, but synchronizing the requested week here
    # ensures older records are actually available to Chroma before querying.
    for entry in entries:
        index_diary_entry(entry)

    ranked_evidence = search_diary_entries_for_week(
        user_id=user_id,
        query=query,
        week_start=week_start,
        week_end=week_end,
        top_k=top_k,
    )
    canonical_by_id = {
        evidence["evidence_id"]: evidence
        for evidence in canonical_evidence
    }
    output = []
    seen_evidence_ids = set()

    for ranked_item in ranked_evidence:
        evidence_id = ranked_item.get("evidence_id")
        if not evidence_id or evidence_id in seen_evidence_ids:
            continue

        canonical_item = canonical_by_id.get(evidence_id)
        if canonical_item is None:
            continue

        seen_evidence_ids.add(evidence_id)
        resolved_item = dict(canonical_item)
        resolved_item.update(
            {
                "similarity_score": ranked_item.get("similarity_score"),
                "retrieval_rank": len(output) + 1,
                "retrieval_method": "semantic_week",
            }
        )
        output.append(resolved_item)

    return output


def rank_week_entries_in_memory(
    entries: Sequence[DiaryEntryResponse],
    *,
    user_id: str,
    query: str,
    week_start: str,
    week_end: str,
    top_k: int = 8,
) -> List[dict]:
    """Rank an already scoped research dataset without relying on Chroma state."""

    if top_k <= 0:
        raise ValueError("top_k must be greater than zero.")

    evidence = build_general_week_evidence(
        entries,
        user_id=user_id,
        week_start=week_start,
        week_end=week_end,
    )
    if not evidence:
        return []

    documents = [item["content"] for item in evidence]
    embeddings = _get_embedding_model().encode(
        [query, *documents],
        normalize_embeddings=True,
    )
    query_embedding = embeddings[0]
    scored = []
    for item, document_embedding in zip(evidence, embeddings[1:]):
        similarity = float(sum(
            float(left) * float(right)
            for left, right in zip(query_embedding, document_embedding)
        ))
        scored.append((similarity, item))

    scored.sort(
        key=lambda pair: (
            -pair[0],
            pair[1]["metadata"]["entryDate"],
            pair[1]["metadata"]["startTime"],
            pair[1]["evidence_id"],
        )
    )
    output = []
    for rank, (similarity, item) in enumerate(scored[:top_k], start=1):
        ranked = dict(item)
        ranked.update(
            similarity_score=round(similarity, 4),
            retrieval_rank=rank,
            retrieval_method="semantic_week_in_memory",
        )
        output.append(ranked)
    return output
