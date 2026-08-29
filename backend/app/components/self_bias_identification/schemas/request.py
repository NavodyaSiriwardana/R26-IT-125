from pydantic import BaseModel
from typing import Optional, Dict

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
    calendar_match: int = 0
    facial_emotion: Optional[dict] = None
    # Per-app source breakdown for the verified totals above — display only,
    # not used by the classifier or the PAS formula.
    educational_breakdown: Dict[str, float] = {}
    entertainment_breakdown: Dict[str, float] = {}
    social_media_breakdown: Dict[str, float] = {}

class BiasAnalysisRequest(BaseModel):
    diary_entry: DiaryEntry
    sensor_data: SensorData