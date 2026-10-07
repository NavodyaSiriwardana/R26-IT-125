"""Shared local model generation and RAG output parsing.

Plain and RAG conditions intentionally share :func:`generate_text`, one lazy
pipeline instance, and one decoding configuration. Research callers handle
failures explicitly; this module never substitutes a template for model output.
"""

from __future__ import annotations

import logging
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


logger = logging.getLogger(f"uvicorn.error.{__name__}")

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

class _Seq2SeqPipelineCompat:
    """
    Compatibility wrapper for Transformers 5.x.

    Mimics the old text2text-generation pipeline interface so the rest
    of the application does not need to change.
    """

    framework = "pt"

    def __init__(self, model, tokenizer):
        self.model = model
        self.tokenizer = tokenizer
        self.device = model.device

    def __call__(self, inputs, **kwargs):
        import torch

        
        truncation = kwargs.pop("truncation", True)

        encoded = self.tokenizer(
            inputs,
            return_tensors="pt",
            padding=True,
            truncation=truncation,
        )

        encoded = {
            key: value.to(self.model.device)
            for key, value in encoded.items()
        }

        with torch.inference_mode():
            outputs = self.model.generate(
                **encoded,
                **kwargs,
            )

        texts = self.tokenizer.batch_decode(
            outputs,
            skip_special_tokens=True,
        )

    
        return [
            {"generated_text": text}
            for text in texts
        ]


def _get_summarizer_pipeline():
    """Lazily create the single generator shared by every condition."""

    global _summarizer_pipeline

    if _summarizer_pipeline is None:
        load_started = time.perf_counter()

        logger.info(
            "rag_model_load_start role=summary_generator model=%s revision=%s",
            GENERATION_SETTINGS.model_name,
            GENERATION_SETTINGS.model_revision or "default",
        )

        try:
            from transformers import (
                AutoModelForSeq2SeqLM,
                AutoTokenizer,
            )
            import torch

            try:
                torch.set_num_threads(GENERATION_SETTINGS.cpu_threads)
            except (RuntimeError, ValueError):
                logger.warning(
                    "rag_cpu_thread_configuration_skipped role=summary_generator"
                )

            tokenizer_kwargs: Dict[str, Any] = {"local_files_only": True}
            model_kwargs: Dict[str, Any] = {
                "local_files_only": True,
                "low_cpu_mem_usage": True,
            }

            if GENERATION_SETTINGS.torch_dtype == "bfloat16":
                model_kwargs["dtype"] = torch.bfloat16
            elif GENERATION_SETTINGS.torch_dtype not in {"float32", "auto"}:
                raise ValueError(
                    "SLM_TORCH_DTYPE must be bfloat16, float32, or auto."
                )

            if GENERATION_SETTINGS.model_revision:
                tokenizer_kwargs["revision"] = GENERATION_SETTINGS.model_revision
                model_kwargs["revision"] = GENERATION_SETTINGS.model_revision

            tokenizer = AutoTokenizer.from_pretrained(
                GENERATION_SETTINGS.model_name,
                **tokenizer_kwargs,
            )

            model = AutoModelForSeq2SeqLM.from_pretrained(
                GENERATION_SETTINGS.model_name,
                **model_kwargs,
            )
            if getattr(model.generation_config, "forced_bos_token_id", None) is None:
                model.generation_config.forced_bos_token_id = tokenizer.bos_token_id or 0
            model.eval()

            _summarizer_pipeline = _Seq2SeqPipelineCompat(
                model=model,
                tokenizer=tokenizer,
            )

        except Exception as error:
            logger.exception(
                "rag_model_load_failed role=summary_generator model=%s revision=%s "
                "elapsed_ms=%.3f error_type=%s",
                GENERATION_SETTINGS.model_name,
                GENERATION_SETTINGS.model_revision or "default",
                (time.perf_counter() - load_started) * 1000,
                type(error).__name__,
            )
            raise

        logger.info(
            "rag_model_load_success role=summary_generator model=%s revision=%s "
            "elapsed_ms=%.3f framework=%s device=%s",
            GENERATION_SETTINGS.model_name,
            _resolved_model_revision(_summarizer_pipeline) or "unknown",
            (time.perf_counter() - load_started) * 1000,
            getattr(_summarizer_pipeline, "framework", "unknown"),
            getattr(_summarizer_pipeline, "device", "unknown"),
        )

    return _summarizer_pipeline


def preload_summary_model() -> None:
    """Load the local summarizer before the first interactive request."""

    _get_summarizer_pipeline()

def get_shared_decoding_parameters() -> Dict[str, Any]:
    """
    Shared deterministic decoding configuration.

    IMPORTANT:
    Plain and RAG use exactly the same decoding parameters
    so generation settings do not become an experimental confound.
    """

    return {
        "max_length": GENERATION_SETTINGS.max_new_tokens,
        "do_sample": False,
        "num_beams": GENERATION_SETTINGS.num_beams,

        "no_repeat_ngram_size": 3,
        "repetition_penalty": 1.05,

        "length_penalty": 1.0,

        "min_length": 0,
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
        "torch_dtype": GENERATION_SETTINGS.torch_dtype,
        "cpu_threads": GENERATION_SETTINGS.cpu_threads,
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
    """Generate with the one controlled local model and decoding contract."""

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
            logger.info(
                "summary_generation_start prompt_chars=%d max_new_tokens=%d",
                len(prompt),
                GENERATION_SETTINGS.max_new_tokens,
            )
            result = generator(prompt, **get_shared_decoding_parameters())

            logger.info(
                "summary_generation_finished elapsed_ms=%.3f",
                (time.perf_counter() - generation_started) * 1000,
            )
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
        logger.error(
            "rag_model_execution_failed role=summary_generator model=%s phase=%s "
            "error_type=%s",
            GENERATION_SETTINGS.model_name,
            "inference" if generation_started is not None else "setup",
            type(error).__name__,
        )
        raise GenerationFailure(metadata["failure_reason"], metadata) from error


def generate_text_batch(
    prompts: Sequence[str],
    *,
    prompt_version: str,
    retrieved_evidence_ids: Sequence[str],
) -> List[GenerationOutput]:
    """Generate independent summaries in one model call."""

    if not prompts:
        return []
    setup_started = time.perf_counter()
    generation_started: Optional[float] = None
    metadata = _base_generation_metadata(
        prompt_version=prompt_version,
        retrieved_evidence_ids=retrieved_evidence_ids,
    )
    try:
        model_cache_hit = _summarizer_pipeline is not None
        generator = _get_summarizer_pipeline()
        setup_latency_ms = round((time.perf_counter() - setup_started) * 1000, 3)
        with _generation_lock:
            from transformers import set_seed

            set_seed(GENERATION_SETTINGS.random_seed)
            generation_started = time.perf_counter()
            results = generator(list(prompts), **get_shared_decoding_parameters())
        if not isinstance(results, list) or len(results) != len(prompts):
            raise ValueError("generator returned the wrong number of batch results")
        latency_ms = round((time.perf_counter() - generation_started) * 1000, 3)
        outputs: List[GenerationOutput] = []
        for evidence_id, result in zip(retrieved_evidence_ids, results):
            text = str(result.get("generated_text", "")).strip()
            if not text:
                raise ValueError("generator returned blank text")
            item_metadata = dict(metadata)
            item_metadata.update(
                status="success",
                model_revision=_resolved_model_revision(generator),
                model_setup_latency_ms=setup_latency_ms,
                model_cache_hit=model_cache_hit,
                latency_ms=round(latency_ms / len(prompts), 3),
                retrieved_evidence_ids=[evidence_id],
            )
            outputs.append(GenerationOutput(text, item_metadata))
        return outputs
    except Exception as error:
        metadata.update(
            status="generation_failed",
            failure_reason=f"model_generation_failed:{type(error).__name__}",
            model_setup_latency_ms=round(
                (time.perf_counter() - setup_started) * 1000,
                3,
            ),
            latency_ms=(
                round((time.perf_counter() - generation_started) * 1000, 3)
                if generation_started is not None
                else None
            ),
        )
        raise GenerationFailure(metadata["failure_reason"], metadata) from error


def _compact_field(value: Any, *, limit: Optional[int] = 180) -> str:
    text = " ".join(str(value or "").split()).strip()
    if not text:
        return "Not recorded"
    return text if limit is None or len(text) <= limit else f"{text[: limit - 1].rstrip()}…"


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
    sentence = f"{_compact_field(entry.activity_name)} was"
    if entry.activity_category:
        sentence += f" a {_compact_field(entry.activity_category)} activity"
    if entry.productivity_level:
        sentence += f" with {_compact_field(entry.productivity_level)} productivity"
    if entry.task_outcome:
        sentence += f", resulting in {_compact_field(entry.task_outcome)}"
    if entry.mood_before or entry.mood_after:
        sentence += (
            f", while your mood changed from {_compact_field(entry.mood_before or 'not recorded')}"
            f" to {_compact_field(entry.mood_after or 'not recorded')}"
        )
    sentence += "."
    if entry.notes:
        sentence += f" You noted {_compact_field(entry.notes, limit=None)}."
    return sentence


def build_plain_slm_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
) -> str:
    """Build the plain condition's compact source document."""

    return (
        "\n".join(blocks)
        + f"\nRequested focus: {query.strip()}."
    )

def build_plain_consolidation_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
) -> str:
    return "\n".join(blocks) + f"\nRequested focus: {query.strip()}."


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

    evidence_id = _evidence_id(evidence)
    activity = _compact_field(metadata.get("activityName"))
    sentence = f"{source_label}: You did {activity}"
    if metadata.get("activityCategory"):
        sentence += f", a {_compact_field(metadata['activityCategory'])} activity"
    if metadata.get("productivityLevel"):
        sentence += f" with {_compact_field(metadata['productivityLevel'])} productivity"
    if metadata.get("taskOutcome"):
        sentence += f", resulting in {_compact_field(metadata['taskOutcome'])}"
    if metadata.get("moodBefore") or metadata.get("moodAfter"):
        sentence += (
            f", while your mood changed from {_compact_field(metadata.get('moodBefore'))}"
            f" to {_compact_field(metadata.get('moodAfter'))}"
        )
    if metadata.get("notes"):
        sentence += f"; notes: {_compact_field(metadata['notes'], limit=None)}"
    return f"{sentence}. [EVIDENCE_ID: {evidence_id}]"


def build_rag_slm_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
    *,
    require_full_coverage: bool = False,
) -> str:
    """
    Build the grounded RAG generation prompt.
    """

    coverage = "all supplied sources" if require_full_coverage else "relevant sources"
    return (
        "\n".join(blocks)
        + f"\nRequested focus: {query.strip()}. Summarize {coverage} in second person."
    )


def build_rag_consolidation_prompt_from_blocks(
    blocks: Sequence[str],
    query: str,
) -> str:
    return (
        "\n".join(blocks)
        + f"\nRequested focus: {query.strip()}."
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
    _unsupported_claims: Sequence[str],
) -> str:
    return (
        "\n\n".join(blocks)
        + f"\nRequested focus: {query.strip()}. Rewrite the evidence as one concise "
        "diary sentence using only the recorded facts."
    )


def _prompt_token_count(prompt: str) -> int:

    words = len(re.findall(r"\S+", prompt))
    return max(1, int(max(words * 1.4, len(prompt) / 4)) + 1)


def _split_oversized_block(
    block: str,
    query: str,
    prompt_builder: Callable[[Sequence[str], str], str],
) -> List[str]:
    source_match = re.match(r"\s*(Source\s+\[\d+\])", block, re.IGNORECASE)
    evidence_match = re.search(r"\[EVIDENCE_ID:\s*[^\]]+\]", block, re.IGNORECASE)
    repeated_header = " ".join(
        part for part in (
            source_match.group(1) if source_match else "",
            evidence_match.group(0) if evidence_match else "",
    ) if part
    )
    content = _EXPLICIT_EVIDENCE_RE.sub("", block).strip() if evidence_match else block
    if source_match:
        content = re.sub(r"^\s*Source\s+\[\d+\]\s*:\s*", "", content, flags=re.IGNORECASE)
    words = content.split()
    if not words:
        return []
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
    paragraph = re.sub(
        r"\bthe diary (?:owner|author)(?:'s|’s)\b",
        "your",
        paragraph,
        flags=re.IGNORECASE,
    )
    paragraph = re.sub(
        r"\bthe diary (?:owner|author)\b",
        "you",
        paragraph,
        flags=re.IGNORECASE,
    )
    paragraph = re.sub(r"\bthe user(?:'s|’s)\b", "your", paragraph, flags=re.IGNORECASE)
    paragraph = re.sub(r"\bthe user\b", "you", paragraph, flags=re.IGNORECASE)
    paragraph = re.sub(
        r"(^|(?<=[.!?])\s+)(you|your)\b",
        lambda match: f"{match.group(1)}{match.group(2).capitalize()}",
        paragraph,
        flags=re.IGNORECASE,
    )
    if strip_citations:
        paragraph = _remove_citation_tokens(paragraph)
    return " ".join(paragraph.split()).strip()


_QUALITY_STOPWORDS = {
    "a", "about", "activity", "and", "author", "diary", "entry", "for",
    "from", "in", "is", "it", "of", "on", "owner", "summary", "the",
    "this", "to", "was", "week", "weekly", "with", "you", "your",
}
_LOW_INFORMATION_PHRASES = (
    "diary entry summarizes",
    "diary owner summarized",
    "diary author summarized",
    "author summarizes",
    "summary was generated",
)


def _meaningful_tokens(values: Sequence[Any]) -> set[str]:
    return {
        token[:4]
        for value in values
        for token in re.findall(r"[a-z0-9]+", str(value or "").casefold())
        if len(token) > 2 and token not in _QUALITY_STOPWORDS
    }


def _validate_generated_summary(text: str, source_values: Sequence[Any]) -> bool:
    """Reject blank/meta output without replacing model text with a template."""

    normalized = " ".join(text.split()).strip()
    lowered = normalized.casefold()
    if len(re.findall(r"\b\w+\b", normalized)) < 4:
        return False
    if any(phrase in lowered for phrase in _LOW_INFORMATION_PHRASES):
        return False
    source_tokens = _meaningful_tokens(source_values)
    summary_tokens = _meaningful_tokens([normalized])
    return not source_tokens or bool(source_tokens.intersection(summary_tokens))


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
    source_values = [
        value
        for entry in entries
        for value in (
            entry.activity_name,
            entry.activity_category,
            entry.productivity_level,
            entry.mood_before,
            entry.mood_after,
            entry.task_outcome,
            entry.notes,
        )
    ]
    if not _validate_generated_summary(paragraph, source_values):
        metadata = _aggregate_generation_metadata(
            calls,
            prompt_version=PLAIN_PROMPT_VERSION,
        )
        metadata.update(status="generation_failed", failure_reason="low_information_summary")
        raise GenerationFailure("low_information_summary", metadata)
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
                        "attribution_method": "model_marker",
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


def _evidence_match_score(claim: str, evidence: Dict[str, Any]) -> int:
    """Score one generated claim against one retrieved canonical record."""

    metadata = _metadata_from_evidence(evidence)
    lowered_claim = claim.casefold()
    activity_name = str(metadata.get("activityName") or "").strip().casefold()
    score = 10 if activity_name and activity_name in lowered_claim else 0
    evidence_tokens = _meaningful_tokens(
        [
            metadata.get("activityName"),
            metadata.get("activityCategory"),
            metadata.get("productivityLevel"),
            metadata.get("moodBefore"),
            metadata.get("moodAfter"),
            metadata.get("taskOutcome"),
            metadata.get("notes"),
        ]
    )
    return score + len(_meaningful_tokens([claim]).intersection(evidence_tokens))


def _attribute_uncited_points(
    points: List[Dict[str, Any]],
    evidence: Sequence[Dict[str, Any]],
) -> int:
    """Attach retrieved sources to model claims when the model drops markers.

    This does not create or rewrite summary text. NLI still decides whether each
    attached source actually supports its generated claim.
    """

    attributed = 0
    evidence_number = {
        _evidence_id(item): index for index, item in enumerate(evidence, 1)
    }
    for point in points:
        if point.get("citations"):
            continue
        scored = [
            (_evidence_match_score(str(point.get("text") or ""), item), item)
            for item in evidence
        ]
        best_score = max((score for score, _ in scored), default=0)
        if best_score <= 0:
            continue
        named_matches = [
            item
            for _, item in scored
            if str(_metadata_from_evidence(item).get("activityName") or "").strip().casefold()
            in str(point.get("text") or "").casefold()
        ]
        matches = named_matches or [item for score, item in scored if score == best_score]
        point["citations"] = [
            {
                "citation_id": "",
                "evidence_id": _evidence_id(item),
                "label": f"[{evidence_number[_evidence_id(item)]}]",
                "source_preview": _source_preview(item),
                "source_type": "diary_entry",
                "is_valid": True,
                "validation_error": None,
                "attribution_method": "automatic_lexical_attribution",
            }
            for item in matches
            if _evidence_id(item)
        ]
        if point["citations"]:
            attributed += 1
    return attributed


def _renumber_rag_points(points: List[Dict[str, Any]]) -> None:
    for claim_index, point in enumerate(points, 1):
        point["claim_id"] = f"CLM-{claim_index:03d}"
        for citation_index, citation in enumerate(point.get("citations") or [], 1):
            citation["citation_id"] = f"CIT-{claim_index:03d}-{citation_index:02d}"


def _generate_full_coverage_rag_summary(
    retrieved_evidence: List[Dict[str, Any]],
    query: str,
) -> RagGenerationOutput:
    """Generate one traceable claim group per entry in a single model batch."""

    evidence = _prepare_weekly_evidence(retrieved_evidence)
    evidence_ids = [_evidence_id(item) for item in evidence if _evidence_id(item)]
    prompts = [
        build_rag_slm_prompt_from_blocks(
            [build_rag_evidence_block(item, source_number=index)],
            query,
        )
        for index, item in enumerate(evidence, 1)
    ]
    outputs = generate_text_batch(
        prompts,
        prompt_version=RAG_PROMPT_VERSION,
        retrieved_evidence_ids=evidence_ids,
    )

    points: List[Dict[str, Any]] = []
    calls: List[Dict[str, Any]] = []
    for item, output in zip(evidence, outputs):
        item_points, _ = parse_rag_output(
            output.text,
            [item],
            retain_citations=False,
        )
        evidence_id = _evidence_id(item)
        for point in item_points:
            point["citations"] = [
                {
                    "citation_id": "",
                    "evidence_id": evidence_id,
                    "label": "",
                    "source_preview": _source_preview(item),
                    "source_type": "diary_entry",
                    "is_valid": True,
                    "validation_error": None,
                    "attribution_method": "single_source_generation",
                }
            ]
        points.extend(item_points)
        calls.append(output.metadata)

    _renumber_rag_points(points)
    paragraph = _normalize_generated_paragraph(_summary_text_from_points(points))
    metadata = _aggregate_generation_metadata(
        calls,
        prompt_version=RAG_PROMPT_VERSION,
        retrieved_evidence_ids=evidence_ids,
    )
    metadata.update(
        coverage_contract_required=True,
        coverage_contract_met=True,
        coverage_repair_enabled=False,
        coverage_repair_count=0,
        generation_strategy="batched_single_source",
    )
    parsing = {
        "status": "success",
        "failure_reason": None,
        "claim_count": len(points),
        "display_point_count": len(points),
        "unknown_evidence_ids": [],
        "model_cited_claim_count": 0,
        "automatically_attributed_claim_count": 0,
        "single_source_bound_claim_count": len(points),
        "uncited_claim_count": 0,
        "represented_evidence_ids": evidence_ids,
        "missing_evidence_ids": [],
        "coverage_repair_evidence_ids": [],
        "coverage_repair_skipped_reason": None,
        "coverage_repair_round_count": 0,
        "coverage_contract_required": True,
        "coverage_contract_met": True,
        "coverage_repair_enabled": False,
    }
    return RagGenerationOutput(paragraph, points, metadata, parsing)


def _summary_text_from_points(points: Sequence[Dict[str, Any]]) -> str:
    return " ".join(
        str(point.get("text") or "").strip()
        for point in points
        if str(point.get("text") or "").strip()
    )


def generate_rag_slm_summary(
    retrieved_evidence: List[Dict[str, Any]],
    query: str,
    *,
    require_full_coverage: bool = False,
    repair_missing_coverage: bool = False,
) -> RagGenerationOutput:
    """
    Generate a grounded RAG weekly summary.

    Long inputs are summarized in batches and then consolidated into one cited
    narrative. When coverage repair is enabled, all omitted sources share one
    repair call and the result is reconsolidated once.
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

    if require_full_coverage:
        return _generate_full_coverage_rag_summary(retrieved_evidence, query)

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
    drafts: List[str] = []

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
            batch_points, _ = parse_rag_output(
                output.text,
                batch_evidence,
                source_aliases=source_aliases,
            )
        except RagParsingFailure as error:
            raise RagParsingFailure(
                error.reason,
                error.raw_text,
                output.metadata,
            ) from error

        invalid_labels = {
            str(citation.get("label") or "")
            for point in batch_points
            for citation in point.get("citations") or []
            if citation.get("is_valid") is False
        }
        draft = output.text
        for label in invalid_labels:
            if label:
                draft = draft.replace(label, "")
        drafts.append(draft)

    paragraph_with_citations = _consolidate_drafts(
        drafts,
        query=query,
        prompt_builder=build_rag_consolidation_prompt_from_blocks,
        prompt_version=RAG_PROMPT_VERSION,
        calls=calls,
        retrieved_evidence_ids=evidence_ids,
        preserve_citations=True,
    )

    source_values = [
        value
        for item in retrieved_evidence
        for value in _metadata_from_evidence(item).values()
    ]
    if not _validate_generated_summary(
        _normalize_generated_paragraph(paragraph_with_citations),
        source_values,
    ):
        metadata = _aggregate_generation_metadata(
            calls,
            prompt_version=RAG_PROMPT_VERSION,
            retrieved_evidence_ids=evidence_ids,
        )
        metadata.update(status="generation_failed", failure_reason="low_information_summary")
        raise GenerationFailure("low_information_summary", metadata)

    try:
        points, parsing = parse_rag_output(
            paragraph_with_citations,
            retrieved_evidence,
            source_aliases=source_aliases,
        )
    except RagParsingFailure as error:
        raise RagParsingFailure(
            error.reason,
            error.raw_text,
            calls[-1] if calls else None,
        ) from error

    # ---------------------------------------------------------
    # Deterministic duplicate removal.
    # ---------------------------------------------------------

    points = _merge_duplicate_rag_points(
        points
    )
    model_cited_claim_count = sum(bool(point.get("citations")) for point in points)
    attributed_claim_count = _attribute_uncited_points(points, retrieved_evidence)

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
    repair_skipped_reason: Optional[str] = None
    repair_round_count = 0
    repair_unknown_ids: List[str] = list(parsing.get("unknown_evidence_ids", []))

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
        "display_point_count": len(points),

        "unknown_evidence_ids": list(dict.fromkeys(repair_unknown_ids)),

        "model_cited_claim_count": model_cited_claim_count,

        "automatically_attributed_claim_count": attributed_claim_count,

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

        "coverage_repair_skipped_reason": repair_skipped_reason,

        "coverage_repair_round_count": repair_round_count,

        "coverage_contract_required": (
            require_full_coverage
        ),

     
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

        coverage_repair_skipped_reason=repair_skipped_reason,
        coverage_repair_round_count=repair_round_count,
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

    _attribute_uncited_points(points, retrieved_evidence)
    _renumber_rag_points(points)

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
