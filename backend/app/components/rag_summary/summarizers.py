"""Shared deterministic FLAN-T5 generation and RAG output parsing.

Plain and RAG conditions intentionally share :func:`generate_text`, one lazy
pipeline instance, and one decoding configuration. Research callers handle
failures explicitly; this module never substitutes a template for model output.
"""

from __future__ import annotations

import re
import threading
import time
import warnings
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Sequence

from app.config import (
    GENERATION_SETTINGS,
    PLAIN_PROMPT_VERSION,
    RAG_PROMPT_VERSION,
    RAG_REGENERATION_PROMPT_VERSION,
)

from .schemas import DiaryEntryResponse


_summarizer_pipeline = None
_generation_lock = threading.Lock()


class GenerationFailure(RuntimeError):
    """Raised when the configured SLM cannot produce usable output."""

    def __init__(self, reason: str, metadata: Dict[str, Any]):
        super().__init__(reason)
        self.reason = reason
        self.metadata = metadata


class RagParsingFailure(RuntimeError):
    """Raised when a generated RAG response contains no parseable claim text."""

    def __init__(
        self,
        reason: str,
        raw_text: str,
        metadata: Optional[Dict[str, Any]] = None,
    ):
        super().__init__(reason)
        self.reason = reason
        self.raw_text = raw_text
        self.metadata = metadata


@dataclass(frozen=True)
class GenerationOutput:
    text: str
    metadata: Dict[str, Any]


@dataclass(frozen=True)
class RagGenerationOutput:
    raw_text: str
    summary_points: List[Dict[str, Any]]
    metadata: Dict[str, Any]
    parsing: Dict[str, Any]


def _get_summarizer_pipeline():
    """Lazily create the single generator shared by every condition."""

    global _summarizer_pipeline
    if _summarizer_pipeline is None:
        from transformers import pipeline

        model_kwargs: Dict[str, Any] = {}
        if GENERATION_SETTINGS.model_revision:
            model_kwargs["revision"] = GENERATION_SETTINGS.model_revision
        _summarizer_pipeline = pipeline(
            task="text2text-generation",
            model=GENERATION_SETTINGS.model_name,
            **model_kwargs,
        )
    return _summarizer_pipeline


def get_shared_decoding_parameters() -> Dict[str, Any]:
    """
    Shared deterministic decoding configuration.

    IMPORTANT:
    Plain and RAG use exactly the same decoding parameters
    so generation settings do not become an experimental confound.
    """

    return {
        "max_new_tokens": GENERATION_SETTINGS.max_new_tokens,
        "do_sample": False,
        "num_beams": GENERATION_SETTINGS.num_beams,

        # Reduce repetitive FLAN-T5 generations.
        "no_repeat_ngram_size": 3,
        "repetition_penalty": 1.15,

        # Prevent beam search from strongly favoring unnecessarily
        # long generations.
        "length_penalty": 1.0,

        "early_stopping": True,
    }

def _resolved_model_revision(generator: Any) -> Optional[str]:
    if GENERATION_SETTINGS.model_revision:
        return GENERATION_SETTINGS.model_revision
    model = getattr(generator, "model", None)
    return getattr(getattr(model, "config", None), "_commit_hash", None)


def _base_generation_metadata(
    *,
    prompt_version: str,
    retrieved_evidence_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    return {
        "status": "unavailable",
        "failure_reason": None,
        "model_name": GENERATION_SETTINGS.model_name,
        "model_revision": GENERATION_SETTINGS.model_revision,
        "prompt_version": prompt_version,
        "decoding_parameters": get_shared_decoding_parameters(),
        "max_input_tokens": GENERATION_SETTINGS.max_input_tokens,
        "random_seed": GENERATION_SETTINGS.random_seed,
        "retrieved_evidence_ids": list(retrieved_evidence_ids or []),
        "latency_ms": None,
        "model_setup_latency_ms": None,
        "model_cache_hit": None,
        "batch_count": 1,
    }


def generate_text(
    prompt: str,
    *,
    prompt_version: str,
    retrieved_evidence_ids: Optional[Sequence[str]] = None,
) -> GenerationOutput:
    """Generate with the one controlled FLAN-T5 model and decoding contract."""

    metadata = _base_generation_metadata(
        prompt_version=prompt_version,
        retrieved_evidence_ids=retrieved_evidence_ids,
    )
    setup_started = time.perf_counter()
    generation_started: Optional[float] = None
    try:
        model_cache_hit = _summarizer_pipeline is not None
        generator = _get_summarizer_pipeline()
        metadata.update(
            model_revision=_resolved_model_revision(generator),
            model_setup_latency_ms=round(
                (time.perf_counter() - setup_started) * 1000,
                3,
            ),
            model_cache_hit=model_cache_hit,
        )
        with _generation_lock:
            from transformers import set_seed

            set_seed(GENERATION_SETTINGS.random_seed)
            generation_started = time.perf_counter()
            result = generator(prompt, **get_shared_decoding_parameters())
        if not result or not isinstance(result, list):
            raise ValueError("generator returned no result")
        generated_text = str(result[0].get("generated_text", "")).strip()
        if not generated_text:
            raise ValueError("generator returned blank text")
        metadata.update(
            status="success",
            latency_ms=round((time.perf_counter() - generation_started) * 1000, 3),
        )
        return GenerationOutput(generated_text, metadata)
    except Exception as error:
        if metadata["model_setup_latency_ms"] is None:
            metadata["model_setup_latency_ms"] = round(
                (time.perf_counter() - setup_started) * 1000,
                3,
            )
        metadata.update(
            status="generation_failed",
            failure_reason=f"model_generation_failed:{type(error).__name__}",
            latency_ms=(
                round((time.perf_counter() - generation_started) * 1000, 3)
                if generation_started is not None
                else None
            ),
        )
        raise GenerationFailure(metadata["failure_reason"], metadata) from error


def _compact_field(value: Any, *, limit: int = 180) -> str:
    text = " ".join(str(value or "").split()).strip()
    if not text:
        return "Not recorded"
    return text if len(text) <= limit else f"{text[: limit - 1].rstrip()}…"


def _duration_context(duration: Any, duration_minutes: Any) -> str:
    stored_duration = " ".join(str(duration or "").split()).strip()
    if stored_duration and duration_minutes is not None:
        return f"{_compact_field(stored_duration)} ({duration_minutes} minutes)"
    if stored_duration:
        return _compact_field(stored_duration)
    if duration_minutes is not None:
        return f"{duration_minutes} minutes"
    return "Not recorded"


def _specific_person_context(specific_person: Any, with_whom: Any) -> str:
    person = " ".join(str(specific_person or "").split()).strip()
    if person:
        return _compact_field(person)
    company = " ".join(str(with_whom or "").split()).strip()
    if company.casefold() == "alone":
        return "Not applicable (alone)"
    return "Not recorded"


def _resolved_metadata_location(metadata: Dict[str, Any]) -> Any:
    resolved = metadata.get("resolvedLocation")
    if resolved:
        return resolved
    location_type = metadata.get("locationType")
    custom_location = metadata.get("customLocation")
    if (
        str(location_type or "").strip().casefold() == "other"
        and str(custom_location or "").strip()
    ):
        return custom_location
    return location_type


def _plain_entry_block(entry: DiaryEntryResponse, index: int) -> str:
    return (
        f"{index}. On {entry.entry_date}, activity: {_compact_field(entry.activity_name)} "
        f"({_compact_field(entry.activity_category)}). Start time: "
        f"{_compact_field(entry.start_time)}. End time: {_compact_field(entry.end_time)}. "
        f"Duration: {_duration_context(entry.duration, entry.duration_minutes)}. "
        f"Time period: {_compact_field(entry.time_period)}. "
        f"Productivity: {_compact_field(entry.productivity_level)}. "
        f"Mood before: {_compact_field(entry.mood_before)}. "
        f"Mood after: {_compact_field(entry.mood_after)}. "
        f"Outcome: {_compact_field(entry.task_outcome)}. "
        f"Health: {_compact_field(entry.health_status)}. "
        f"Location: {_compact_field(entry.location)}. "
        f"With whom: {_compact_field(entry.with_whom)}. "
        f"Specific person: "
        f"{_specific_person_context(entry.specific_person, entry.with_whom)}. "
        f"Notes: {_compact_field(entry.notes)}."
    )


def build_plain_slm_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
) -> str:
    """
    Plain SLM experimental condition.

    This condition receives the same complete-week coverage requirement
    as RAG, but without retrieval/citation grounding.
    """

    return (
        "Write one natural, coherent paragraph that answers the user query "
        "using only the supplied weekly diary entries. "

        "This is a complete-week summary. Represent every supplied diary "
        "entry at least once, while combining related activities naturally. "

        "Do not invent, assume, infer, or add facts that are not explicitly "
        "recorded in the diary entries. "

        "Mention the specific activity when describing productivity, mood, "
        "location, people, or task outcome. Avoid vague statements such as "
        "'the activity was completed' when the activity can be named. "

        "Use 'The user' consistently when referring to the diary owner. "
        "Never use 'I', 'we', 'the student', 'the author', 'he', or 'she'. "

        "Avoid unnecessary repetition. Do not repeat the same fact in "
        "different wording. "

        "Do not use headings, bullet points, numbered lists, field labels, "
        "or repeated 'This week' phrases. "

        "Produce only the final paragraph.\n\n"

        f"User query: {query.strip()}\n\n"

        "Complete weekly diary evidence:\n"
        + "\n\n".join(blocks)

        + "\n\nComplete-week summary:"
    )

def build_plain_consolidation_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
) -> str:
    return (
        "Combine the draft weekly summaries below into one smooth, coherent paragraph "
        "that answers the query. Remove repetition and do not introduce facts that are "
        "not already present in the drafts. Do not use bullets, headings, numbered "
        "points, or label prefixes.\n\n"
        f"User query: {query.strip()}\n\nDraft summaries:\n"
        + "\n\n".join(blocks)
        + "\n\nFinal one-paragraph weekly summary:"
    )


def build_plain_slm_input(entries: List[DiaryEntryResponse], query: str) -> str:
    """Build the direct condition prompt without evidence-ID instructions."""

    blocks = [_plain_entry_block(entry, index) for index, entry in enumerate(entries, 1)]
    return build_plain_slm_prompt_from_blocks(blocks, query)


def _metadata_from_evidence(evidence: Dict[str, Any]) -> Dict[str, Any]:
    metadata = evidence.get("metadata")
    return metadata if isinstance(metadata, dict) else {}


def _evidence_id(evidence: Dict[str, Any]) -> str:
    metadata = _metadata_from_evidence(evidence)
    return str(evidence.get("evidence_id") or metadata.get("evidenceId") or "").strip()

def _evidence_sort_key(
    evidence: Dict[str, Any],
) -> tuple[str, str, str]:
    """
    Stable chronological ordering for weekly evidence.

    Whole-week summaries should follow diary chronology rather than
    vector-search relevance order.
    """

    metadata = _metadata_from_evidence(evidence)

    return (
        str(metadata.get("entryDate") or ""),
        str(metadata.get("startTime") or ""),
        _evidence_id(evidence),
    )


def _deduplicate_retrieved_evidence(
    evidence_items: Sequence[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """
    Remove duplicated retrieved Firestore documents using evidence/document ID.
    """

    result: List[Dict[str, Any]] = []
    seen: set[str] = set()

    for item in evidence_items:
        evidence_id = _evidence_id(item).strip()

        if not evidence_id:
            result.append(item)
            continue

        normalized = evidence_id.casefold()

        if normalized in seen:
            continue

        seen.add(normalized)
        result.append(item)

    return result


def _prepare_weekly_evidence(
    evidence_items: Sequence[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """
    Deduplicate and chronologically order retrieved diary evidence.
    """

    unique = _deduplicate_retrieved_evidence(
        evidence_items
    )

    return sorted(
        unique,
        key=_evidence_sort_key,
    )

def _deduplicate_retrieved_evidence(
    evidence_items: Sequence[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """
    Prevent the same Firestore diary entry from being supplied to the
    generator multiple times.

    Evidence is deduplicated by its stable evidence/document ID.
    """

    result: List[Dict[str, Any]] = []
    seen_ids: set[str] = set()

    for item in evidence_items:
        evidence_id = _evidence_id(item)

        # Preserve entries without IDs rather than silently dropping them.
        if not evidence_id:
            result.append(item)
            continue

        normalized_id = evidence_id.casefold()

        if normalized_id in seen_ids:
            continue

        seen_ids.add(normalized_id)
        result.append(item)

    return result

def build_rag_evidence_block(
    evidence: Dict[str, Any],
    source_number: Optional[int] = None,
) -> str:
    """
    Convert one retrieved diary record into compact canonical evidence.

    Keeps information useful for summarization while reducing prompt noise.
    """

    metadata = _metadata_from_evidence(evidence)

    source_label = (
        f"Source [{source_number}]"
        if source_number is not None
        else "Source"
    )

    activity = _compact_field(
        metadata.get("activityName")
    )

    category = _compact_field(
        metadata.get("activityCategory")
    )

    productivity = _compact_field(
        metadata.get("productivityLevel")
    )

    mood_before = _compact_field(
        metadata.get("moodBefore")
    )

    mood_after = _compact_field(
        metadata.get("moodAfter")
    )

    outcome = _compact_field(
        metadata.get("taskOutcome")
    )

    location = _compact_field(
        _resolved_metadata_location(metadata)
    )

    with_whom = _compact_field(
        metadata.get("withWhom")
    )

    notes = _compact_field(
        metadata.get("notes"),
        limit=140,
    )

    evidence_id = _evidence_id(evidence)

    return (
        f"{source_label} | "
        f"[EVIDENCE_ID: {evidence_id}] | "
        f"Activity: {activity} | "
        f"Category: {category} | "
        f"Productivity: {productivity} | "
        f"Mood: {mood_before} -> {mood_after} | "
        f"Outcome: {outcome} | "
        f"Location: {location} | "
        f"With whom: {with_whom} | "
        f"Notes: {notes}"
    )


def build_rag_slm_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
    *,
    require_full_coverage: bool = False,
) -> str:
    """
    Build the grounded RAG generation prompt.
    """

    if require_full_coverage:
        coverage_instruction = (
            "This is a complete-week summary. Try to represent every supplied "
            "source at least once while naturally combining related activities. "
        )
    else:
        coverage_instruction = (
            "Use only the supplied sources that are relevant to the query. "
        )

    return (
        "Write one natural, coherent paragraph that answers the user query "
        "using only the retrieved diary evidence below. "

        "Every factual statement must be directly supported by the supplied "
        "evidence. If a detail is not explicitly recorded, omit it. "
        "Do not guess, infer, or add information. "

        f"{coverage_instruction}"

        "Mention the specific activity when describing productivity, mood, "
        "location, people, or outcomes. Avoid vague statements such as "
        "'the activity was completed' when the activity can be named. "

        "Use 'The user' consistently when referring to the diary owner. "
        "Never use 'I', 'we', 'the student', 'the author', 'he', or 'she'. "

        "Avoid repetition. State each factual detail only once unless repetition "
        "is necessary to distinguish different diary entries. "

        "When multiple facts belong to the same diary entry, combine them into "
        "one concise sentence where possible. "

        "After each factual sentence, place one or more compact source markers "
        "that support that sentence before its final punctuation. "
        "Example: 'The user studied database concepts at home [2].' "

        "Never reveal internal EVIDENCE_ID values. "

        "Do not use headings, bullet points, numbered lists, field labels, "
        "dates unless required by the query, or repeated 'This week' phrases. "

        "Produce only the final grounded paragraph.\n\n"

        f"User query: {query.strip()}\n\n"

        "Retrieved diary evidence:\n"
        + "\n\n".join(blocks)

        + "\n\nGrounded complete-week summary:"
    )


def build_rag_consolidation_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
) -> str:
    return (
        "Combine the grounded draft summaries below into one smooth, coherent paragraph "
        "that answers the query. Preserve every compact source marker and the fact it "
        "supports; do not drop a represented source. Preserve only facts stated in the "
        "drafts, remove repetition, and add no new details or explanations. Keep compact "
        "source markers before the final punctuation of their supported sentences. Do "
        "not use bullets, headings, "
        "numbered points, or label prefixes.\n\n"
        f"User query: {query.strip()}\n\nGrounded draft summaries:\n"
        + "\n\n".join(blocks)
        + "\n\nFinal grounded one-paragraph weekly summary:"
    )


def build_rag_slm_input(retrieved_evidence: List[Dict[str, Any]], query: str) -> str:
    return build_rag_slm_prompt_from_blocks(
        [
            build_rag_evidence_block(item, source_number=index)
            for index, item in enumerate(retrieved_evidence, 1)
        ],
        query,
    )


def build_rag_regeneration_prompt(
    retrieved_evidence: List[Dict[str, Any]],
    query: str,
    unsupported_claims: Sequence[str],
) -> str:
    blocks = [build_rag_evidence_block(item) for item in retrieved_evidence]
    return build_rag_regeneration_prompt_from_blocks(
        blocks,
        query,
        unsupported_claims,
    )


def build_rag_regeneration_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
    unsupported_claims: Sequence[str],
) -> str:
    claims = "\n".join(f"- {claim}" for claim in unsupported_claims)
    return (
        "Rewrite only the unsupported diary claims below as complete descriptive "
        "sentences using the supplied evidence. Omit a claim if the evidence cannot "
        "support a corrected version. Put one sentence on each line, then copy one or "
        "more supporting evidence markers exactly as they appear below. Never return "
        "an evidence marker without a sentence and do not add commentary.\n\n"
        f"User query: {query.strip()}\n\nUnsupported claims:\n{claims}\n\n"
        "Evidence blocks:\n"
        + "\n\n".join(blocks)
        + "\n\nCorrected claims:"
    )


def build_rag_coverage_repair_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
) -> str:
    """
    Production-only repair of sources omitted from a RAG summary.
    """

    return (
        "Write exactly one concise factual sentence for each supplied diary "
        "source. "

        "The sentence must explicitly identify the specific recorded activity. "

        "Never write vague statements such as 'The activity was completed', "
        "'The task was completed', or 'The activity was successful'. "

        "If an outcome is important, state it together with the activity name. "

        "Use only facts explicitly recorded in the supplied evidence. "
        "Do not infer or add anything. "

        "Use 'The user' consistently as the subject. "
        "Never use 'I', 'the student', 'the author', 'he', or 'she'. "

        "Place the source marker before the final punctuation. "

        "Do not reveal internal EVIDENCE_ID values. "
        "Do not use headings, bullets, commentary, or repeated phrases.\n\n"

        f"User query: {query.strip()}\n\n"

        "Missing diary evidence:\n"
        + "\n\n".join(blocks)

        + "\n\nGrounded missing-source sentence:"
    )

def _prompt_token_count(prompt: str) -> int:
    try:
        tokenizer = getattr(_get_summarizer_pipeline(), "tokenizer", None)
        if tokenizer is None:
            raise AttributeError("generator has no tokenizer")
        # ``verbose=False`` avoids the tokenizer's misleading overlength warning
        # while we are only measuring the prompt before splitting it.
        encoded = tokenizer(
            prompt,
            add_special_tokens=True,
            truncation=False,
            verbose=False,
        )
        return len(encoded.get("input_ids", []))
    except Exception:
        # Conservative deterministic estimate for mocked/offline test pipelines.
        return max(1, (len(prompt) + 2) // 3)


def _split_oversized_block(
    block: str,
    query: str,
    prompt_builder: Callable[[Sequence[str], str], str],
) -> List[str]:
    words = block.split()
    if not words:
        return []
    header_match = re.match(
        r"((?:Source\s+\[\d+\]\s*\|\s*)?"
        r"\[EVIDENCE_ID:\s*[^\]]+\])",
        block,
        re.IGNORECASE,
    )
    repeated_header = header_match.group(1) if header_match else ""
    chunks: List[str] = []
    current: List[str] = []
    for word in words:
        candidate_words = current + [word]
        candidate = " ".join(candidate_words)
        if repeated_header and not candidate.startswith(repeated_header):
            candidate = f"{repeated_header}\n{candidate}"
        if current and _prompt_token_count(prompt_builder([candidate], query)) > GENERATION_SETTINGS.max_input_tokens:
            chunk = " ".join(current)
            if repeated_header and not chunk.startswith(repeated_header):
                chunk = f"{repeated_header}\n{chunk}"
            chunks.append(chunk)
            current = [word]
        else:
            current = candidate_words
    if current:
        chunk = " ".join(current)
        if repeated_header and not chunk.startswith(repeated_header):
            chunk = f"{repeated_header}\n{chunk}"
        chunks.append(chunk)
    return chunks


def _batch_blocks(
    blocks: Sequence[str],
    query: str,
    prompt_builder: Callable[[Sequence[str], str], str],
) -> List[List[str]]:
    expanded: List[str] = []
    for block in blocks:
        if _prompt_token_count(prompt_builder([block], query)) <= GENERATION_SETTINGS.max_input_tokens:
            expanded.append(block)
        else:
            expanded.extend(_split_oversized_block(block, query, prompt_builder))
    batches: List[List[str]] = []
    current: List[str] = []
    for block in expanded:
        candidate = current + [block]
        if current and _prompt_token_count(prompt_builder(candidate, query)) > GENERATION_SETTINGS.max_input_tokens:
            batches.append(current)
            current = [block]
        else:
            current = candidate
    if current:
        batches.append(current)
    return batches


def _aggregate_generation_metadata(
    calls: Sequence[Dict[str, Any]],
    *,
    prompt_version: str,
    retrieved_evidence_ids: Optional[Sequence[str]] = None,
) -> Dict[str, Any]:
    metadata = _base_generation_metadata(
        prompt_version=prompt_version,
        retrieved_evidence_ids=retrieved_evidence_ids,
    )
    latencies = [item.get("latency_ms") for item in calls]
    complete_latency = (
        round(sum(float(value) for value in latencies), 3)
        if calls and all(value is not None for value in latencies)
        else None
    )
    setup_latencies = [item.get("model_setup_latency_ms") for item in calls]
    complete_setup_latency = (
        round(sum(float(value) for value in setup_latencies), 3)
        if calls and all(value is not None for value in setup_latencies)
        else None
    )
    metadata.update(
        status="success",
        model_revision=next(
            (item.get("model_revision") for item in calls if item.get("model_revision")),
            None,
        ),
        latency_ms=complete_latency,
        model_setup_latency_ms=complete_setup_latency,
        model_cache_hit=all(item.get("model_cache_hit") is True for item in calls),
        batch_count=len(calls),
        calls=list(calls),
    )
    return metadata


_PARAGRAPH_LABEL_RE = re.compile(
    r"\b(?:this\s+week|earlier\s+in\s+your\s+diary|weekly\s+highlight|diary\s+reflection)\s*:\s*",
    re.IGNORECASE,
)
_LINE_PREFIX_RE = re.compile(r"^\s*(?:[-*]\s+|\d+[.)]\s+)")


def _normalize_generated_paragraph(
    text: str,
    *,
    strip_citations: bool = True,
) -> str:
    """Turn model formatting into one display paragraph without changing facts."""

    lines = []
    for raw_line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        line = _LINE_PREFIX_RE.sub("", raw_line).strip()
        if line:
            lines.append(line)
    paragraph = " ".join(lines)
    paragraph = _PARAGRAPH_LABEL_RE.sub("", paragraph)
    if strip_citations:
        paragraph = _remove_citation_tokens(paragraph)
    return " ".join(paragraph.split()).strip()


def _consolidate_drafts(
    drafts: Sequence[str],
    *,
    query: str,
    prompt_builder: Callable[[Sequence[str], str], str],
    prompt_version: str,
    calls: List[Dict[str, Any]],
    retrieved_evidence_ids: Optional[Sequence[str]] = None,
    preserve_citations: bool = False,
) -> str:
    """Reduce any number of batch drafts to one model-written paragraph."""

    current = [
        _normalize_generated_paragraph(
            item,
            strip_citations=not preserve_citations,
        )
        for item in drafts
        if item.strip()
    ]
    while len(current) > 1:
        batches = _batch_blocks(current, query, prompt_builder)
        reduced: List[str] = []
        for batch in batches:
            output = generate_text(
                prompt_builder(batch, query),
                prompt_version=prompt_version,
                retrieved_evidence_ids=retrieved_evidence_ids,
            )
            calls.append(output.metadata)
            reduced.append(
                _normalize_generated_paragraph(
                    output.text,
                    strip_citations=not preserve_citations,
                )
            )
        if len(reduced) >= len(current):
            raise GenerationFailure(
                "summary_consolidation_did_not_reduce",
                _aggregate_generation_metadata(
                    calls,
                    prompt_version=prompt_version,
                    retrieved_evidence_ids=retrieved_evidence_ids,
                ),
            )
        current = reduced
    return current[0] if current else ""


def generate_plain_slm_summary_result(
    entries: List[DiaryEntryResponse],
    query: str,
) -> GenerationOutput:
    if not entries:
        metadata = _base_generation_metadata(prompt_version=PLAIN_PROMPT_VERSION)
        metadata.update(status="not_applicable", failure_reason="no_source_entries", batch_count=0)
        raise GenerationFailure("no_source_entries", metadata)
    blocks = [_plain_entry_block(entry, index) for index, entry in enumerate(entries, 1)]
    batches = _batch_blocks(blocks, query, build_plain_slm_prompt_from_blocks)
    outputs: List[str] = []
    calls: List[Dict[str, Any]] = []
    for batch in batches:
        output = generate_text(
            build_plain_slm_prompt_from_blocks(batch, query),
            prompt_version=PLAIN_PROMPT_VERSION,
        )
        outputs.append(output.text)
        calls.append(output.metadata)
    paragraph = _consolidate_drafts(
        outputs,
        query=query,
        prompt_builder=build_plain_consolidation_prompt_from_blocks,
        prompt_version=PLAIN_PROMPT_VERSION,
        calls=calls,
    )
    if not paragraph:
        metadata = _aggregate_generation_metadata(
            calls,
            prompt_version=PLAIN_PROMPT_VERSION,
        )
        metadata.update(status="generation_failed", failure_reason="blank_summary")
        raise GenerationFailure("blank_summary", metadata)
    return GenerationOutput(
        paragraph,
        _aggregate_generation_metadata(calls, prompt_version=PLAIN_PROMPT_VERSION),
    )


def generate_plain_slm_summary(entries: List[DiaryEntryResponse], query: str) -> str:
    """Compatibility wrapper that still fails explicitly in research mode."""

    return generate_plain_slm_summary_result(entries, query).text


_EXPLICIT_EVIDENCE_RE = re.compile(r"\[\s*EVIDENCE_ID\s*:\s*([^\]]+)\]", re.IGNORECASE)
_SHORT_EVIDENCE_RE = re.compile(r"\[\s*((?:EV|EVIDENCE)[-_][^\]]+)\]", re.IGNORECASE)
_NUMERIC_CITATION_RE = re.compile(
    r"\[\s*(\d+(?:\s*[,;]\s*\d+)*)\s*\]"
)
_CLAIM_PREFIX_RE = re.compile(
    r"^\s*(?:[-*]\s*)?(?:\d+[.)]\s*)?(?:claim\s*:\s*)?",
    re.IGNORECASE,
)


def _citation_tokens(raw_text: str) -> List[tuple[str, str]]:
    matches: List[tuple[int, str, str]] = []
    occupied: List[tuple[int, int]] = []
    for match in _EXPLICIT_EVIDENCE_RE.finditer(raw_text):
        occupied.append(match.span())
        for token in re.split(r"[,;\s]+", match.group(1).strip()):
            if token:
                matches.append((match.start(), token.strip(), match.group(0)))
    for match in _SHORT_EVIDENCE_RE.finditer(raw_text):
        if any(start <= match.start() < end for start, end in occupied):
            continue
        for token in re.split(r"[,;\s]+", match.group(1).strip()):
            if token:
                matches.append((match.start(), token, match.group(0)))
    for match in _NUMERIC_CITATION_RE.finditer(raw_text):
        if any(start <= match.start() < end for start, end in occupied):
            continue
        for token in re.split(r"\s*[,;]\s*", match.group(1)):
            if token:
                matches.append((match.start(), token, match.group(0)))
    ordered: List[tuple[str, str]] = []
    seen = set()
    for _, token, label in sorted(matches, key=lambda item: item[0]):
        if token.upper() not in seen:
            ordered.append((token, label))
            seen.add(token.upper())
    return ordered


def _remove_citation_tokens(raw_text: str) -> str:
    cleaned = _EXPLICIT_EVIDENCE_RE.sub("", raw_text)
    cleaned = _SHORT_EVIDENCE_RE.sub("", cleaned)
    cleaned = _NUMERIC_CITATION_RE.sub("", cleaned)
    cleaned = " ".join(cleaned.split()).strip()
    return re.sub(r"\s+([.,!?;:])", r"\1", cleaned)


def _split_generated_claims(raw_text: str) -> List[str]:
    normalized = raw_text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not normalized:
        return []
    # Small models sometimes put a requested marker just after the period. Move
    # it back onto the preceding sentence before sentence segmentation.
    normalized = re.sub(
        r"([.!?])\s+((?:\[[^\[\]]+\]\s*)+)(?=[A-Z0-9]|$)",
        r" \2\1 ",
        normalized,
    ).strip()
    claims: List[str] = []
    for line in (line.strip() for line in normalized.split("\n") if line.strip()):
        parts = re.split(
            r"(?<=[.!?])\s+(?=(?:[-*]\s*)?(?:\d+[.)]\s*)?(?:Claim\s*:\s*)?[A-Z0-9])",
            line,
        )
        claims.extend(part.strip() for part in parts if part.strip())
    return claims


def _source_preview(evidence: Dict[str, Any]) -> str:
    metadata = _metadata_from_evidence(evidence)
    return " | ".join(
        value
        for value in (
            str(metadata.get("entryDate") or ""),
            str(metadata.get("activityName") or ""),
            str(metadata.get("taskOutcome") or ""),
        )
        if value
    )


def parse_rag_output(
    raw_text: str,
    retrieved_evidence: List[Dict[str, Any]],
    *,
    retain_citations: bool = True,
    source_aliases: Optional[Dict[str, str]] = None,
) -> tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """Parse model claims while retaining invented IDs as visibly invalid."""

    allowed = {
        _evidence_id(item): item
        for item in retrieved_evidence
        if _evidence_id(item)
    }
    resolved_source_aliases = (
        {
            str(index): _evidence_id(item)
            for index, item in enumerate(retrieved_evidence, 1)
            if _evidence_id(item)
        }
        if source_aliases is None
        else {
            str(alias).strip(): str(evidence_id).strip()
            for alias, evidence_id in source_aliases.items()
            if str(alias).strip() and str(evidence_id).strip()
        }
    )
    points: List[Dict[str, Any]] = []
    unknown_ids: List[str] = []
    for index, raw_claim in enumerate(_split_generated_claims(raw_text), 1):
        text = _CLAIM_PREFIX_RE.sub("", _remove_citation_tokens(raw_claim)).strip()
        if not text:
            continue
        citations = []
        for citation_index, (generated_id, label) in enumerate(_citation_tokens(raw_claim), 1):
            resolved_evidence_id = resolved_source_aliases.get(
                generated_id,
                generated_id,
            )
            evidence = allowed.get(resolved_evidence_id)
            valid = evidence is not None
            if not valid and resolved_evidence_id not in unknown_ids:
                unknown_ids.append(resolved_evidence_id)
            if retain_citations:
                citations.append(
                    {
                        "citation_id": f"CIT-{index:03d}-{citation_index:02d}",
                        "evidence_id": resolved_evidence_id,
                        "label": label,
                        "source_preview": _source_preview(evidence) if evidence else "Unknown Evidence ID",
                        "source_type": "diary_entry",
                        "is_valid": valid,
                        "validation_error": None if valid else "evidence_id_not_supplied_to_model",
                    }
                )
        points.append({"claim_id": f"CLM-{index:03d}", "text": text, "citations": citations})
    if not points:
        raise RagParsingFailure("no_parseable_claims", raw_text)
    represented_evidence_ids = list(
        dict.fromkeys(
            citation["evidence_id"]
            for point in points
            for citation in point["citations"]
            if citation.get("is_valid") and citation.get("evidence_id")
        )
    )
    parsing = {
        "status": "success",
        "failure_reason": None,
        "claim_count": len(points),
        "unknown_evidence_ids": unknown_ids,
        "uncited_claim_count": sum(1 for point in points if not point["citations"]),
        "represented_evidence_ids": represented_evidence_ids,
    }
    return points, parsing


def _evidence_for_batch(
    batch: Sequence[str],
    evidence: Sequence[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    ids = {
        match.group(1).strip().upper()
        for block in batch
        if (match := re.search(r"\[EVIDENCE_ID:\s*([^\]]+)\]", block, re.IGNORECASE))
    }
    return [item for item in evidence if _evidence_id(item).upper() in ids]


def _represented_evidence_ids(points: Sequence[Dict[str, Any]]) -> List[str]:
    return list(
        dict.fromkeys(
            str(citation.get("evidence_id") or "").strip()
            for point in points
            for citation in point.get("citations") or []
            if citation.get("is_valid") is not False
            and str(citation.get("evidence_id") or "").strip()
        )
    )

def _claim_dedup_key(text: str) -> str:
    """
    Create a deterministic comparison key for generated claims.

    This removes superficial differences such as capitalization,
    punctuation, and repeated whitespace without changing the
    actual displayed claim.
    """

    normalized = str(text or "").casefold().strip()

    # Remove punctuation while preserving letters/numbers/words.
    normalized = re.sub(r"[^\w\s]", " ", normalized)

    # Collapse whitespace.
    normalized = re.sub(r"\s+", " ", normalized).strip()

    return normalized


def _merge_duplicate_rag_points(
    points: Sequence[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """
    Merge duplicate generated claims while preserving all evidence citations.

    Example:

        The activity was completed. -> source A
        The activity was completed. -> source B

    becomes one claim associated with sources A and B.

    No model-generated facts are rewritten or invented here.
    """

    merged: Dict[str, Dict[str, Any]] = {}
    order: List[str] = []

    for point in points:
        text = str(point.get("text") or "").strip()

        if not text:
            continue

        key = _claim_dedup_key(text)

        if not key:
            continue

        citations = list(point.get("citations") or [])

        if key not in merged:
            merged[key] = {
                "claim_id": point.get("claim_id"),
                "text": text,
                "citations": [],
            }
            order.append(key)

        target = merged[key]

        citation_index_by_evidence_id = {
            str(citation.get("evidence_id") or "").strip(): index
            for index, citation in enumerate(target["citations"])
            if str(citation.get("evidence_id") or "").strip()
        }

        for citation in citations:
            evidence_id = str(citation.get("evidence_id") or "").strip()

            if evidence_id:
                existing_index = citation_index_by_evidence_id.get(evidence_id)
                if existing_index is not None:
                    existing = target["citations"][existing_index]
                    if (
                        existing.get("is_valid") is False
                        and citation.get("is_valid") is not False
                    ):
                        target["citations"][existing_index] = dict(citation)
                    continue
                citation_index_by_evidence_id[evidence_id] = len(
                    target["citations"]
                )

            # Preserve uncited/invalid citation metadata too.
            target["citations"].append(dict(citation))

    merged_points = [merged[key] for key in order]

    _renumber_rag_points(merged_points)

    return merged_points


def _renumber_rag_points(points: List[Dict[str, Any]]) -> None:
    for claim_index, point in enumerate(points, 1):
        point["claim_id"] = f"CLM-{claim_index:03d}"
        for citation_index, citation in enumerate(point.get("citations") or [], 1):
            citation["citation_id"] = f"CIT-{claim_index:03d}-{citation_index:02d}"


def _single_source_citation(
    evidence: Dict[str, Any],
    *,
    claim_index: int,
    citation_index: int,
) -> Dict[str, Any]:
    return {
        "citation_id": f"CIT-{claim_index:03d}-{citation_index:02d}",
        "evidence_id": _evidence_id(evidence),
        "label": "[1]",
        "source_preview": _source_preview(evidence),
        "source_type": "diary_entry",
        "is_valid": True,
        "validation_error": None,
    }


def generate_rag_slm_summary(
    retrieved_evidence: List[Dict[str, Any]],
    query: str,
    *,
    require_full_coverage: bool = False,
    repair_missing_coverage: bool = False,
) -> RagGenerationOutput:
    """
    Generate a grounded RAG weekly summary.

    Research mode:
        require_full_coverage=True
        repair_missing_coverage=False

    This asks the model to cover the complete week but does NOT perform
    extra generation calls to artificially force 100% answer coverage.

    That makes answer coverage an observed experimental metric rather
    than something the pipeline guarantees after generation.
    """

    if not retrieved_evidence:
        metadata = _base_generation_metadata(
            prompt_version=RAG_PROMPT_VERSION
        )

        metadata.update(
            status="not_applicable",
            failure_reason="no_retrieved_evidence",
            batch_count=0,
        )

        raise GenerationFailure(
            "no_retrieved_evidence",
            metadata,
        )

    # ---------------------------------------------------------
    # Clean and chronologically order evidence.
    # ---------------------------------------------------------

    retrieved_evidence = _prepare_weekly_evidence(
        retrieved_evidence
    )

    evidence_ids = [
        _evidence_id(item)
        for item in retrieved_evidence
        if _evidence_id(item)
    ]
    source_aliases = {
        str(index): evidence_id
        for index, evidence_id in enumerate(evidence_ids, 1)
    }

    blocks = [
        build_rag_evidence_block(
            item,
            source_number=index,
        )
        for index, item in enumerate(
            retrieved_evidence,
            1,
        )
    ]

    def prompt_builder(
        batch: Sequence[str],
        batch_query: str,
    ) -> str:
        return build_rag_slm_prompt_from_blocks(
            batch,
            batch_query,
            require_full_coverage=require_full_coverage,
        )

    batches = _batch_blocks(
        blocks,
        query,
        prompt_builder,
    )

    calls: List[Dict[str, Any]] = []
    points: List[Dict[str, Any]] = []
    parsing_parts: List[Dict[str, Any]] = []

    # ---------------------------------------------------------
    # Primary RAG generation.
    # ---------------------------------------------------------

    for batch in batches:
        batch_evidence = _evidence_for_batch(
            batch,
            retrieved_evidence,
        )

        batch_ids = [
            _evidence_id(item)
            for item in batch_evidence
            if _evidence_id(item)
        ]

        output = generate_text(
            prompt_builder(
                batch,
                query,
            ),
            prompt_version=RAG_PROMPT_VERSION,
            retrieved_evidence_ids=batch_ids,
        )

        calls.append(
            output.metadata
        )

        try:
            parsed, parsing = parse_rag_output(
                output.text,

                # IMPORTANT:
                # validate citations only against evidence actually
                # supplied to this specific generation call.
                batch_evidence,
                source_aliases=source_aliases,
            )

        except RagParsingFailure as error:
            raise RagParsingFailure(
                error.reason,
                error.raw_text,
                output.metadata,
            ) from error

        points.extend(parsed)
        parsing_parts.append(parsing)

    # ---------------------------------------------------------
    # Deterministic duplicate removal.
    # ---------------------------------------------------------

    points = _merge_duplicate_rag_points(
        points
    )

    represented_ids = _represented_evidence_ids(
        points
    )

    represented_id_set = set(
        represented_ids
    )

    missing_ids = [
        evidence_id
        for evidence_id in evidence_ids
        if evidence_id not in represented_id_set
    ]

    repaired_ids: List[str] = []

    # ---------------------------------------------------------
    # OPTIONAL PRODUCTION-ONLY coverage repair.
    #
    # DO NOT enable this for the RAG-vs-Plain research experiment.
    # ---------------------------------------------------------

    if (
        require_full_coverage
        and repair_missing_coverage
        and missing_ids
    ):
        evidence_by_id = {
            _evidence_id(item): item
            for item in retrieved_evidence
            if _evidence_id(item)
        }

        for missing_id in missing_ids:
            evidence = evidence_by_id.get(
                missing_id
            )

            if evidence is None:
                continue

            repair_block = build_rag_evidence_block(
                evidence,
                source_number=1,
            )

            output = generate_text(
                build_rag_coverage_repair_prompt_from_blocks(
                    [repair_block],
                    query,
                ),
                prompt_version=RAG_PROMPT_VERSION,
                retrieved_evidence_ids=[missing_id],
            )

            calls.append(
                output.metadata
            )

            try:
                repaired_points, repair_parsing = (
                    parse_rag_output(
                        output.text,
                        [evidence],
                    )
                )

            except RagParsingFailure as error:
                raise RagParsingFailure(
                    error.reason,
                    error.raw_text,
                    output.metadata,
                ) from error

            for point in repaired_points:
                has_valid_citation = any(
                    citation.get("is_valid")
                    is not False
                    and citation.get(
                        "evidence_id"
                    )
                    == missing_id

                    for citation
                    in point.get(
                        "citations"
                    )
                    or []
                )

                if not has_valid_citation:
                    point["citations"] = [
                        _single_source_citation(
                            evidence,
                            claim_index=(
                                len(points) + 1
                            ),
                            citation_index=1,
                        )
                    ]

            points.extend(
                repaired_points
            )

            parsing_parts.append(
                repair_parsing
            )

            repaired_ids.append(
                missing_id
            )

        # Repair calls can independently produce identical text.
        points = _merge_duplicate_rag_points(
            points
        )

    # ---------------------------------------------------------
    # Final IDs and coverage measurement.
    # ---------------------------------------------------------

    _renumber_rag_points(
        points
    )

    represented_ids = _represented_evidence_ids(
        points
    )

    represented_id_set = set(
        represented_ids
    )

    remaining_missing_ids = [
        evidence_id
        for evidence_id in evidence_ids
        if evidence_id not in represented_id_set
    ]

    # ---------------------------------------------------------
    # Deterministic display paragraph.
    #
    # Do not add another abstractive generation pass here.
    # That could remove citations or introduce new facts.
    # ---------------------------------------------------------

    paragraph = _normalize_generated_paragraph(
        " ".join(
            str(
                point.get("text") or ""
            ).strip()

            for point in points

            if str(
                point.get("text") or ""
            ).strip()
        )
    )

    parsing = {
        "status": "success",
        "failure_reason": None,

        "claim_count": len(points),
        "display_point_count": 1,

        "unknown_evidence_ids": list(
            dict.fromkeys(
                item
                for part in parsing_parts
                for item in part.get(
                    "unknown_evidence_ids",
                    [],
                )
            )
        ),

        "uncited_claim_count": sum(
            1
            for point in points
            if not point.get("citations")
        ),

        "represented_evidence_ids": (
            represented_ids
        ),

        "missing_evidence_ids": (
            remaining_missing_ids
        ),

        "coverage_repair_evidence_ids": (
            repaired_ids
        ),

        "coverage_contract_required": (
            require_full_coverage
        ),

        # This now means whether the MODEL itself achieved the
        # requested coverage when repair is disabled.
        "coverage_contract_met": (
            not require_full_coverage
            or not remaining_missing_ids
        ),

        "coverage_repair_enabled": (
            repair_missing_coverage
        ),
    }

    metadata = _aggregate_generation_metadata(
        calls,
        prompt_version=RAG_PROMPT_VERSION,
        retrieved_evidence_ids=evidence_ids,
    )

    metadata.update(
        coverage_contract_required=(
            require_full_coverage
        ),

        coverage_repair_enabled=(
            repair_missing_coverage
        ),

        coverage_repair_count=(
            len(repaired_ids)
        ),
    )

    return RagGenerationOutput(
        raw_text=paragraph,
        summary_points=points,
        metadata=metadata,
        parsing=parsing,
    )


def regenerate_unsupported_rag_claims(
    retrieved_evidence: List[Dict[str, Any]],
    query: str,
    unsupported_claims: Sequence[str],
) -> RagGenerationOutput:
    """Perform one constrained regeneration phase, batching only when needed."""

    if not retrieved_evidence:
        metadata = _base_generation_metadata(
            prompt_version=RAG_REGENERATION_PROMPT_VERSION
        )
        metadata.update(
            status="not_applicable",
            failure_reason="no_retrieved_evidence",
            batch_count=0,
        )
        raise GenerationFailure("no_retrieved_evidence", metadata)

    blocks = [build_rag_evidence_block(item) for item in retrieved_evidence]

    def prompt_builder(batch: Sequence[str], batch_query: str) -> str:
        return build_rag_regeneration_prompt_from_blocks(
            batch,
            batch_query,
            unsupported_claims,
        )

    batches = _batch_blocks(blocks, query, prompt_builder)
    calls: List[Dict[str, Any]] = []
    raw_outputs: List[str] = []
    points: List[Dict[str, Any]] = []
    parsing_parts: List[Dict[str, Any]] = []
    for batch in batches:
        batch_evidence = _evidence_for_batch(batch, retrieved_evidence)
        batch_ids = [_evidence_id(item) for item in batch_evidence]
        output = generate_text(
            build_rag_regeneration_prompt_from_blocks(
                batch,
                query,
                unsupported_claims,
            ),
            prompt_version=RAG_REGENERATION_PROMPT_VERSION,
            retrieved_evidence_ids=batch_ids,
        )
        try:
            parsed, parsing = parse_rag_output(
                output.text,
                batch_evidence,
                source_aliases={},
            )
        except RagParsingFailure as error:
            raise RagParsingFailure(error.reason, error.raw_text, output.metadata) from error
        raw_outputs.append(output.text)
        points.extend(parsed)
        parsing_parts.append(parsing)
        calls.append(output.metadata)

    for claim_index, point in enumerate(points, 1):
        point["claim_id"] = f"CLM-{claim_index:03d}"
        for citation_index, citation in enumerate(point["citations"], 1):
            citation["citation_id"] = f"CIT-{claim_index:03d}-{citation_index:02d}"

    evidence_ids = [_evidence_id(item) for item in retrieved_evidence]
    parsing = {
        "status": "success",
        "failure_reason": None,
        "claim_count": len(points),
        "unknown_evidence_ids": list(
            dict.fromkeys(
                item
                for part in parsing_parts
                for item in part["unknown_evidence_ids"]
            )
        ),
        "uncited_claim_count": sum(1 for point in points if not point["citations"]),
    }
    return RagGenerationOutput(
        "\n".join(raw_outputs),
        points,
        _aggregate_generation_metadata(
            calls,
            prompt_version=RAG_REGENERATION_PROMPT_VERSION,
            retrieved_evidence_ids=evidence_ids,
        ),
        parsing,
    )


def generate_production_fallback_plain_summary(
    entries: List[DiaryEntryResponse],
) -> Dict[str, Any]:
    """Explicitly labelled non-research fallback for production continuity."""

    text = (
        f"A weekly summary could not be generated from {len(entries)} recorded entries."
        if entries
        else "No diary entries are available to summarize."
    )
    return {"text": text, "generation_method": "deterministic_production_fallback"}


def generate_production_fallback_rag_summary(
    retrieved_evidence: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """Explicit production fallback; excluded from every research condition."""

    if not retrieved_evidence:
        return []
    return [
        {
            "claim_id": "FALLBACK-001",
            "text": "A model-generated evidence summary is temporarily unavailable.",
            "citations": [],
        }
    ]


def fallback_plain_summary(entries: List[DiaryEntryResponse], query: str) -> str:
    warnings.warn(
        "fallback_plain_summary is production-only and excluded from research.",
        DeprecationWarning,
        stacklevel=2,
    )
    return generate_production_fallback_plain_summary(entries)["text"]


def generate_rule_based_rag_summary(
    retrieved_evidence: List[Dict[str, Any]],
    query: str,
) -> List[Dict[str, Any]]:
    warnings.warn(
        "generate_rule_based_rag_summary is production-only and excluded from research.",
        DeprecationWarning,
        stacklevel=2,
    )
    return generate_production_fallback_rag_summary(retrieved_evidence)
