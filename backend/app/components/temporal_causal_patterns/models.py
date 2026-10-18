from pydantic import BaseModel, Field
from typing import List, Optional


# ─────────────────────────────────────────────
# REQUEST MODEL — diary entry input
# ─────────────────────────────────────────────

class DiaryEntryRequest(BaseModel):
    # userId comes automatically from localStorage
    userId: str = Field(..., description="User ID from localStorage")

    # Basic
    activityName: str = Field(..., description="Name of the activity")
    activityCategory: str = Field(..., description="Category of activity")

    # Time
    entryDate: str = Field(..., description="Date in YYYY-MM-DD format")
    startTime: str = Field(..., description="Start time in HH:MM format")
    endTime: Optional[str] = Field(None, description="End time in HH:MM format")
    timePeriod: Optional[str] = Field(None, description="Morning/Afternoon/Evening/Night")
    duration: Optional[str] = Field(None, description="Duration of activity")

    # Location
    locationType: Optional[str] = Field(None, description="Location type")
    customLocation: Optional[str] = Field(None, description="Custom location name")

    # Social
    withWhom: Optional[str] = Field(None, description="Alone/Partner/Friends/Group")

    specificPerson: Optional[str] = Field(None, description="Specific person name")

    # Well-being
    moodBefore: Optional[str] = Field(None, description="Mood before activity")
    moodAfter: Optional[str] = Field(None, description="Mood after activity")
    healthStatus: Optional[str] = Field(None, description="Health status")

    # Performance
    productivityLevel: Optional[str] = Field(None, description="Low/Medium/High")
    taskOutcome: Optional[str] = Field(None, description="Task outcome")

    # Notes
    notes: Optional[str] = Field(None, description="Additional context")

    class Config:
        json_schema_extra = {
            "example": {
                "userId": "U001",
                "activityName": "party",
                "activityCategory": "Entertainment",
                "entryDate": "2026-05-09",
                "startTime": "19:30",
                "endTime": "22:30",
                "timePeriod": "Night",
                "duration": "3 hours",
                "locationType": "Public",
                "customLocation": "Monach Imperial",
                "withWhom": "Group",
                "moodBefore": "Tired",
                "moodAfter": "Happy",
                "healthStatus": "Normal",
                "productivityLevel": "High",
                "taskOutcome": "Completed",
                "notes": "Met all school friends, enjoyable night"
            }
        }


# ─────────────────────────────────────────────
# RESPONSE MODEL — diary entry insert result
# ─────────────────────────────────────────────

class DiaryEntryResponse(BaseModel):
    entryId: str
    userId: str
    status: str
    message: str


# ─────────────────────────────────────────────
# RESPONSE MODEL — single pattern result
# ─────────────────────────────────────────────

class PatternResult(BaseModel):
    insightText: str
    trigger: str
    outcome: str
    matchedCount: int
    totalTriggerCount: int
    confidencePercentage: float
    patternLevel: str
    evidenceDates: list[str]
    dfsScore: Optional[float] = None
    louvainScore: Optional[float] = None
    fftScore: Optional[float] = None
    htgpsScore: Optional[float] = None
    dfsExplanation: Optional[str] = None
    louvainExplanation: Optional[str] = None
    fftExplanation: Optional[str] = None
    analysisVersion: Optional[str] = None


# ─────────────────────────────────────────────
# RESPONSE MODEL — full analysis response
# ─────────────────────────────────────────────

class AnalyseResponse(BaseModel):
    userId: str
    totalPatternsFound: int
    patterns: List[PatternResult]
    message: str


# ─────────────────────────────────────────────
# RESPONSE MODEL — get saved patterns
# ─────────────────────────────────────────────

class GetPatternsResponse(BaseModel):
    userId: str
    totalEntries: int
    message: str