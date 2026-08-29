import json
import re
from typing import List, Dict, Any, Optional, Callable

from app.config import FEEDBACK_PROMPT_VERSION

from .schemas import DiaryEntryResponse


POSITIVE_MOODS = {
    "happy",
    "motivated",
    "calm",
    "relaxed",
    "focused",
    "confident",
    "good",
    "excited",
}

NEGATIVE_MOODS = {
    "sad",
    "stressed",
    "tired",
    "bored",
    "angry",
    "anxious",
    "worried",
    "frustrated",
    "low",
}


def _normalize(value: str) -> str:
    return value.strip().lower() if value else ""


def _mood_score(mood: str) -> int:
    normalized = _normalize(mood)

    if normalized in POSITIVE_MOODS:
        return 1

    if normalized in NEGATIVE_MOODS:
        return -1

    return 0


def _detect_mood_signal(entries: List[DiaryEntryResponse]) -> str:
    if not entries:
        return "unknown"

    before_total = sum(_mood_score(entry.mood_before) for entry in entries)
    after_total = sum(_mood_score(entry.mood_after) for entry in entries)

    if before_total < after_total:
        return "negative_to_positive"

    if before_total > after_total:
        return "positive_to_negative"

    if after_total < 0:
        return "mostly_negative"

    if after_total > 0:
        return "mostly_positive"

    return "neutral"


def _detect_productivity_signal(entries: List[DiaryEntryResponse]) -> str:
    if not entries:
        return "unknown"

    productivity_values = [_normalize(entry.productivity_level) for entry in entries]

    high_count = productivity_values.count("high")
    medium_count = productivity_values.count("medium")
    low_count = productivity_values.count("low")

    if high_count >= medium_count and high_count >= low_count:
        return "high"

    if low_count > high_count and low_count >= medium_count:
        return "low"

    return "medium"


def _detect_task_signal(entries: List[DiaryEntryResponse]) -> str:
    if not entries:
        return "unknown"

    outcomes = [_normalize(entry.task_outcome) for entry in entries]

    completed_count = sum(
        1 for outcome in outcomes
        if outcome in {"completed", "done", "finished", "success"}
    )

    incomplete_count = len(outcomes) - completed_count

    if completed_count > incomplete_count:
        return "mostly_completed"

    if incomplete_count > completed_count:
        return "mostly_incomplete"

    return "mixed"


def _get_retrieved_evidence_ids(retrieved_evidence: List[Dict[str, Any]]) -> List[str]:
    evidence_ids = []

    for evidence in retrieved_evidence:
        evidence_id = evidence.get("evidence_id")

        if not evidence_id:
            metadata = evidence.get("metadata", {})
            evidence_id = metadata.get("evidenceId") or metadata.get("evidence_id")

        if evidence_id and evidence_id not in evidence_ids:
            evidence_ids.append(evidence_id)

    return evidence_ids


def _generate_rule_based_feedback(
    retrieved_entries: List[DiaryEntryResponse],
    retrieved_evidence: List[Dict[str, Any]],
    *,
    fallback_reason: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Generates safe, demo-friendly feedback using structured diary fields.

    This intentionally does not use the plain SLM summary.
    Feedback is calculated from the current week's recorded diary entries.
    """

    evidence_ids = _get_retrieved_evidence_ids(retrieved_evidence)

    if not retrieved_entries:
        return {
            "feedback_type": "wellbeing_productivity",
            "mood_signal": "unknown",
            "productivity_signal": "unknown",
            "message": (
                "There are no diary entries available for feedback this week."
            ),
            "action": "Record an activity before requesting weekly feedback.",
            "evidence_ids": evidence_ids,
            "based_on_evidence_ids": evidence_ids,
            "abstained": True,
            "generation_method": (
                "rule_based_fallback" if fallback_reason else "rule_based"
            ),
            "fallback_reason": fallback_reason,
        }

    mood_signal = _detect_mood_signal(retrieved_entries)
    productivity_signal = _detect_productivity_signal(retrieved_entries)
    task_signal = _detect_task_signal(retrieved_entries)

    if mood_signal == "negative_to_positive" and productivity_signal == "high":
        message = (
            "Your diary entries show improved mood alongside high productivity."
        )
        action = "Keep the working pattern that helped, with a short break after focused work."

    elif mood_signal == "negative_to_positive":
        message = (
            "Your diary entries show mood improvement across the recorded activities."
        )
        action = "Repeat a helpful routine and keep the next task small and manageable."

    elif mood_signal in {"positive_to_negative", "mostly_negative"}:
        message = (
            "Your diary entries show a lower mood pattern after the recorded activities."
        )
        action = "Reduce the next task, pause briefly, and choose one manageable step."

    elif productivity_signal == "low":
        message = (
            "Your diary entries show low self-rated productivity."
        )
        action = "Reduce the next task to one small step and reassess after completing it."

    elif task_signal == "mostly_incomplete":
        message = (
            "Your diary entries show that recorded tasks were mostly incomplete."
        )
        action = "Choose the most urgent unfinished task and complete its first small step."

    elif productivity_signal == "high":
        message = (
            "Your diary entries show high self-rated productivity."
        )
        action = "Keep the same working pattern and include a short break after focused work."

    else:
        message = (
            "Your diary entries show mixed or stable patterns."
        )
        action = "Keep recording mood, productivity, and outcomes to build a clearer pattern."

    return {
        "feedback_type": "wellbeing_productivity",
        "mood_signal": mood_signal,
        "productivity_signal": productivity_signal,
        "message": message,
        "action": action,
        "evidence_ids": evidence_ids,
        "based_on_evidence_ids": evidence_ids,
        "abstained": False,
        "generation_method": (
            "rule_based_fallback" if fallback_reason else "rule_based"
        ),
        "fallback_reason": fallback_reason,
    }


_DIAGNOSIS_RE = re.compile(
    r"\b(?:diagnos(?:e|ed|is)|depression|anxiety disorder|bipolar|adhd|ptsd|"
    r"mental illness|personality disorder|clinical disorder|suicid(?:e|al))\b",
    re.IGNORECASE,
)
_NUMERIC_CLAIM_RE = re.compile(r"(?<![A-Za-z])\d+(?:\.\d+)?\s*%?")


def _feedback_prompt(
    *,
    mood_signal: str,
    productivity_signal: str,
    task_signal: str,
    evidence_ids: List[str],
) -> str:
    return (
        "Create brief, non-medical wellbeing and productivity feedback from the "
        "backend-calculated categorical signals below. Do not calculate statistics, "
        "introduce numbers, diagnose a condition, or add a factual premise not in the "
        "signals. Cite only supplied Evidence IDs. Return JSON only with exactly these "
        "keys: message, action, evidence_ids, abstained.\n\n"
        f"Mood signal: {mood_signal}\n"
        f"Productivity signal: {productivity_signal}\n"
        f"Task signal: {task_signal}\n"
        f"Verified Evidence IDs: {', '.join(evidence_ids)}"
    )


def _parse_feedback_json(raw_text: str) -> Dict[str, Any]:
    start = raw_text.find("{")
    end = raw_text.rfind("}")
    if start < 0 or end <= start:
        raise ValueError("feedback_json_not_found")
    parsed = json.loads(raw_text[start : end + 1])
    if not isinstance(parsed, dict):
        raise ValueError("feedback_json_must_be_object")
    required = {"message", "action", "evidence_ids", "abstained"}
    if not required.issubset(parsed):
        raise ValueError("feedback_json_missing_fields")
    if not isinstance(parsed["message"], str) or not isinstance(parsed["action"], str):
        raise ValueError("feedback_text_fields_invalid")
    if not isinstance(parsed["evidence_ids"], list):
        raise ValueError("feedback_evidence_ids_invalid")
    if not isinstance(parsed["abstained"], bool):
        raise ValueError("feedback_abstained_invalid")
    return parsed


def _validate_slm_feedback(
    parsed: Dict[str, Any],
    *,
    verified_entries: List[DiaryEntryResponse],
    valid_evidence_ids: List[str],
    nli_runner: Optional[Callable[..., Any]] = None,
) -> Optional[str]:
    cited_ids = [str(value).strip() for value in parsed["evidence_ids"]]
    if any(evidence_id not in set(valid_evidence_ids) for evidence_id in cited_ids):
        return "feedback_contains_unverified_evidence_id"

    combined_text = f"{parsed['message']} {parsed['action']}"
    if _NUMERIC_CLAIM_RE.search(combined_text):
        return "feedback_introduced_numerical_claim"
    if _DIAGNOSIS_RE.search(combined_text):
        return "feedback_contains_medical_or_mental_health_diagnosis"
    if parsed["abstained"]:
        return None
    if not parsed["message"].strip() or not parsed["action"].strip():
        return "feedback_text_is_blank"

    # Only the message is treated as a factual premise; the action is advice.
    from .hallucination_evaluator import evaluate_plain_summary_groundedness

    evaluation = evaluate_plain_summary_groundedness(
        parsed["message"],
        verified_entries,
        nli_runner=nli_runner,
    )
    if evaluation.get("status") != "available":
        return "feedback_nli_validation_unavailable"
    if evaluation.get("unsupported_claim_rate") != 0.0:
        return "feedback_premise_not_entailed"
    return None


def generate_feedback_from_rag_evidence(
    retrieved_entries: List[DiaryEntryResponse],
    retrieved_evidence: List[Dict[str, Any]],
    *,
    use_slm: bool = False,
    nli_runner: Optional[Callable[..., Any]] = None,
) -> Dict[str, Any]:
    """Generate optional validated SLM feedback, or explicit rule-based fallback.

    Feedback is a separate feature and is never counted as one of the three
    summarization experiment conditions.
    """

    if not use_slm:
        return _generate_rule_based_feedback(retrieved_entries, retrieved_evidence)

    evidence_ids = _get_retrieved_evidence_ids(retrieved_evidence)
    if not retrieved_entries or not evidence_ids:
        return _generate_rule_based_feedback(
            retrieved_entries,
            retrieved_evidence,
            fallback_reason="no_verified_feedback_evidence",
        )

    mood_signal = _detect_mood_signal(retrieved_entries)
    productivity_signal = _detect_productivity_signal(retrieved_entries)
    task_signal = _detect_task_signal(retrieved_entries)
    try:
        from .summarizers import generate_text

        generated = generate_text(
            _feedback_prompt(
                mood_signal=mood_signal,
                productivity_signal=productivity_signal,
                task_signal=task_signal,
                evidence_ids=evidence_ids,
            ),
            prompt_version=FEEDBACK_PROMPT_VERSION,
            retrieved_evidence_ids=evidence_ids,
        )
        parsed = _parse_feedback_json(generated.text)
        validation_error = _validate_slm_feedback(
            parsed,
            verified_entries=retrieved_entries,
            valid_evidence_ids=evidence_ids,
            nli_runner=nli_runner,
        )
        if validation_error:
            raise ValueError(validation_error)
        cited_ids = list(dict.fromkeys(str(value).strip() for value in parsed["evidence_ids"]))
        return {
            "feedback_type": "wellbeing_productivity",
            "mood_signal": mood_signal,
            "productivity_signal": productivity_signal,
            "message": parsed["message"].strip(),
            "action": parsed["action"].strip(),
            "evidence_ids": cited_ids,
            "based_on_evidence_ids": cited_ids,
            "abstained": parsed["abstained"],
            "generation_method": "slm_verified",
            "fallback_reason": None,
            "generation": generated.metadata,
        }
    except Exception as error:
        return _generate_rule_based_feedback(
            retrieved_entries,
            retrieved_evidence,
            fallback_reason=f"slm_feedback_validation_failed:{type(error).__name__}",
        )
