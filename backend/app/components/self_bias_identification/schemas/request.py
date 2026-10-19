from pydantic import BaseModel, Field
from typing import Optional, Dict, Literal

class DiaryEntry(BaseModel):
    entry_id: str
    user_id: str
    claimed_activity: str = ""
    activity_category: str = ""
    claimed_start_time: str = ""
    claimed_end_time: str = ""
    claimed_duration_minutes: int = 0
    claimed_location: str = ""
    productivity_level: str = ""
    completion_status: str = ""
    with_whom: str = ""
    mood_before: str = ""   # ← Fix
    mood_after: str = ""    # ← Fix
    health_status: str = ""
    diary_text: str = ""

class SensorData(BaseModel):
    entry_id: str
    user_id: str
    verified_educational_minutes: int = 0
    social_media_minutes: int = 0
    entertainment_minutes: int = 0
    distraction_duration: int = 0
    app_switch_count: int = 0
    gps_location: str = ""
    # 1 = event found, 0 = checked and none found, -1 = not checked
    calendar_match: int = -1
    facial_emotion: Optional[dict] = None
    # Per-app source breakdown for the verified totals above — display only,
    # not used by the classifier or the PAS formula.
    educational_breakdown: Dict[str, float] = {}
    entertainment_breakdown: Dict[str, float] = {}
    social_media_breakdown: Dict[str, float] = {}

class LocationRequest(BaseModel):
    name: str
    lat: float
    lng: float
    radius_m: float

class EntryLocationRequest(BaseModel):
    """Where the phone was when a diary entry was written."""
    source_doc_id: str
    lat: float
    lng: float
    accuracy_m: float | None = None
    place_name: str = ""
    place_types: list[str] = []
    age_at_capture_hours: float | None = None
    captured_at: str = ""

class MoodResetRequest(BaseModel):
    entry_id: str = ""
    before_stress: float
    before_mood: str = ""
    after_facial: Optional[dict] = None
    duration_seconds: int = 0
    rounds_completed: int = 0
    # Research-study fields. Self-reported stress is the ground truth the
    # facial stress score is validated against (1 = very calm, 5 = very stressed).
    self_before: Optional[int] = Field(default=None, ge=1, le=5)
    self_after: Optional[int] = Field(default=None, ge=1, le=5)
    # "breathing" = guided 4-7-8; "control" = quiet rest of the same length.
    condition: Literal["breathing", "control"] = "breathing"
    study_mode: bool = False


class ConsentRequest(BaseModel):
    agreed: bool
    version: str = "v1"
    study_mode: bool = False

class BiasAnalysisRequest(BaseModel):
    diary_entry: DiaryEntry
    sensor_data: SensorData