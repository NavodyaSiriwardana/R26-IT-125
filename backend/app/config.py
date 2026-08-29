# for Rag_summary
from __future__ import annotations
import os
from dataclasses import dataclass
from typing import Optional

from dotenv import load_dotenv


load_dotenv()


@dataclass(frozen=True)
class Settings:
    # App settings
    APP_NAME: str = "Intelligent Diary API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = os.getenv("DEBUG", "true").strip().casefold() == "true"

    # Neo4j AuraDB settings. Dev note :- Remove the optional typing after integration
    NEO4J_URI: str | None = os.getenv("NEO4J_URI")
    NEO4J_USERNAME: str | None = os.getenv("NEO4J_USERNAME")
    NEO4J_PASSWORD: str | None = os.getenv("NEO4J_PASSWORD")
    NEO4J_DATABASE: str = os.getenv("NEO4J_DATABASE", "neo4j")

# Rag_summary related config
def _optional_env(name: str) -> Optional[str]:
    value = os.getenv(name)
    return value.strip() if value and value.strip() else None


def _positive_int_env(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as error:
        raise ValueError(f"{name} must be an integer.") from error

    if value <= 0:
        raise ValueError(f"{name} must be greater than zero.")
    return value


def _float_env(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError as error:
        raise ValueError(f"{name} must be numeric.") from error


@dataclass(frozen=True)
class GenerationSettings:
    model_name: str = os.getenv("SLM_MODEL_NAME", "google/flan-t5-large")
    model_revision: Optional[str] = _optional_env("SLM_MODEL_REVISION")
    max_new_tokens: int = _positive_int_env("SLM_MAX_NEW_TOKENS", 160)
    # FLAN-T5's supported encoder window is 512 tokens. Longer weekly inputs
    # are handled by the summarizer's batching + consolidation pipeline.
    max_input_tokens: int = _positive_int_env("SLM_MAX_INPUT_TOKENS", 512)
    random_seed: int = int(os.getenv("SLM_RANDOM_SEED", "42"))
    do_sample: bool = False
    num_beams: int = 1


@dataclass(frozen=True)
class EvaluationSettings:
    nli_model_name: str = os.getenv(
        "NLI_MODEL_NAME",
        "cross-encoder/nli-deberta-v3-base",
    )
    nli_model_revision: Optional[str] = _optional_env("NLI_MODEL_REVISION")
    entailment_threshold: float = _float_env("NLI_ENTAILMENT_THRESHOLD", 0.70)
    bertscore_model_name: str = os.getenv(
        "BERTSCORE_MODEL_NAME",
        "distilbert-base-uncased",
    )


GENERATION_SETTINGS = GenerationSettings()
EVALUATION_SETTINGS = EvaluationSettings()

PLAIN_PROMPT_VERSION = "plain-raw-week-paragraph-v5"
RAG_PROMPT_VERSION = "rag-query-aware-cited-paragraph-v6"
# Retained only for compatibility with the optional legacy evaluator. The
# interactive and primary research paths no longer regenerate or reject claims.
RAG_REGENERATION_PROMPT_VERSION = "legacy-rag-regeneration-v2"
FEEDBACK_PROMPT_VERSION = "structured-feedback-json-v2"
SUMMARY_SCHEMA_VERSION = "3.1"


settings = Settings()
