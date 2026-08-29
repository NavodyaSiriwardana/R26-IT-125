"""Reference-summary similarity metrics for offline research evaluation."""

from __future__ import annotations

import math
import os
import re
from collections.abc import Callable
from typing import Any, Dict, Optional


DEFAULT_BERTSCORE_MODEL = "distilbert-base-uncased"
BERTSCORE_MODEL_ENV = "BERTSCORE_MODEL_NAME"
BERTSCORE_MODEL = DEFAULT_BERTSCORE_MODEL  # Deprecated public constant alias.

# Patchable while ensuring importing this module never imports/model-loads
# BERTScore eagerly.
bert_score: Optional[Callable[..., Any]] = None


def _get_bert_score_function() -> Callable[..., Any]:
    global bert_score
    if bert_score is None:
        from bert_score import score as bert_score_function

        bert_score = bert_score_function
    return bert_score


def _metric_result(
    *,
    status: str,
    value: Optional[float],
    reason: Optional[str],
    model: str,
    metric: str,
    **extra: Any,
) -> Dict[str, Any]:
    return {
        "status": status,
        "value": value,
        "reason": reason,
        "model": model,
        "metric": metric,
        **extra,
    }


def evaluate_bertscore(
    candidate_text: str,
    human_reference_summary: str,
    *,
    model_name: Optional[str] = None,
    scorer: Optional[Callable[..., Any]] = None,
) -> Dict[str, Any]:
    """Calculate BERTScore F1 against a supplied human-written reference.

    Returns ``{"status", "value", "reason", "model", "metric"}``. ``value``
    is a rounded float only when ``status == "available"``. Blank inputs,
    import/model failures and malformed outputs return ``value=None``; they are
    never represented as a fabricated zero. The dataset/experiment caller is
    responsible for ensuring the reference is human-authored, not raw context.
    """

    resolved_model = (
        model_name or os.getenv(BERTSCORE_MODEL_ENV) or DEFAULT_BERTSCORE_MODEL
    ).strip()
    if not candidate_text or not candidate_text.strip():
        return _metric_result(
            status="unavailable",
            value=None,
            reason="The candidate summary is blank.",
            model=resolved_model,
            metric="bertscore_f1",
        )
    if not human_reference_summary or not human_reference_summary.strip():
        return _metric_result(
            status="unavailable",
            value=None,
            reason="A non-blank human reference summary is required.",
            model=resolved_model,
            metric="bertscore_f1",
        )
    try:
        score_function = scorer or _get_bert_score_function()
        _, _, f1_scores = score_function(
            cands=[candidate_text],
            refs=[human_reference_summary],
            model_type=resolved_model,
            lang="en",
            verbose=False,
            rescale_with_baseline=False,
        )
        mean_score = f1_scores.mean()
        if hasattr(mean_score, "item"):
            mean_score = mean_score.item()
        value = float(mean_score)
        if not math.isfinite(value):
            raise ValueError("BERTScore returned a non-finite value.")
        return _metric_result(
            status="available",
            value=round(value, 4),
            reason=None,
            model=resolved_model,
            metric="bertscore_f1",
        )
    except Exception as error:
        return _metric_result(
            status="unavailable",
            value=None,
            reason=f"BERTScore evaluation failed ({type(error).__name__}).",
            model=resolved_model,
            metric="bertscore_f1",
        )


def calculate_bertscore_similarity(
    candidate_text: str,
    reference_text: str,
    **kwargs: Any,
) -> Dict[str, Any]:
    """Deprecated compatibility name returning a structured metric result.

    ``reference_text`` must be a human-written reference summary. Comparing a
    candidate with raw diary context is not a factual-accuracy evaluation.
    """

    return evaluate_bertscore(candidate_text, reference_text, **kwargs)


def _rouge_tokens(text: str) -> list[str]:
    return re.findall(r"\w+", text.lower(), flags=re.UNICODE)


def _lcs_length(left: list[str], right: list[str]) -> int:
    if len(right) > len(left):
        left, right = right, left
    previous = [0] * (len(right) + 1)
    for left_token in left:
        current = [0]
        for index, right_token in enumerate(right, start=1):
            if left_token == right_token:
                current.append(previous[index - 1] + 1)
            else:
                current.append(max(previous[index], current[-1]))
        previous = current
    return previous[-1]


def calculate_rouge_l_similarity(
    candidate_text: str,
    human_reference_summary: str,
) -> Dict[str, Any]:
    """Calculate token-level ROUGE-L F1 against a human-written reference.

    The result uses the same ``status/value/reason/model`` contract as
    BERTScore. A genuine no-overlap comparison is an available ``0.0``; blank
    and error cases remain unavailable/``None``.
    """

    implementation = "rouge-l-lcs-f1-unicode-word-v1"
    if not candidate_text or not candidate_text.strip():
        return _metric_result(
            status="unavailable",
            value=None,
            reason="The candidate summary is blank.",
            model=implementation,
            metric="rouge_l_f1",
            precision=None,
            recall=None,
        )
    if not human_reference_summary or not human_reference_summary.strip():
        return _metric_result(
            status="unavailable",
            value=None,
            reason="A non-blank human reference summary is required.",
            model=implementation,
            metric="rouge_l_f1",
            precision=None,
            recall=None,
        )
    try:
        candidate_tokens = _rouge_tokens(candidate_text)
        reference_tokens = _rouge_tokens(human_reference_summary)
        if not candidate_tokens or not reference_tokens:
            raise ValueError("The supplied text contains no comparable word tokens.")
        lcs = _lcs_length(candidate_tokens, reference_tokens)
        precision = lcs / len(candidate_tokens)
        recall = lcs / len(reference_tokens)
        value = (
            0.0
            if precision + recall == 0
            else 2 * precision * recall / (precision + recall)
        )
        return _metric_result(
            status="available",
            value=round(value, 4),
            reason=None,
            model=implementation,
            metric="rouge_l_f1",
            precision=round(precision, 4),
            recall=round(recall, 4),
        )
    except Exception as error:
        return _metric_result(
            status="unavailable",
            value=None,
            reason=f"ROUGE-L evaluation failed ({type(error).__name__}).",
            model=implementation,
            metric="rouge_l_f1",
            precision=None,
            recall=None,
        )


def evaluate_reference_similarity(
    candidate_text: str,
    human_reference_summary: str,
    *,
    bertscore_model_name: Optional[str] = None,
    bertscore_scorer: Optional[Callable[..., Any]] = None,
) -> Dict[str, Dict[str, Any]]:
    """Return separate BERTScore and ROUGE-L human-reference metrics."""

    return {
        "bertscore": evaluate_bertscore(
            candidate_text,
            human_reference_summary,
            model_name=bertscore_model_name,
            scorer=bertscore_scorer,
        ),
        "rouge_l": calculate_rouge_l_similarity(
            candidate_text,
            human_reference_summary,
        ),
    }


def calculate_evidence_accuracy(*args: Any, **kwargs: Any) -> Dict[str, Any]:
    """Retired compatibility stub for the invalid invented aggregate metric."""

    raise NotImplementedError(
        "Evidence Accuracy was retired. Report groundedness, citation, "
        "BERTScore and ROUGE-L metrics separately."
    )
