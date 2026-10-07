import re
import time
from pathlib import Path
from threading import Lock
from typing import Any, Dict, List, Sequence

from app.config import FEEDBACK_PROMPT_VERSION


_FEEDBACK_MODEL_NAME = "microsoft/Phi-4-mini-instruct-onnx"
_FEEDBACK_MODEL_SUBDIR = "cpu_and_mobile/cpu-int4-rtn-block-32-acc-level-4"
_FEEDBACK_MAX_NEW_TOKENS = 128
_feedback_model = None
_feedback_tokenizer = None
_feedback_model_lock = Lock()


_DIAGNOSIS_RE = re.compile(
    r"\b(?:diagnos(?:e|ed|is)|depression|anxiety disorder|bipolar|adhd|ptsd|"
    r"mental illness|personality disorder|clinical disorder|suicid(?:e|al))\b",
    re.IGNORECASE,
)

_CITATION_RE = re.compile(r"\[\s*\d+\s*\]?")


def _summary_text(summary_points: Sequence[Dict[str, Any]]) -> str:
    return "\n".join(
        f"- {text}"
        for point in summary_points
        if (text := str(point.get("text") or "").strip())
    )


def _summary_evidence_ids(summary_points: Sequence[Dict[str, Any]]) -> List[str]:
    return list(
        dict.fromkeys(
            evidence_id
            for point in summary_points
            for citation in point.get("citations") or []
            if (evidence_id := str(citation.get("evidence_id") or "").strip())
        )
    )


def _clean_rag_summary(rag_summary: str) -> str:
    """Remove citation noise and exact repeated sentences before generation."""

    without_citations = _CITATION_RE.sub("", rag_summary)
    normalized = re.sub(r"[ \t]+", " ", without_citations)
    sentences = re.split(r"(?<=[.!?])\s+|\n+", normalized)

    unique_sentences = []
    seen = set()
    for sentence in sentences:
        cleaned = re.sub(r"^\s*-\s*", "", sentence).strip()
        if not cleaned:
            continue

        comparison_key = re.sub(r"\W+", " ", cleaned).lower().strip()
        if comparison_key in seen:
            continue

        seen.add(comparison_key)
        unique_sentences.append(f"- {cleaned}")

    return "\n".join(unique_sentences)


def _feedback_prompt(rag_summary: str) -> str:
    clean_summary = _clean_rag_summary(rag_summary)

    return (
        "Based on following records, what should I do next week?.\n\n"
        f"Activity records:\n{clean_summary}\n\n"
        "Analysis and recommendations:"
    )


def _feedback_model_path() -> Path:
    from huggingface_hub import snapshot_download

    snapshot = snapshot_download(
        _FEEDBACK_MODEL_NAME,
        allow_patterns=[f"{_FEEDBACK_MODEL_SUBDIR}/*"],
        local_files_only=True,
    )
    return Path(snapshot) / _FEEDBACK_MODEL_SUBDIR


def _generate_feedback_text(prompt: str) -> tuple[str, Dict[str, Any]]:
    global _feedback_model, _feedback_tokenizer

    import onnxruntime_genai as og

    started = time.perf_counter()
    with _feedback_model_lock:
        model_cache_hit = _feedback_model is not None
        if not model_cache_hit:
            _feedback_model = og.Model(str(_feedback_model_path()))
            _feedback_tokenizer = og.Tokenizer(_feedback_model)

        chat_prompt = (
            "<|system|>You provide concise, grounded, non-medical wellbeing and "
            "productivity feedback.<|end|><|user|>"
            f"{prompt}<|end|><|assistant|>"
        )
        input_tokens = _feedback_tokenizer.encode(chat_prompt)
        params = og.GeneratorParams(_feedback_model)
        params.set_search_options(
            max_length=len(input_tokens) + _FEEDBACK_MAX_NEW_TOKENS,
            do_sample=False,
            num_beams=1,
        )
        generator = og.Generator(_feedback_model, params)
        generator.append_tokens(input_tokens)
        stream = _feedback_tokenizer.create_stream()
        output = []
        while not generator.is_done():
            generator.generate_next_token()
            output.append(stream.decode(generator.get_next_tokens()[0]))
        del generator
        text = "".join(output).strip()

    return text, {
        "status": "success",
        "model_name": _FEEDBACK_MODEL_NAME,
        "model_format": "onnx-int4-rtn",
        "execution_provider": "cpu",
        "prompt_version": FEEDBACK_PROMPT_VERSION,
        "decoding_parameters": {
            "max_new_tokens": _FEEDBACK_MAX_NEW_TOKENS,
            "do_sample": False,
            "num_beams": 1,
        },
        "model_cache_hit": model_cache_hit,
        "latency_ms": round((time.perf_counter() - started) * 1000, 3),
    }


def _unavailable_feedback(
    reason: str,
    evidence_ids: Sequence[str] = (),
) -> Dict[str, Any]:
    ids = list(evidence_ids)
    return {
        "feedback_type": "wellbeing_productivity",
        "mood_signal": "",
        "productivity_signal": "",
        "message": "Feedback could not be generated from this week's summary.",
        "action": "",
        "evidence_ids": ids,
        "based_on_evidence_ids": ids,
        "abstained": True,
        "generation_method": "generative_unavailable",
        "fallback_reason": reason,
    }


def generate_feedback_from_rag_summary(
    summary_points: Sequence[Dict[str, Any]],
) -> Dict[str, Any]:
    """Generate Phi-4 Mini INT4 feedback from the displayed RAG summary."""

    rag_summary = _summary_text(summary_points)
    evidence_ids = _summary_evidence_ids(summary_points)
    if not rag_summary:
        return _unavailable_feedback("no_supported_rag_summary", evidence_ids)

    try:
        message, generation = _generate_feedback_text(
            _feedback_prompt(rag_summary)
        )
        if not message:
            raise ValueError("feedback_text_is_blank")
        if _DIAGNOSIS_RE.search(message):
            raise ValueError("feedback_contains_medical_or_mental_health_diagnosis")

        print(f"[Feedback] Generated feedback from RAG summary: {message}")
        return {
            "feedback_type": "wellbeing_productivity",
            "mood_signal": "",
            "productivity_signal": "",
            "message": message,
            "action": "",
            "evidence_ids": evidence_ids,
            "based_on_evidence_ids": evidence_ids,
            "abstained": False,
            "generation_method": "phi4_mini_int4_from_rag_summary",
            "fallback_reason": None,
            "generation": generation,
        }
    except Exception as error:
        return _unavailable_feedback(
            f"feedback_generation_failed:{type(error).__name__}",
            evidence_ids,
        )
