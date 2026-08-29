from pydantic import BaseModel
from typing import List, Dict

class PrimaryBias(BaseModel):
    bias_type: str
    confidence: float

class AdditionalIndicator(BaseModel):
    type: str
    reason: str

class Comparison(BaseModel):
    claimed_duration: int
    verified_educational: int
    duration_gap: int
    claimed_location: str
    actual_location: str
    location_match: int
    app_switches: int
    social_media_minutes: int

class BiasAnalysisResponse(BaseModel):
    user_id: str
    entry_id: str
    primary_bias: PrimaryBias
    additional_indicators: List[AdditionalIndicator]
    pas_score: int
    pas_level: str
    comparison: Comparison
    reflection_text: str
    suggested_actions: List[str]
    is_recurring: bool = False
    streak_count: int = 1
    status: str = "success"