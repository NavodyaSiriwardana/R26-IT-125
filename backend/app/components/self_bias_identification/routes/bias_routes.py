from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query
from app.components.self_bias_identification.schemas.request import BiasAnalysisRequest, ConsentRequest, EntryLocationRequest, LocationRequest, MoodResetRequest
from app.components.self_bias_identification.services.privacy import strip_face_images
from app.components.self_bias_identification.services.mood_support import MoodSupport
from app.components.self_bias_identification.services import location_check
from app.components.self_bias_identification.services.orchestrator import BiasDetectionOrchestrator
from app.components.self_bias_identification.services.reflection_bot import ReflectionBot
from app.components.self_bias_identification.services.firebase_service import FirebaseService
from app.components.self_bias_identification.services.facial_service import analyze_facial_expression
from app.components.self_bias_identification.services.diary_entry_mapper import (
    STALE_ENTRY_HOURS,
    entry_age_hours,
    map_leader_entry,
)

router = APIRouter()
orchestrator = BiasDetectionOrchestrator()
reflection_bot = ReflectionBot()
firebase = FirebaseService()
mood_support = MoodSupport()


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
    mood = mood_support.build(
        facial_emotion=sensor_data.get("facial_emotion"),
        mood_before=diary_entry.get("mood_before") or "",
        mood_after=diary_entry.get("mood_after") or "",
        claimed_duration=diary_entry.get("claimed_duration_minutes") or 0,
        history=history,
    )
    return {
        "user_id": diary_entry.get("user_id", ""),
        "entry_id": diary_entry.get("entry_id", ""),
        "source_doc_id": diary_entry.get("source_doc_id", ""),
        "mood_support": mood,
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
    diary_entry = request.diary_entry.model_dump()
    sensor_data = request.sensor_data.model_dump()
    # Face images are for on-device display only — never analysed further or stored.
    sensor_data["facial_emotion"] = strip_face_images(sensor_data.get("facial_emotion"))
    response = _run_analysis(diary_entry, sensor_data)

    saved = all([
        firebase.save_diary_entry(diary_entry),
        firebase.save_sensor_data(sensor_data),
        firebase.save_bias_result(response),
    ])
    response["saved"] = saved

    return response


def _diary_state(user_id: str) -> dict:
    """What the student's latest diary entry means for an analysis.

    `none`: no entry at all. `analyzed`: it was analysed before (`existing`
    holds that result). `stale`: too old to compare with the phone's recent
    data. `new`: fresh and not analysed yet, so it can be analysed.
    """
    leader_doc = firebase.get_latest_diary_entry(user_id)
    if leader_doc is None:
        return {"state": "none", "doc": None, "age": None, "existing": None}
    age = entry_age_hours(leader_doc)
    existing = firebase.find_result_for_diary_entry(user_id, leader_doc.get("_doc_id", ""))
    if existing is not None:
        return {"state": "analyzed", "doc": leader_doc, "age": age, "existing": existing}
    if age is not None and age > STALE_ENTRY_HOURS:
        return {"state": "stale", "doc": leader_doc, "age": age, "existing": None}
    return {"state": "new", "doc": leader_doc, "age": age, "existing": None}


@router.get("/diary-status/{user_id}")
async def diary_status(user_id: str):
    """A quick look at the latest diary entry, so the app knows before it starts
    whether an analysis will happen or only a face check is possible."""
    st = _diary_state(user_id)
    doc = st["doc"] or {}
    return {
        "state": st["state"],
        "entry_age_hours": st["age"],
        "source_doc_id": doc.get("_doc_id", ""),
        # The app captures the phone's position only while this is true.
        "location_capture_open": (
            st["state"] == "new"
            and st["age"] is not None
            and st["age"] <= location_check.LOCATION_WINDOW_HOURS
        ),
    }


@router.post("/entry-location/{user_id}")
async def save_entry_location(user_id: str, request: EntryLocationRequest):
    """Where the phone was right after a diary entry was written. Used later
    to check the place the student claimed, with nothing saved by hand."""
    data = request.model_dump()
    data["captured_at"] = data["captured_at"] or datetime.now(timezone.utc).isoformat()
    saved = firebase.save_entry_location(user_id, request.source_doc_id, data)
    return {"status": "success" if saved else "error"}


def _location_check_for(user_id: str, diary_entry: dict, age) -> dict | None:
    """The location result for an entry, or None to keep the old behaviour
    (the live position read while analysing)."""
    claimed = diary_entry.get("claimed_location")
    evidence = firebase.get_entry_location(user_id, diary_entry.get("source_doc_id", ""))
    if evidence:
        return location_check.evaluate(
            claimed, evidence, firebase.get_user_locations(user_id)
        )
    if age is not None and age > location_check.LOCATION_WINDOW_HOURS:
        # No capture, and "where the phone is now" says nothing about where the
        # activity was this long ago.
        return location_check.evaluate(claimed, {"age_at_capture_hours": age})
    return None


@router.post("/analyze-from-diary/{user_id}")
async def analyze_from_shared_diary(user_id: str, request: dict):
    """Same analysis pipeline as /analyze, but the "claimed" side comes
    from the team's shared diaryEntries collection (the group leader's
    single-template requirement) instead of a form submission from this
    component. Only sensor_data (from this component's own Facial
    Capture + auto sensor collection) is sent by the frontend."""
    st = _diary_state(user_id)

    if st["state"] == "none":
        return {"status": "no_entry_found", "reason": "none"}

    # The same diary entry is analysed once. Pressing analyze again shows the
    # saved result.
    if st["state"] == "analyzed":
        return {"status": "already_analyzed", "result": st["existing"]}

    # An entry too old to compare with the phone's last few hours is not a new
    # entry: report it as "no entry" so the app can offer the face check
    # instead of a misleading bias result.
    if st["state"] == "stale":
        return {"status": "no_entry_found", "reason": "stale", "entry_age_hours": st["age"]}

    leader_doc, age = st["doc"], st["age"]
    diary_entry = map_leader_entry(leader_doc)
    sensor_data = request.get("sensor_data") or {}
    sensor_data["facial_emotion"] = strip_face_images(sensor_data.get("facial_emotion"))
    checked_location = _location_check_for(user_id, diary_entry, age)
    if checked_location is not None:
        sensor_data["location_check"] = checked_location
    response = _run_analysis(diary_entry, sensor_data)
    response["entry_age_hours"] = age
    response["stale_entry"] = age is not None and age > STALE_ENTRY_HOURS

    sensor_data_with_ids = {
        **sensor_data,
        "entry_id": diary_entry["entry_id"],
        "user_id": user_id,
    }
    saved = all([
        firebase.save_sensor_data(sensor_data_with_ids),
        firebase.save_bias_result(response),
    ])
    response["saved"] = saved

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
async def get_history(user_id: str, limit: int = Query(10, ge=1, le=200)):
    """Newest-first. The default of 10 keeps the existing screens as they
    were; the history pages ask for more. A Firestore failure is a 503, not an
    empty list, so the app can tell "no entries yet" from "could not load"."""
    try:
        history = firebase.get_user_history(user_id, limit=limit, strict=True)
    except Exception:
        raise HTTPException(status_code=503, detail="History is temporarily unavailable")
    return {"user_id": user_id, "history": history}


@router.post("/face-check/{user_id}")
async def face_check(user_id: str, request: dict):
    """A camera scan with no diary entry to compare against: gives Mood
    Support from the face reading alone. No bias type and no PAS score, and it
    is stored apart from bias results so those statistics stay clean."""
    facial = strip_face_images(request.get("facial_emotion"))
    if not isinstance(facial, dict) or facial.get("status") != "success":
        return {"status": "no_face"}

    past = (
        firebase.get_recent_history(user_id, limit=5)
        + firebase.get_face_checks(user_id, limit=5)
    )
    past.sort(key=lambda r: r.get("created_at", ""), reverse=True)
    mood = mood_support.build(
        facial_emotion=facial,
        mood_before="",
        mood_after="",
        claimed_duration=0,
        history=past[:5],
    )
    entry_id = f"FACE_{int(datetime.now(timezone.utc).timestamp() * 1000)}"
    saved = bool(firebase.save_face_check({
        "user_id": user_id,
        "entry_id": entry_id,
        "kind": "face_only",
        "comparison": {"facial_emotion": facial},
        "mood_support": mood,
    }))
    return {
        "status": "success",
        "user_id": user_id,
        "entry_id": entry_id,
        "facial_emotion": facial,
        "mood_support": mood,
        "saved": saved,
    }


@router.get("/face-checks/{user_id}")
async def get_face_checks(user_id: str, limit: int = Query(20, ge=1, le=200)):
    try:
        checks = firebase.get_face_checks(user_id, limit=limit, strict=True)
    except Exception:
        raise HTTPException(status_code=503, detail="Face checks are temporarily unavailable")
    return {"user_id": user_id, "checks": checks}


@router.post("/mood-reset/{user_id}")
async def save_mood_reset(user_id: str, request: MoodResetRequest):
    """Compares the stress reading taken before a Mood Reset with a fresh
    camera reading taken right after it, and stores both."""
    after_facial = strip_face_images(request.after_facial)
    evaluation = mood_support.evaluate_reset(request.before_stress, after_facial)
    after_stress = evaluation["after_mood"]["stress"]
    saved = bool(firebase.save_mood_reset({
        "user_id": user_id,
        "entry_id": request.entry_id,
        "condition": request.condition,
        "study_mode": request.study_mode,
        "before_stress": request.before_stress,
        "before_mood": request.before_mood,
        "after_stress": after_stress,
        "after_mood": evaluation["after_mood"]["label"],
        "self_before": request.self_before,
        "self_after": request.self_after,
        "delta_points": evaluation["delta_points"],
        "outcome": evaluation["outcome"],
        "duration_seconds": request.duration_seconds,
        "rounds_completed": request.rounds_completed,
    }))
    return {"status": "success", "saved": saved, **evaluation}


@router.post("/consent/{user_id}")
async def record_consent(user_id: str, request: ConsentRequest):
    ok = firebase.save_consent(
        user_id, request.agreed, request.version, request.study_mode
    )
    return {"status": "success" if ok else "error"}


@router.get("/consent/{user_id}")
async def get_consent(user_id: str):
    consent = firebase.get_consent(user_id)
    return {"user_id": user_id, "consent": consent}


@router.delete("/participant/{user_id}/data")
async def delete_participant_data(user_id: str):
    """Withdrawal: deletes everything this component stored about the user.
    The shared diaryEntries collection (another component's) is untouched."""
    return {"status": "success", "deleted": firebase.delete_user_data(user_id)}


@router.get("/mood-resets/{user_id}")
async def get_mood_resets(user_id: str, limit: int = Query(20, ge=1, le=200)):
    try:
        resets = firebase.get_mood_resets(user_id, limit=limit, strict=True)
    except Exception:
        raise HTTPException(status_code=503, detail="Mood resets are temporarily unavailable")
    return {"user_id": user_id, "resets": resets}


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
async def save_location(user_id: str, request: LocationRequest):
    firebase.save_location(
        user_id=user_id,
        name=request.name,
        lat=request.lat,
        lng=request.lng,
        radius_m=request.radius_m,
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