from fastapi import APIRouter
from app.components.self_bias_identification.schemas.request import BiasAnalysisRequest
from app.components.self_bias_identification.services.orchestrator import BiasDetectionOrchestrator
from app.components.self_bias_identification.services.reflection_bot import ReflectionBot
from app.components.self_bias_identification.services.firebase_service import FirebaseService
from app.components.self_bias_identification.services.facial_service import analyze_facial_expression
from app.components.self_bias_identification.services.diary_entry_mapper import map_leader_entry

router = APIRouter()
orchestrator = BiasDetectionOrchestrator()
reflection_bot = ReflectionBot()
firebase = FirebaseService()


def _run_analysis(diary_entry: dict, sensor_data: dict) -> dict:
    """Shared by /analyze and /analyze-from-diary — both end up with the
    same diary_entry/sensor_data shape (the latter only after mapping),
    so the actual classification + reflection logic is written once."""
    result = orchestrator.analyze(
        diary_entry=diary_entry,
        sensor_data=sensor_data,
    )
    history = firebase.get_recent_history(
        diary_entry.get("user_id", ""), limit=5
    )
    reflection = reflection_bot.generate(
        bias_type=result["primary_bias"]["bias_type"],
        comparison=result["comparison"],
        pas_score=result["pas_score"],
        history=history,
    )
    return {
        "user_id": diary_entry.get("user_id", ""),
        "entry_id": diary_entry.get("entry_id", ""),
        "primary_bias": result["primary_bias"],
        "additional_indicators": result["additional_indicators"],
        "pas_score": result["pas_score"],
        "pas_level": result["pas_level"],
        "comparison": result["comparison"],
        "reflection_text": reflection["reflection_text"],
        "suggested_actions": reflection["suggested_actions"],
        "is_recurring": reflection["is_recurring"],
        "streak_count": reflection["streak_count"],
        "status": "success",
    }


@router.post("/analyze")
async def analyze_bias(request: BiasAnalysisRequest):
    diary_entry = request.diary_entry.dict()
    sensor_data = request.sensor_data.dict()
    response = _run_analysis(diary_entry, sensor_data)

    firebase.save_diary_entry(diary_entry)
    firebase.save_sensor_data(sensor_data)
    firebase.save_bias_result(response)

    return response


@router.post("/analyze-from-diary/{user_id}")
async def analyze_from_shared_diary(user_id: str, request: dict):
    """Same analysis pipeline as /analyze, but the "claimed" side comes
    from the team's shared diaryEntries collection (the group leader's
    single-template requirement) instead of a form submission from this
    component. Only sensor_data (from this component's own Facial
    Capture + auto sensor collection) is sent by the frontend."""
    leader_doc = firebase.get_latest_diary_entry(user_id)
    if leader_doc is None:
        return {"status": "no_entry_found"}

    diary_entry = map_leader_entry(leader_doc)
    sensor_data = request.get("sensor_data", {})
    response = _run_analysis(diary_entry, sensor_data)

    sensor_data_with_ids = {
        **sensor_data,
        "entry_id": diary_entry["entry_id"],
        "user_id": user_id,
    }
    firebase.save_sensor_data(sensor_data_with_ids)
    firebase.save_bias_result(response)

    return response


@router.post("/test-create-diary-entry")
async def test_create_diary_entry(request: dict):
    """Testing-only: writes a document into the shared diaryEntries
    collection in the leader's exact schema, so /analyze-from-diary can
    be tested end to end without needing the leader's separate
    app/codebase installed anywhere."""
    entry_id = firebase.create_test_diary_entry(request)
    return {"status": "success" if entry_id else "error", "id": entry_id}


@router.get("/history/{user_id}")
async def get_history(user_id: str):
    history = firebase.get_user_history(user_id)
    return {"user_id": user_id, "history": history}


@router.get("/weekly/{user_id}")
async def get_weekly(user_id: str):
    return firebase.get_weekly_summary(user_id)


@router.get("/health")
async def health():
    return {"status": "Bias Detection API running ✅"}


@router.get("/locations/{user_id}")
async def get_locations(user_id: str):
    return {"locations": firebase.get_user_locations(user_id)}


@router.post("/locations/{user_id}")
async def save_location(user_id: str, request: dict):
    firebase.save_location(
        user_id=user_id,
        name=request["name"],
        lat=request["lat"],
        lng=request["lng"],
        radius_m=request["radius_m"],
    )
    return {"status": "success"}


@router.delete("/locations/{user_id}/{name}")
async def delete_location(user_id: str, name: str):
    firebase.delete_location(user_id, name)
    return {"status": "success"}


@router.post("/facial/analyze")
async def facial_analyze(request: dict):
    image_base64 = request.get("image_base64")
    if not image_base64:
        return {"status": "error", "message": "No image provided"}

    result = analyze_facial_expression(image_base64)
    return result